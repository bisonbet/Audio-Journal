//
//  AudioChunkingModels.swift
//  Audio Journal
//
//  Data models for audio file chunking functionality
//

import Foundation
import AVFoundation
import CoreMedia

// MARK: - Audio Chunk Model

struct AudioChunk: Identifiable, Codable {
    let id: UUID
    let originalURL: URL
    let chunkURL: URL
    let sequenceNumber: Int
    let startTime: TimeInterval
    let endTime: TimeInterval
    let fileSize: Int64
    let duration: TimeInterval
    
    init(originalURL: URL, chunkURL: URL, sequenceNumber: Int, startTime: TimeInterval, endTime: TimeInterval, fileSize: Int64) {
        self.id = UUID()
        self.originalURL = originalURL
        self.chunkURL = chunkURL
        self.sequenceNumber = sequenceNumber
        self.startTime = startTime
        self.endTime = endTime
        self.fileSize = fileSize
        self.duration = endTime - startTime
    }
}

// MARK: - Transcript Chunk Model

struct TranscriptChunk: Identifiable, Codable {
    let id: UUID
    let chunkId: UUID
    let sequenceNumber: Int
    let transcript: String
    let segments: [TranscriptSegment]
    let startTime: TimeInterval
    let endTime: TimeInterval
    let processingTime: TimeInterval?
    let createdAt: Date
    
    init(chunkId: UUID, sequenceNumber: Int, transcript: String, segments: [TranscriptSegment], startTime: TimeInterval, endTime: TimeInterval, processingTime: TimeInterval? = nil) {
        self.id = UUID()
        self.chunkId = chunkId
        self.sequenceNumber = sequenceNumber
        self.transcript = transcript
        self.segments = segments
        self.startTime = startTime
        self.endTime = endTime
        self.processingTime = processingTime
        self.createdAt = Date()
    }
}

// MARK: - Chunking Strategy

enum ChunkingStrategy {
    case fileSize(maxBytes: Int64)
    case duration(maxSeconds: TimeInterval)
    
    static let openAI = ChunkingStrategy.fileSize(maxBytes: 24 * 1024 * 1024) // 24MB
    static let whisper = ChunkingStrategy.duration(maxSeconds: 2 * 60 * 60) // 2 hours
    static let aws = ChunkingStrategy.duration(maxSeconds: 2 * 60 * 60) // 2 hours
    static let appleIntelligence = ChunkingStrategy.duration(maxSeconds: 15 * 60) // 15 minutes
    
    var description: String {
        switch self {
        case .fileSize(let maxBytes):
            return "File size limit: \(maxBytes / 1024 / 1024) MB"
        case .duration(let maxSeconds):
            return "Duration limit: \(Int(maxSeconds / 60)) minutes"
        }
    }
}

// MARK: - Chunking Configuration

struct ChunkingConfig {
    let strategy: ChunkingStrategy
    let overlapSeconds: TimeInterval
    let tempDirectory: URL
    
    init(strategy: ChunkingStrategy, overlapSeconds: TimeInterval = 5.0, tempDirectory: URL? = nil) {
        self.strategy = strategy
        self.overlapSeconds = overlapSeconds
        self.tempDirectory = tempDirectory ?? FileManager.default.temporaryDirectory.appendingPathComponent("AudioChunks")
    }
    
    static func config(for engine: TranscriptionEngine) -> ChunkingConfig {
        switch engine {
        case .openAI:
            return ChunkingConfig(strategy: .openAI)
        case .whisper:
            return ChunkingConfig(strategy: .whisper)
        case .awsTranscribe:
            return ChunkingConfig(strategy: .aws)
        case .appleIntelligence:
            return ChunkingConfig(strategy: .appleIntelligence)
        case .openAIAPICompatible:
            return ChunkingConfig(strategy: .openAI) // Default to OpenAI limits
        }
    }
}

// MARK: - Chunking Result

struct ChunkingResult {
    let chunks: [AudioChunk]
    let totalDuration: TimeInterval
    let totalSize: Int64
    let chunkingTime: TimeInterval
    let needsChunking: Bool
    
    init(chunks: [AudioChunk], totalDuration: TimeInterval, totalSize: Int64, chunkingTime: TimeInterval) {
        self.chunks = chunks
        self.totalDuration = totalDuration
        self.totalSize = totalSize
        self.chunkingTime = chunkingTime
        self.needsChunking = chunks.count > 1
    }
}

// MARK: - Reassembly Result

struct ReassemblyResult {
    let transcriptData: TranscriptData
    let totalSegments: Int
    let reassemblyTime: TimeInterval
    let chunks: [TranscriptChunk]
    
    init(transcriptData: TranscriptData, totalSegments: Int, reassemblyTime: TimeInterval, chunks: [TranscriptChunk]) {
        self.transcriptData = transcriptData
        self.totalSegments = totalSegments
        self.reassemblyTime = reassemblyTime
        self.chunks = chunks
    }
}

// MARK: - Audio File Info

struct AudioFileInfo {
    let url: URL
    let duration: TimeInterval
    let fileSize: Int64
    let format: String
    let sampleRate: Double
    let channels: Int
    
    static func create(from url: URL) async throws -> AudioFileInfo {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = fileAttributes[.size] as? Int64 ?? 0
        
        // Get format information
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        var sampleRate: Double = 0
        var channels: Int = 0
        
        if let audioTrack = tracks.first {
            let formatDescriptions = try await audioTrack.load(.formatDescriptions)
            if let formatDescription = formatDescriptions.first {
                let audioStreamBasicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
                sampleRate = audioStreamBasicDescription?.pointee.mSampleRate ?? 0
                channels = Int(audioStreamBasicDescription?.pointee.mChannelsPerFrame ?? 0)
            }
        }
        
        // Determine format from file extension
        let fileExtension = url.pathExtension.lowercased()
        let format: String
        switch fileExtension {
        case "mp3":
            format = "MP3"
        case "m4a", "mp4":
            format = "AAC"
        case "wav":
            format = "WAV"
        case "flac":
            format = "FLAC"
        default:
            format = fileExtension.uppercased()
        }
        
        return AudioFileInfo(
            url: url,
            duration: duration,
            fileSize: fileSize,
            format: format,
            sampleRate: sampleRate,
            channels: channels
        )
    }
    
    private init(url: URL, duration: TimeInterval, fileSize: Int64, format: String, sampleRate: Double, channels: Int) {
        self.url = url
        self.duration = duration
        self.fileSize = fileSize
        self.format = format
        self.sampleRate = sampleRate
        self.channels = channels
    }
}

// MARK: - Chunking Errors

enum AudioChunkingError: LocalizedError {
    case fileNotFound
    case invalidAudioFile
    case chunkingFailed(String)
    case reassemblyFailed(String)
    case tempDirectoryCreationFailed
    case fileWriteFailed(String)
    case cleanupFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "Audio file not found or inaccessible"
        case .invalidAudioFile:
            return "Invalid audio file format or corrupted file"
        case .chunkingFailed(let message):
            return "Audio file chunking failed: \(message)"
        case .reassemblyFailed(let message):
            return "Transcript reassembly failed: \(message)"
        case .tempDirectoryCreationFailed:
            return "Failed to create temporary directory for chunks"
        case .fileWriteFailed(let message):
            return "Failed to write chunk file: \(message)"
        case .cleanupFailed(let message):
            return "Failed to cleanup temporary files: \(message)"
        }
    }
}