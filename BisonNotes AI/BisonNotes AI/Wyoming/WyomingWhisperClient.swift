//
//  WyomingWhisperClient.swift
//  Audio Journal
//
//  Wyoming protocol client specifically for Whisper transcription
//

import Foundation
import AVFoundation
import UIKit

@MainActor
class WyomingWhisperClient: ObservableObject {
    
    // MARK: - Properties
    
    @Published var isConnected = false
    @Published var connectionError: String?
    @Published var isTranscribing = false
    @Published var currentStatus = ""
    @Published var progress: Double = 0.0
    
    private let tcpClient: WyomingTCPClient
    private let config: WhisperConfig
    private var currentTranscription: CheckedContinuation<TranscriptionResult, Error>?
    private var transcriptionResult = ""
    private var serverInfo: WyomingInfoData?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var streamingTimeoutTask: Task<Void, Never>?
    
    // MARK: - Initialization
    
    init(config: WhisperConfig) {
        self.config = config
        
        // Extract host from server URL
        let host = Self.extractHost(from: config.serverURL)
        print("🔗 Wyoming TCP connection: \(host):\(config.port)")
        
        self.tcpClient = WyomingTCPClient(host: host, port: config.port)
        setupMessageHandlers()
    }
    
    private static func extractHost(from serverURL: String) -> String {
        var url = serverURL
        
        // Remove any protocol scheme
        if let range = url.range(of: "://") {
            url = String(url[range.upperBound...])
        }
        
        // Remove any path
        if let range = url.range(of: "/") {
            url = String(url[..<range.lowerBound])
        }
        
        // Remove any port (we'll use the config port)
        if let range = url.range(of: ":") {
            url = String(url[..<range.lowerBound])
        }
        
        return url.isEmpty ? "localhost" : url
    }
    
    // MARK: - Message Handlers
    
    private func setupMessageHandlers() {
        // Handle server info responses
        tcpClient.registerHandler(for: .info) { [weak self] message in
            Task { @MainActor in
                await self?.handleInfoMessage(message)
            }
        }
        
        // Handle transcription results
        tcpClient.registerHandler(for: .transcript) { [weak self] message in
            Task { @MainActor in
                await self?.handleTranscriptMessage(message)
            }
        }
        
        // Handle errors
        tcpClient.registerHandler(for: .error) { [weak self] message in
            Task { @MainActor in
                await self?.handleErrorMessage(message)
            }
        }
    }
    
    private func handleInfoMessage(_ message: WyomingMessage) async {
        guard let infoData = message.parseData(as: WyomingInfoData.self) else {
            print("⚠️ Failed to parse info message")
            return
        }
        
        serverInfo = infoData
        print("ℹ️ Wyoming server info received:")
        
        if let asrInfo = infoData.asr?.first {
            print("   - ASR: \(asrInfo.name)")
            print("   - Version: \(asrInfo.version ?? "unknown")")
            print("   - Models: \(asrInfo.models?.count ?? 0)")
        }
        
        isConnected = true
        connectionError = nil
    }
    
    private func handleTranscriptMessage(_ message: WyomingMessage) async {
        guard let transcriptData = message.parseData(as: WyomingTranscriptData.self) else {
            print("⚠️ Failed to parse transcript message")
            return
        }
        
        print("📝 Received transcription: \(transcriptData.text.prefix(100))...")
        transcriptionResult = transcriptData.text
        
        // Complete the transcription
        if let continuation = currentTranscription {
            let result = TranscriptionResult(
                fullText: transcriptData.text,
                segments: [TranscriptSegment(
                    speaker: "Speaker",
                    text: transcriptData.text,
                    startTime: 0.0,
                    endTime: 0.0
                )],
                processingTime: 0.0,
                chunkCount: 1,
                success: true,
                error: nil
            )
            
            continuation.resume(returning: result)
            currentTranscription = nil
            
            isTranscribing = false
            currentStatus = "Transcription completed"
            progress = 1.0
            
            // Clean up background task and timeout
            cancelStreamingTimeout()
            endBackgroundTask()
        }
    }
    
    private func handleErrorMessage(_ message: WyomingMessage) async {
        guard let errorData = message.parseData(as: WyomingErrorData.self) else {
            print("⚠️ Failed to parse error message")
            return
        }
        
        print("❌ Wyoming server error: \(errorData.code) - \(errorData.message)")
        
        if let continuation = currentTranscription {
            let error = WyomingError.serverError("\(errorData.code): \(errorData.message)")
            continuation.resume(throwing: error)
            currentTranscription = nil
        }
        
        isTranscribing = false
        currentStatus = "Error: \(errorData.message)"
        connectionError = errorData.message
        
        // Clean up background task and timeout on error
        cancelStreamingTimeout()
        endBackgroundTask()
    }
    
    // MARK: - Connection Management
    
    func testConnection() async -> Bool {
        do {
            print("🔌 Wyoming client testing TCP connection...")
            try await tcpClient.connect()
            print("✅ Wyoming TCP connected, sending describe message...")
            
            // Send describe message to get server info
            try await tcpClient.sendDescribe()
            
            // Wait a bit for the info response
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            
            await MainActor.run {
                self.isConnected = true
                self.connectionError = nil
            }
            
            print("✅ Wyoming connection test passed")
            return true
            
        } catch {
            print("❌ Wyoming connection test failed: \(error)")
            await MainActor.run {
                connectionError = error.localizedDescription
                isConnected = false
            }
            return false
        }
    }
    
    func disconnect() {
        tcpClient.disconnect()
        isConnected = false
        connectionError = nil
    }
    
    // MARK: - Transcription
    
    func transcribeAudio(url: URL, recordingId: UUID? = nil) async throws -> TranscriptionResult {
        print("🎤 WyomingWhisperClient.transcribeAudio called for: \(url.lastPathComponent)")
        
        // Check if file is longer than 5 minutes and needs chunking
        let duration = try await getAudioDuration(url: url)
        let maxChunkDuration: TimeInterval = 300 // 5 minutes
        
        if duration > maxChunkDuration {
            print("📏 Audio duration (\(Int(duration))s) exceeds \(Int(maxChunkDuration))s, using chunked transcription")
            return try await transcribeAudioWithChunking(url: url, recordingId: recordingId, maxChunkDuration: maxChunkDuration)
        } else {
            print("📏 Audio duration (\(Int(duration))s) is within limits, using standard transcription")
            return try await transcribeAudioStandard(url: url, recordingId: recordingId)
        }
    }
    
    private func transcribeAudioStandard(url: URL, recordingId: UUID? = nil) async throws -> TranscriptionResult {
        print("🎤 WyomingWhisperClient.transcribeAudioStandard called for: \(url.lastPathComponent)")
        
        // Start background task for long-running transcription
        print("🔍 DEBUG: About to call beginBackgroundTask()")
        beginBackgroundTask()
        print("🔍 DEBUG: beginBackgroundTask completed successfully")
        
        // Ensure we're connected
        if !isConnected {
            let connected = await testConnection()
            if !connected {
                endBackgroundTask()
                throw WyomingError.connectionFailed
            }
        }
        
        isTranscribing = true
        currentStatus = "Starting transcription..."
        progress = 0.0
        transcriptionResult = ""
        
        // Start timeout for large files (estimate 1 minute per 5MB of audio)
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        print("📁 File size: \(fileSize) bytes (\(Double(fileSize) / (1024 * 1024))MB)")
        print("🔍 DEBUG: About to calculate timeout for file size: \(fileSize)")
        
        // Safely calculate timeout with bounds checking
        let fileSizeMB = Double(fileSize) / (1024.0 * 1024.0)
        let estimatedMinutes = max(5.0, fileSizeMB / 5.0) // Minimum 5 min, 1 min per 5MB
        let estimatedSeconds = min(estimatedMinutes * 60.0, 3600.0) // Cap at 1 hour
        
        // Ensure the value is within Int range before converting
        let safeEstimatedSeconds = min(estimatedSeconds, Double(Int.max - 1))
        let timeoutSeconds: Int
        
        if safeEstimatedSeconds.isFinite && safeEstimatedSeconds >= 0 {
            timeoutSeconds = Int(safeEstimatedSeconds)
        } else {
            // Fallback to default timeout if calculation failed
            print("⚠️ Timeout calculation failed, using default 300 seconds")
            timeoutSeconds = 300
        }
        
        print("⏰ Setting Wyoming timeout: \(timeoutSeconds) seconds (\(timeoutSeconds/60) minutes)")
        print("🔍 DEBUG: About to call startStreamingTimeout with: \(timeoutSeconds)")
        
        startStreamingTimeout(seconds: timeoutSeconds)
        print("🔍 DEBUG: startStreamingTimeout completed successfully")
        
        do {
            return try await withCheckedThrowingContinuation { continuation in
                currentTranscription = continuation
                
                Task {
                    do {
                        try await performWyomingTranscription(url: url)
                    } catch {
                        await MainActor.run {
                            self.isTranscribing = false
                            self.currentStatus = "Transcription failed"
                            self.currentTranscription = nil
                            self.cancelStreamingTimeout()
                            self.endBackgroundTask()
                        }
                        continuation.resume(throwing: error)
                    }
                }
            }
        } catch {
            cancelStreamingTimeout()
            endBackgroundTask()
            throw error
        }
    }
    
    private func performWyomingTranscription(url: URL) async throws {
        do {
            // Step 1: Send transcribe command
            currentStatus = "Sending transcription request..."
            progress = 0.1
            
            try await tcpClient.sendTranscribe(language: "en")
            
            // Step 2: Send audio start
            currentStatus = "Starting audio stream..."
            progress = 0.2
            
            try await tcpClient.sendAudioStart()
            
            // Step 3: Stream audio data
            currentStatus = "Streaming audio data..."
            progress = 0.3
            
            try await streamAudioFile(url: url)
            
            // Step 4: Send audio stop
            currentStatus = "Finishing audio stream..."
            progress = 0.9
            
            try await tcpClient.sendAudioStop()
            
            currentStatus = "Waiting for transcription..."
            // The completion will be handled by handleTranscriptMessage
            
        } catch {
            print("❌ Wyoming transcription error: \(error)")
            
            // Attempt recovery for network errors
            if let wyomingError = error as? WyomingError,
               case .connectionFailed = wyomingError {
                print("🔄 Attempting Wyoming connection recovery...")
                
                do {
                    // Disconnect and reconnect
                    tcpClient.disconnect()
                    try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                    
                    let reconnected = await testConnection()
                    if reconnected {
                        print("✅ Wyoming connection recovered, retrying transcription...")
                        currentStatus = "Connection recovered, retrying..."
                        
                        // Retry the transcription once
                        try await performWyomingTranscription(url: url)
                        return
                    }
                } catch {
                    print("❌ Wyoming connection recovery failed: \(error)")
                }
            }
            
            // If we get here, the original error couldn't be recovered
            throw error
        }
    }
    
    private func streamAudioFile(url: URL) async throws {
        // Convert audio file to PCM data for Wyoming
        let audioData = try await convertToPCMData(url: url)
        
        // Optimize chunk size based on file size
        let chunkSize: Int
        if audioData.count > 50_000_000 { // > 50MB
            chunkSize = 65536 // 64KB chunks for large files
        } else if audioData.count > 10_000_000 { // > 10MB
            chunkSize = 32768 // 32KB chunks for medium files
        } else {
            chunkSize = 16384 // 16KB chunks for small files
        }
        
        let totalChunks = (audioData.count + chunkSize - 1) / chunkSize
        
        print("🔄 Streaming \(audioData.count) bytes in \(totalChunks) chunks of \(chunkSize) bytes each")
        
        let startTime = Date()
        
        // Prepare chunks array for batch processing
        var chunks: [Data] = []
        chunks.reserveCapacity(totalChunks)
        
        for chunkIndex in 0..<totalChunks {
            let startIndex = chunkIndex * chunkSize
            let endIndex = min(startIndex + chunkSize, audioData.count)
            let chunk = audioData.subdata(in: startIndex..<endIndex)
            chunks.append(chunk)
        }
        
        // Send audio chunks using Wyoming protocol messages
        for (chunkIndex, chunk) in chunks.enumerated() {
            try await tcpClient.sendAudioChunk(chunk)
            
            let chunkProgress = Double(chunkIndex + 1) / Double(totalChunks)
            progress = 0.3 + (chunkProgress * 0.6) // Use 30%-90% for streaming
            
            // Comment out individual chunk progress logging to reduce log volume
            // let elapsed = Date().timeIntervalSince(startTime)
            // if elapsed > 0 {
            //     let rate = Double(chunkIndex + 1) / elapsed
            //     let safeRate = min(rate, Double(Int.max - 1))
            //     print("📤 Streaming progress: \(Int(chunkProgress * 100))% (\(chunkIndex + 1)/\(totalChunks) chunks) - \(Int(safeRate)) chunks/sec")
            // }
        }
        
        let totalTime = Date().timeIntervalSince(startTime)
        let avgRate = totalTime > 0 ? Double(totalChunks) / totalTime : 0
        let safeAvgRate = min(avgRate, Double(Int.max - 1))
        
        print("✅ Streamed \(totalChunks) audio chunks (\(audioData.count) bytes total) in \(String(format: "%.2f", totalTime))s at \(Int(safeAvgRate)) chunks/sec")
    }
    
    private func convertToPCMData(url: URL) async throws -> Data {
        print("🔄 Converting audio to PCM for Wyoming...")
        
        let asset = AVURLAsset(url: url)
        
        // Get audio track
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw WyomingError.serverError("No audio track found")
        }
        
        // Create asset reader
        let assetReader = try AVAssetReader(asset: asset)
        
        // Configure reader for PCM output (Wyoming format)
        let readerOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: WyomingConstants.audioSampleRate,  // 16kHz
            AVNumberOfChannelsKey: WyomingConstants.audioChannels,  // Mono
            AVLinearPCMBitDepthKey: WyomingConstants.audioBitDepth,  // 16-bit
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ])
        
        assetReader.add(readerOutput)
        assetReader.startReading()
        
        var pcmData = Data()
        
        while assetReader.status == .reading {
            if let sampleBuffer = readerOutput.copyNextSampleBuffer() {
                if let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
                    let length = CMBlockBufferGetDataLength(blockBuffer)
                    var data = Data(count: length)
                    
                    let result = data.withUnsafeMutableBytes { bytes in
                        CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: bytes.baseAddress!)
                    }
                    
                    if result != noErr {
                        print("⚠️ Warning: CMBlockBufferCopyDataBytes returned error: \(result)")
                    }
                    
                    pcmData.append(data)
                }
            } else {
                break
            }
        }
        
        if assetReader.status == .failed {
            if let error = assetReader.error {
                throw error
            } else {
                throw WyomingError.serverError("Audio conversion failed")
            }
        }
        
        print("✅ Converted to PCM: \(pcmData.count) bytes at \(WyomingConstants.audioSampleRate)Hz")
        return pcmData
    }
    
    // MARK: - Audio Duration and Chunking
    
    private func getAudioDuration(url: URL) async throws -> TimeInterval {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        return CMTimeGetSeconds(duration)
    }
    
    private func transcribeAudioWithChunking(url: URL, recordingId: UUID?, maxChunkDuration: TimeInterval) async throws -> TranscriptionResult {
        print("🎯 Starting chunked Wyoming transcription for: \(url.lastPathComponent)")
        
        // Start background task for long-running transcription
        beginBackgroundTask()
        
        // Get audio duration and calculate chunks
        let totalDuration = try await getAudioDuration(url: url)
        let numberOfChunks = Int(ceil(totalDuration / maxChunkDuration))
        
        print("📊 Audio duration: \(Int(totalDuration))s, splitting into \(numberOfChunks) chunks of \(Int(maxChunkDuration))s each")
        
        // Create temporary directory for chunks
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            // Clean up temporary files
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        var allSegments: [TranscriptSegment] = []
        var totalProcessingTime: TimeInterval = 0
        let startTime = Date()
        
        // Process each chunk
        for chunkIndex in 0..<numberOfChunks {
            let chunkStartTime = TimeInterval(chunkIndex) * maxChunkDuration
            let chunkEndTime = min(chunkStartTime + maxChunkDuration, totalDuration)
            let chunkDuration = chunkEndTime - chunkStartTime
            
            print("🔄 Processing chunk \(chunkIndex + 1)/\(numberOfChunks): \(Int(chunkStartTime))s - \(Int(chunkEndTime))s (\(Int(chunkDuration))s)")
            
            // Update progress
            currentStatus = "Processing chunk \(chunkIndex + 1) of \(numberOfChunks)..."
            progress = Double(chunkIndex) / Double(numberOfChunks)
            
            // Create audio chunk file
            let chunkURL = tempDir.appendingPathComponent("chunk_\(chunkIndex).m4a")
            try await createAudioChunk(sourceURL: url, outputURL: chunkURL, startTime: chunkStartTime, duration: chunkDuration)
            
            // Transcribe the chunk with fresh connection
            do {
                // Ensure fresh connection for each chunk to avoid Wyoming server issues
                if chunkIndex > 0 {
                    print("🔄 Resetting Wyoming connection for chunk \(chunkIndex + 1)")
                    tcpClient.disconnect()
                    try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
                    
                    // Re-register message handlers after disconnect (they get cleared)
                    setupMessageHandlers()
                    
                    // Test connection to ensure it's ready
                    let connected = await testConnection()
                    if !connected {
                        print("❌ Failed to establish connection for chunk \(chunkIndex + 1)")
                        continue
                    }
                }
                
                let chunkResult = try await transcribeAudioStandard(url: chunkURL, recordingId: recordingId)
                
                // Adjust timestamps to account for chunk offset
                let adjustedSegments = chunkResult.segments.map { segment in
                    TranscriptSegment(
                        speaker: segment.speaker,
                        text: segment.text,
                        startTime: segment.startTime + chunkStartTime,
                        endTime: segment.endTime + chunkStartTime
                    )
                }
                
                allSegments.append(contentsOf: adjustedSegments)
                totalProcessingTime += chunkResult.processingTime
                
                print("✅ Chunk \(chunkIndex + 1) completed: \(adjustedSegments.count) segments")
                
            } catch {
                print("❌ Failed to transcribe chunk \(chunkIndex + 1): \(error)")
                
                // Try connection reset and retry once for failed chunks
                print("🔄 Attempting connection reset and retry for chunk \(chunkIndex + 1)")
                tcpClient.disconnect()
                try await Task.sleep(nanoseconds: 2_000_000_000) // 2 second delay for retry
                
                // Re-register message handlers after disconnect (they get cleared)
                setupMessageHandlers()
                
                let reconnected = await testConnection()
                if reconnected {
                    do {
                        let retryResult = try await transcribeAudioStandard(url: chunkURL, recordingId: recordingId)
                        
                        let adjustedSegments = retryResult.segments.map { segment in
                            TranscriptSegment(
                                speaker: segment.speaker,
                                text: segment.text,
                                startTime: segment.startTime + chunkStartTime,
                                endTime: segment.endTime + chunkStartTime
                            )
                        }
                        
                        allSegments.append(contentsOf: adjustedSegments)
                        totalProcessingTime += retryResult.processingTime
                        
                        print("✅ Chunk \(chunkIndex + 1) completed on retry: \(adjustedSegments.count) segments")
                    } catch {
                        print("❌ Retry also failed for chunk \(chunkIndex + 1): \(error)")
                        // Continue with next chunk - don't fail entire transcription for one chunk
                        continue
                    }
                } else {
                    print("❌ Could not reconnect for chunk \(chunkIndex + 1) retry")
                    continue
                }
            }
            
            // Clean up chunk file immediately to save disk space
            try? FileManager.default.removeItem(at: chunkURL)
        }
        
        endBackgroundTask()
        
        // Merge segments and create final result
        let mergedSegments = mergeAdjacentSegments(allSegments)
        let fullText = mergedSegments.map { $0.text }.joined(separator: " ")
        let finalProcessingTime = Date().timeIntervalSince(startTime)
        
        print("✅ Chunked transcription completed: \(mergedSegments.count) total segments, \(fullText.count) characters")
        print("⏱️ Total processing time: \(Int(finalProcessingTime))s")
        
        // Final progress update
        currentStatus = "Transcription completed"
        progress = 1.0
        isTranscribing = false
        
        return TranscriptionResult(
            fullText: fullText,
            segments: mergedSegments,
            processingTime: finalProcessingTime,
            chunkCount: numberOfChunks,
            success: true,
            error: nil
        )
    }
    
    private func createAudioChunk(sourceURL: URL, outputURL: URL, startTime: TimeInterval, duration: TimeInterval) async throws {
        print("🎵 Creating audio chunk: \(Int(startTime))s - \(Int(startTime + duration))s")
        
        let asset = AVURLAsset(url: sourceURL)
        
        // Use modern iOS 18+ API with fallback for older versions
        if #available(iOS 18.0, *) {
            // Create export session with modern API
            guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
                throw WyomingError.serverError("Failed to create export session")
            }
            
            exportSession.outputFileType = .m4a
            exportSession.timeRange = CMTimeRangeMake(
                start: CMTime(seconds: startTime, preferredTimescale: 1000),
                duration: CMTime(seconds: duration, preferredTimescale: 1000)
            )
            
            // Use modern async throws export method
            try await exportSession.export(to: outputURL, as: .m4a)
            
        } else {
            // Fallback for iOS < 18.0
            guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
                throw WyomingError.serverError("Failed to create export session")
            }
            
            exportSession.outputURL = outputURL
            exportSession.outputFileType = .m4a
            exportSession.timeRange = CMTimeRangeMake(
                start: CMTime(seconds: startTime, preferredTimescale: 1000),
                duration: CMTime(seconds: duration, preferredTimescale: 1000)
            )
            
            await exportSession.export()
            
            if exportSession.status != .completed {
                if let error = exportSession.error {
                    throw error
                } else {
                    throw WyomingError.serverError("Audio chunk export failed")
                }
            }
        }
        
        print("✅ Audio chunk created: \(outputURL.lastPathComponent)")
    }
    
    private func mergeAdjacentSegments(_ segments: [TranscriptSegment]) -> [TranscriptSegment] {
        guard !segments.isEmpty else { return [] }
        
        // Sort segments by start time
        let sortedSegments = segments.sorted { $0.startTime < $1.startTime }
        var mergedSegments: [TranscriptSegment] = []
        var currentSegment = sortedSegments[0]
        
        for nextSegment in sortedSegments.dropFirst() {
            let timeDifference = nextSegment.startTime - currentSegment.endTime
            let isSameSpeaker = currentSegment.speaker == nextSegment.speaker
            
            // Merge if segments are close together (< 2 seconds) and same speaker
            if timeDifference < 2.0 && isSameSpeaker && !currentSegment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                currentSegment = TranscriptSegment(
                    speaker: currentSegment.speaker,
                    text: currentSegment.text + " " + nextSegment.text,
                    startTime: currentSegment.startTime,
                    endTime: nextSegment.endTime
                )
            } else {
                mergedSegments.append(currentSegment)
                currentSegment = nextSegment
            }
        }
        
        mergedSegments.append(currentSegment)
        
        print("🔗 Merged \(segments.count) segments into \(mergedSegments.count) segments")
        return mergedSegments
    }
    
    // MARK: - Status Properties
    
    var connectionStatus: String {
        return tcpClient.connectionStatus
    }
    
    var availableModels: [String] {
        return serverInfo?.asr?.first?.models?.map { $0.name } ?? []
    }
    
    // MARK: - Background Task Management
    
    private func beginBackgroundTask() {
        print("🔍 DEBUG: Inside beginBackgroundTask(), checking backgroundTaskID")
        guard backgroundTaskID == .invalid else { 
            print("🔍 DEBUG: backgroundTaskID already exists, returning early")
            return 
        }
        
        print("🔍 DEBUG: About to call UIApplication.shared.beginBackgroundTask")
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "WyomingTranscription") { [weak self] in
            print("⚠️ Wyoming background task is about to expire")
            Task { @MainActor in
                await self?.handleBackgroundTaskExpiration()
            }
        }
        print("🔍 DEBUG: UIApplication.shared.beginBackgroundTask completed")
        
        print("🔍 DEBUG: Checking if backgroundTaskID is valid")
        if backgroundTaskID == .invalid {
            print("❌ Failed to start Wyoming background task")
        } else {
            print("🔍 DEBUG: About to check backgroundTimeRemaining")
            let remainingTime = UIApplication.shared.backgroundTimeRemaining
            print("🔍 DEBUG: Got remainingTime: \(remainingTime)")
            if remainingTime.isFinite {
                print("✅ Started Wyoming background task with \(String(format: "%.0f", remainingTime)) seconds remaining")
            } else {
                print("✅ Started Wyoming background task with unlimited time remaining")
            }
        }
        print("🔍 DEBUG: beginBackgroundTask completed successfully")
    }
    
    private func endBackgroundTask() {
        if backgroundTaskID != .invalid {
            print("⏹️ Ending Wyoming background task: \(backgroundTaskID.rawValue)")
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
    }
    
    private func handleBackgroundTaskExpiration() async {
        print("⚠️ Wyoming background task expired, attempting graceful cleanup")
        
        // Cancel any ongoing streaming timeout task
        streamingTimeoutTask?.cancel()
        streamingTimeoutTask = nil
        
        // If we have an active transcription, complete it with a timeout error
        if let continuation = currentTranscription {
            currentTranscription = nil
            continuation.resume(throwing: WyomingError.timeout)
        }
        
        // Reset state
        isTranscribing = false
        currentStatus = "Background task expired"
        
        // End the background task
        endBackgroundTask()
    }
    
    // MARK: - Timeout Management
    
    private func startStreamingTimeout(seconds: Int = 300) { // 5 minutes default
        streamingTimeoutTask?.cancel()
        
        // Ensure we don't overflow when converting to nanoseconds
        let clampedSeconds = max(1, min(seconds, 3600)) // Between 1 second and 1 hour
        let nanoseconds = UInt64(clampedSeconds) * 1_000_000_000
        
        print("⏰ Starting Wyoming timeout: \(clampedSeconds) seconds")
        
        streamingTimeoutTask = Task {
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
                await handleStreamingTimeout()
            } catch {
                // Task was cancelled, which is expected
            }
        }
    }
    
    private func cancelStreamingTimeout() {
        streamingTimeoutTask?.cancel()
        streamingTimeoutTask = nil
    }
    
    private func handleStreamingTimeout() async {
        print("⏰ Wyoming streaming timeout after extended period")
        
        if let continuation = currentTranscription {
            currentTranscription = nil
            continuation.resume(throwing: WyomingError.timeout)
        }
        
        isTranscribing = false
        currentStatus = "Streaming timeout"
        connectionError = "Transcription timed out during streaming"
        
        endBackgroundTask()
    }
}