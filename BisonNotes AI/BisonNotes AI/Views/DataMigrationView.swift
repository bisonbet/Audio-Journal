//
//  DataMigrationView.swift
//  Audio Journal
//
//  Created by Kiro on 8/1/25.
//

import SwiftUI

enum MigrationMode {
    case migration
    case integrityCheck
    case repair
}

struct DataMigrationView: View {
    @EnvironmentObject var appCoordinator: AppDataCoordinator
    @StateObject private var migrationManager = DataMigrationManager()
    @StateObject private var legacyiCloudManager = iCloudStorageManager()
    @Environment(\.dismiss) private var dismiss
    @State private var integrityReport: DataIntegrityReport?
    @State private var repairResults: DataRepairResults?
    @State private var currentMode: MigrationMode = .migration
    @State private var showingClearDatabaseAlert = false
    @State private var isInitialized = false
    @State private var showingCleanupAlert = false
    @State private var isPerformingCleanup = false
    @State private var cleanupResults: CleanupResults?
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 30) {
                    headerSection
                    
                    if migrationManager.migrationProgress > 0 {
                        progressSection
                    }
                    
                    switch currentMode {
                    case .migration:
                        migrationSection
                    case .integrityCheck:
                        integrityCheckSection
                    case .repair:
                        repairSection
                    }
                    
                    if integrityReport != nil || repairResults != nil {
                        resultsSection
                    }
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("⚠️ DESTRUCTIVE ACTION - Clear All Database Data", isPresented: $showingClearDatabaseAlert) {
                Button("Cancel", role: .cancel) { }
                Button("I Understand - Delete Everything", role: .destructive) {
                    Task {
                        await migrationManager.clearAllCoreData()
                    }
                }
            } message: {
                Text("🚨 CRITICAL WARNING 🚨\n\nThis will PERMANENTLY DELETE ALL of your data from the database:\n\n❌ ALL TRANSCRIPTS (cannot be recovered)\n❌ ALL SUMMARIES (cannot be recovered)\n❌ ALL RECORDING METADATA\n\n✅ Your audio files will remain on disk\n\n⚠️ This action CANNOT be undone and you will lose all your transcribed text and AI-generated summaries forever.\n\nOnly proceed if you understand this will destroy all your transcript and summary data.")
            }
            .alert("Cleanup Orphaned Data", isPresented: $showingCleanupAlert) {
                Button("Cancel") {
                    showingCleanupAlert = false
                }
                Button("Clean Up") {
                    Task {
                        await performCleanup()
                    }
                    showingCleanupAlert = false
                }
            } message: {
                Text("This will remove summaries and transcripts for recordings that no longer exist. This action cannot be undone.")
            }
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            Image(systemName: headerIcon)
                .font(.system(size: 60))
                .foregroundColor(.accentColor)
            
            Text(headerTitle)
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text(headerDescription)
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }
    
    private var progressSection: some View {
        VStack(spacing: 16) {
            ProgressView(value: migrationManager.migrationProgress)
                .progressViewStyle(LinearProgressViewStyle(tint: .accentColor))
            
            Text(migrationManager.migrationStatus)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
    }
    
    private var migrationSection: some View {
        VStack(spacing: 16) {
            // Primary action - Check for issues
            Button(action: {
                currentMode = .integrityCheck
            }) {
                HStack {
                    Image(systemName: "magnifyingglass.circle.fill")
                    Text("Check for Issues")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.accentColor)
                .cornerRadius(12)
            }
            
            // Legacy migration (for old data format)
            Button(action: {
                Task {
                    await migrationManager.performDataMigration()
                }
            }) {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Import Legacy Files")
                }
                .font(.headline)
                .foregroundColor(.orange)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.orange.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.orange, lineWidth: 1)
                )
                .cornerRadius(12)
            }
            .disabled(migrationManager.migrationProgress > 0 && !migrationManager.isCompleted)
            
            // iCloud Recovery
            Button(action: {
                Task {
                    // Initialize the migration manager with iCloud sync managers
                    migrationManager.setCloudSyncManagers(legacy: legacyiCloudManager)
                    
                    let results = await migrationManager.recoverDataFromiCloud()
                    // Handle recovery results
                    print("📥 Recovery completed: \(results.transcripts) transcripts, \(results.summaries) summaries")
                    if !results.errors.isEmpty {
                        print("⚠️ Recovery errors: \(results.errors.joined(separator: ", "))")
                    }
                }
            }) {
                HStack {
                    Image(systemName: "icloud.and.arrow.down")
                    Text("Recover from iCloud")
                }
                .font(.headline)
                .foregroundColor(.purple)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.purple.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.purple, lineWidth: 1)
                )
                .cornerRadius(12)
            }
            .disabled(migrationManager.migrationProgress > 0 && !migrationManager.isCompleted)
            
            // Fix filename/title duplicates (the new advanced repair)
            Button(action: {
                Task {
                    let result = await migrationManager.fixSpecificDataIssues()
                    print("🎯 Fixed \(result.resolved) data issues, saved: \(result.saved)")
                }
            }) {
                HStack {
                    Image(systemName: "arrow.triangle.merge")
                    Text("Fix Filename/Title Duplicates")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.green)
                .cornerRadius(12)
            }
            .disabled(migrationManager.migrationProgress > 0 && !migrationManager.isCompleted)
            
            // Fix current naming and transcript listing issues
            Button(action: {
                Task {
                    let result = await migrationManager.fixCurrentIssues()
                    print("🎯 Fixed current issues: \(result.renames) renames, \(result.validations) validations")
                }
            }) {
                HStack {
                    Image(systemName: "textformat")
                    Text("Fix Names & Transcript Listings")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.purple)
                .cornerRadius(12)
            }
            .disabled(migrationManager.migrationProgress > 0 && !migrationManager.isCompleted)
            
            // Import orphaned audio files
            Button(action: {
                Task {
                    let count = await migrationManager.findAndImportOrphanedAudioFiles()
                    print("📥 Imported \(count) orphaned audio files")
                }
            }) {
                HStack {
                    Image(systemName: "plus.rectangle.on.folder")
                    Text("Import Orphaned Audio Files")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.orange)
                .cornerRadius(12)
            }
            .disabled(migrationManager.migrationProgress > 0 && !migrationManager.isCompleted)

            // Diagnostic for UI vs Database disconnect
            Button(action: {
                Task {
                    await migrationManager.diagnoseRecordingDisplayIssue()
                }
            }) {
                HStack {
                    Image(systemName: "stethoscope")
                    Text("Diagnose Display Issue")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.red)
                .cornerRadius(12)
            }

            // Debug tools section
            VStack(alignment: .leading, spacing: 12) {
                Text("Database Debug Tools")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .padding(.horizontal, 4)
                
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        Button("Debug Database") {
                            appCoordinator.debugDatabaseContents()
                        }
                        .buttonStyle(CompactDebugButtonStyle())
                        
                        Button("Debug Summary Data") {
                            debugSummaryData()
                        }
                        .buttonStyle(CompactDebugButtonStyle())
                        
                        Button("Sync URLs") {
                            appCoordinator.syncRecordingURLs()
                        }
                        .buttonStyle(CompactDebugButtonStyle())
                    }
                    
                    // Cleanup Orphaned Data section
                    VStack(spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Cleanup Orphaned Data")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                Text("Remove summaries and transcripts for deleted recordings")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button(action: {
                                showingCleanupAlert = true
                            }) {
                                HStack {
                                    if isPerformingCleanup {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                            .padding(.trailing, 4)
                                    }
                                    Text(isPerformingCleanup ? "Cleaning..." : "Clean Up")
                                }
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(isPerformingCleanup ? Color.gray : Color.orange)
                                )
                            }
                            .disabled(isPerformingCleanup)
                        }
                        
                        if let results = cleanupResults {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Last Cleanup Results:")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)
                                
                                Text("• Removed \(results.orphanedSummaries) orphaned summaries")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Text("• Removed \(results.orphanedTranscripts) orphaned transcripts")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Text("• Freed \(results.freedSpaceMB, specifier: "%.1f") MB of space")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color(.systemGray6).opacity(0.5))
                    .cornerRadius(8)
                }
            }
            
            // Debug info
            Button(action: {
                Task {
                    await migrationManager.debugCoreDataContents()
                }
            }) {
                HStack {
                    Image(systemName: "info.circle")
                    Text("View Database Info")
                }
                .font(.headline)
                .foregroundColor(.blue)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.blue.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue, lineWidth: 1)
                )
                .cornerRadius(12)
            }
            
            // Destructive action - Clear database
            Button(action: {
                showingClearDatabaseAlert = true
            }) {
                HStack {
                    Image(systemName: "trash.circle")
                    Text("Clear All Data")
                }
                .font(.headline)
                .foregroundColor(.red)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.red.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.red, lineWidth: 1)
                )
                .cornerRadius(12)
            }
        }
        .padding(.horizontal)
    }
    
    private var integrityCheckSection: some View {
        VStack(spacing: 16) {
            Button(action: {
                Task {
                    integrityReport = await migrationManager.performDataIntegrityCheck()
                }
            }) {
                HStack {
                    Image(systemName: "play.circle.fill")
                    Text("Start Integrity Check")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.orange)
                .cornerRadius(12)
            }
            .disabled(migrationManager.migrationProgress > 0 && migrationManager.migrationProgress < 1.0)
            
            Button(action: {
                currentMode = .migration
                integrityReport = nil
            }) {
                HStack {
                    Image(systemName: "arrow.left.circle")
                    Text("Back to Migration")
                }
                .font(.headline)
                .foregroundColor(.blue)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.blue.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue, lineWidth: 1)
                )
                .cornerRadius(12)
            }
        }
        .padding(.horizontal)
    }
    
    private var repairSection: some View {
        VStack(spacing: 16) {
            if let report = integrityReport {
                Button(action: {
                    Task {
                        repairResults = await migrationManager.repairDataIntegrityIssues(report: report)
                    }
                }) {
                    HStack {
                        Image(systemName: "wrench.and.screwdriver.fill")
                        Text("Start Repair")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.green)
                    .cornerRadius(12)
                }
                .disabled(migrationManager.migrationProgress > 0 && migrationManager.migrationProgress < 1.0)
            }
            
            Button(action: {
                currentMode = .integrityCheck
                repairResults = nil
            }) {
                HStack {
                    Image(systemName: "arrow.left.circle")
                    Text("Back to Integrity Check")
                }
                .font(.headline)
                .foregroundColor(.blue)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.blue.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue, lineWidth: 1)
                )
                .cornerRadius(12)
            }
        }
        .padding(.horizontal)
    }
    
    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let report = integrityReport {
                Text("Integrity Check Results")
                    .font(.headline)
                    .padding(.horizontal)
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: report.hasIssues ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .foregroundColor(report.hasIssues ? .orange : .green)
                        Text(report.hasIssues ? "Issues Found: \(report.totalIssues)" : "No Issues Found")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    
                    if report.hasIssues {
                        VStack(alignment: .leading, spacing: 4) {
                            if !report.orphanedRecordings.isEmpty {
                                Text("• \(report.orphanedRecordings.count) recordings missing transcript/summary links")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            if !report.orphanedFiles.isEmpty {
                                Text("• \(report.orphanedFiles.count) orphaned transcript/summary files")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            if !report.brokenRelationships.isEmpty {
                                Text("• \(report.brokenRelationships.count) broken database relationships")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            if !report.missingAudioFiles.isEmpty {
                                Text("• \(report.missingAudioFiles.count) recordings with missing audio files")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            if !report.duplicateEntries.isEmpty {
                                Text("• \(report.duplicateEntries.count) sets of duplicate entries")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.leading)
                        
                        Button(action: {
                            currentMode = .repair
                        }) {
                            HStack {
                                Image(systemName: "wrench.fill")
                                Text("Repair Issues")
                            }
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.green)
                            .cornerRadius(8)
                        }
                        .padding(.top, 8)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal)
            }
            
            if let results = repairResults {
                Text("Repair Results")
                    .font(.headline)
                    .padding(.horizontal)
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Repairs Completed: \(results.totalRepairs)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    
                    if results.totalRepairs > 0 {
                        VStack(alignment: .leading, spacing: 4) {
                            if results.repairedOrphanedRecordings > 0 {
                                Text("• \(results.repairedOrphanedRecordings) orphaned recordings repaired")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            if results.importedOrphanedFiles > 0 {
                                Text("• \(results.importedOrphanedFiles) orphaned files imported")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            if results.repairedRelationships > 0 {
                                Text("• \(results.repairedRelationships) broken relationships repaired")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            if results.cleanedMissingFiles > 0 {
                                Text("• \(results.cleanedMissingFiles) entries with missing files cleaned")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.leading)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal)
            }
        }
    }
    
    private var navigationTitle: String {
        switch currentMode {
        case .migration:
            return "Database Tools"
        case .integrityCheck:
            return "Integrity Check"
        case .repair:
            return "Data Repair"
        }
    }
    
    private var headerIcon: String {
        switch currentMode {
        case .migration:
            return "arrow.triangle.2.circlepath"
        case .integrityCheck:
            return "magnifyingglass"
        case .repair:
            return "wrench.and.screwdriver"
        }
    }
    
    private var headerTitle: String {
        switch currentMode {
        case .migration:
            return "Database Tools"
        case .integrityCheck:
            return "Data Integrity Check"
        case .repair:
            return "Data Repair"
        }
    }
    
    private var headerDescription: String {
        switch currentMode {
        case .migration:
            return "Check for missing transcripts and summaries, import legacy files, view database information, or clear all data."
        case .integrityCheck:
            return "Scan your database for missing relationships, orphaned files, and other data integrity issues."
        case .repair:
            return "Automatically repair the data integrity issues found during the scan to restore missing transcripts and summaries."
        }
    }
    
    // MARK: - Debug Helper Functions
    
    private func debugSummaryData() {
        print("🔍 Debugging summaries...")
        
        let recordingsWithData = appCoordinator.getAllRecordingsWithData()
        print("📊 Total recordings: \(recordingsWithData.count)")
        
        for (index, recordingData) in recordingsWithData.enumerated() {
            let recording = recordingData.recording
            let summary = recordingData.summary
            
            print("   \(index): \(recording.recordingName ?? "Unknown")")
            print("      - Recording ID: \(recording.id?.uuidString ?? "nil")")
            print("      - Has summary: \(summary != nil)")
            
            if let summary = summary {
                print("      - Summary AI Method: \(summary.aiMethod)")
                print("      - Summary Generated At: \(summary.generatedAt)")
                print("      - Summary Recording ID: \(summary.recordingId?.uuidString ?? "nil")")
                print("      - Summary ID: \(summary.id)")
            }
        }
    }
    
    // MARK: - Cleanup Functions
    
    private func performCleanup() async {
        isPerformingCleanup = true
        
        do {
            let results = try await cleanupOrphanedData()
            await MainActor.run {
                self.cleanupResults = results
                self.isPerformingCleanup = false
            }
        } catch {
            await MainActor.run {
                self.isPerformingCleanup = false
                print("❌ Cleanup error: \(error)")
            }
        }
    }
    
    private func cleanupOrphanedData() async throws -> CleanupResults {
        print("🧹 Starting orphaned data cleanup...")
        
        // Get all recordings from Core Data
        let allRecordings = appCoordinator.coreDataManager.getAllRecordings()
        print("📁 Found \(allRecordings.count) recordings in Core Data")
        
        // Get all transcripts and summaries from Core Data
        let allTranscripts = appCoordinator.getAllTranscripts()
        let allSummaries = appCoordinator.getAllSummaries()
        
        print("📊 Found \(allSummaries.count) stored summaries and \(allTranscripts.count) stored transcripts")
        
        var orphanedSummaries = 0
        var orphanedTranscripts = 0
        var freedSpaceBytes: Int64 = 0
        
        // Create a set of valid recording IDs for quick lookup
        let validRecordingIds = Set(allRecordings.compactMap { $0.id })
        
        print("🔍 Valid recording IDs: \(validRecordingIds.count)")
        
        // Check for orphaned summaries
        for summary in allSummaries {
            let recordingId = summary.recordingId
            
            // Check if the recording ID exists in Core Data
            let hasValidID = recordingId != nil && validRecordingIds.contains(recordingId!)
            
            if !hasValidID {
                print("🗑️ Found orphaned summary for recording ID: \(recordingId?.uuidString ?? "nil")")
                print("   ID exists: \(hasValidID)")
                
                // Delete the orphaned summary
                do {
                    try appCoordinator.coreDataManager.deleteSummary(id: summary.id)
                    orphanedSummaries += 1
                } catch {
                    print("❌ Failed to delete orphaned summary: \(error)")
                }
                
                // Calculate freed space (rough estimate)
                freedSpaceBytes += Int64(summary.summary?.count ?? 0 * 2) // Approximate UTF-8 bytes
            }
        }
        
        // Check for orphaned transcripts
        for transcript in allTranscripts {
            let recordingId = transcript.recordingId
            
            // Check if the recording ID exists in Core Data
            let hasValidID = recordingId != nil && validRecordingIds.contains(recordingId!)
            
            if !hasValidID {
                print("🗑️ Found orphaned transcript for recording ID: \(recordingId?.uuidString ?? "nil")")
                print("   ID exists: \(hasValidID)")
                
                // Delete the orphaned transcript
                appCoordinator.coreDataManager.deleteTranscript(id: transcript.id)
                orphanedTranscripts += 1
                
                // Calculate freed space
                let transcriptText = transcript.segments ?? ""
                freedSpaceBytes += Int64(transcriptText.count * 2) // Approximate UTF-8 bytes
            } else {
                // Log when we find a transcript that's actually valid
                print("✅ Found valid transcript for recording ID: \(recordingId?.uuidString ?? "nil")")
            }
        }
        
        // Check for transcripts where the recording file doesn't exist on disk
        for transcript in allTranscripts {
            guard let recordingId = transcript.recordingId,
                  let recording = appCoordinator.coreDataManager.getRecording(id: recordingId),
                  let recordingURLString = recording.recordingURL,
                  let recordingURL = URL(string: recordingURLString) else {
                continue
            }
            
            // Check if the recording file exists on disk
            let fileExists = FileManager.default.fileExists(atPath: recordingURL.path)
            
            // Check if the recording exists in Core Data
            let hasValidID = validRecordingIds.contains(recordingId)
            
            // Only remove if the file doesn't exist AND it's not in Core Data
            if !fileExists && !hasValidID {
                print("🗑️ Found transcript for non-existent recording file: \(recordingURL.lastPathComponent)")
                print("   File exists: \(fileExists), ID in Core Data: \(hasValidID)")
                
                // Delete the orphaned transcript
                appCoordinator.coreDataManager.deleteTranscript(id: transcript.id)
                orphanedTranscripts += 1
                
                // Calculate freed space
                let transcriptText = transcript.segments ?? ""
                freedSpaceBytes += Int64(transcriptText.count * 2) // Approximate UTF-8 bytes
            } else if !fileExists {
                // Log when file doesn't exist but recording is in Core Data
                print("⚠️  File not found on disk but recording exists in Core Data: \(recordingURL.lastPathComponent)")
                print("   File exists: \(fileExists), ID in Core Data: \(hasValidID)")
            }
        }
        
        let freedSpaceMB = Double(freedSpaceBytes) / (1024 * 1024)
        
        print("✅ Cleanup complete:")
        print("   • Removed \(orphanedSummaries) orphaned summaries")
        print("   • Removed \(orphanedTranscripts) orphaned transcripts")
        print("   • Freed \(String(format: "%.1f", freedSpaceMB)) MB of space")
        
        return CleanupResults(
            orphanedSummaries: orphanedSummaries,
            orphanedTranscripts: orphanedTranscripts,
            freedSpaceMB: freedSpaceMB
        )
    }
}

// MARK: - Supporting Structures

struct CleanupResults {
    let orphanedSummaries: Int
    let orphanedTranscripts: Int
    let freedSpaceMB: Double
}

// MARK: - Compact Debug Button Style

struct CompactDebugButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption)
            .foregroundColor(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.systemGray6))
                    .opacity(configuration.isPressed ? 0.8 : 1.0)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}