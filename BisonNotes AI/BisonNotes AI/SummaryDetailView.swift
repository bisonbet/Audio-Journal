import SwiftUI
import MapKit
import CoreLocation

struct SummaryDetailView: View {
    let recording: RecordingFile
    @State private var summaryData: EnhancedSummaryData
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appCoordinator: AppDataCoordinator
    @State private var locationAddress: String?
    @State private var expandedSections: Set<String> = ["summary", "metadata"]
    @State private var isRegenerating = false
    @State private var showingRegenerationAlert = false
    @State private var regenerationError: String?
    @State private var showingDeleteConfirmation = false
    
    init(recording: RecordingFile, summaryData: EnhancedSummaryData) {
        self.recording = recording
        self._summaryData = State(initialValue: summaryData)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Map Section
                if let locationData = recording.locationData {
                    VStack {
                        Map(position: .constant(.region(MKCoordinateRegion(
                            center: CLLocationCoordinate2D(latitude: locationData.latitude, longitude: locationData.longitude),
                            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                        )))) {
                            Marker("Recording Location", coordinate: CLLocationCoordinate2D(latitude: locationData.latitude, longitude: locationData.longitude))
                                .foregroundStyle(.blue)
                        }
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                        
                        HStack {
                            Image(systemName: "location.fill")
                                .font(.caption)
                                .foregroundColor(.accentColor)
                            Text(locationAddress ?? locationData.coordinateString)
                                .font(.caption)
                                .foregroundColor(.accentColor)
                        }
                        .padding(.bottom)
                    }
                }
                
                // Enhanced Summary Content
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Header Section
                        headerSection
                        
                        // Metadata Section (Expandable)
                        metadataSection
                        
                        // Summary Section (Expandable)
                        summarySection
                        
                        // Tasks Section (Expandable)
                        tasksSection
                        
                        // Reminders Section (Expandable)
                        remindersSection
                        
                        // Titles Section (Expandable)
                        titlesSection
                        
                        // Regenerate Button Section
                        regenerateSection
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("Enhanced Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
                    .onAppear {
                // Refresh summary data from coordinator to get the latest version
                if let recordingEntry = appCoordinator.getRecording(url: recording.url),
                   let recordingId = recordingEntry.id,
            let completeData = appCoordinator.getCompleteRecordingData(id: recordingId),
                   let latestSummary = completeData.summary {
                    summaryData = latestSummary
                }
                
                if let locationData = recording.locationData {
                    let location = CLLocation(latitude: locationData.latitude, longitude: locationData.longitude)
                    let tempLocationManager = LocationManager()
                    tempLocationManager.reverseGeocodeLocation(location) { address in
                        if let address = address {
                            locationAddress = address
                        }
                    }
                }
            }
        .alert("Regeneration Error", isPresented: $showingRegenerationAlert) {
            Button("OK") {
                regenerationError = nil
            }
        } message: {
            if let error = regenerationError {
                Text(error)
            }
        }
        .alert("Delete Summary", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteSummary()
            }
        } message: {
            Text("Are you sure you want to delete this summary? This action cannot be undone. The audio file and transcript will remain unchanged.")
        }
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(recording.name)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            HStack {
                Image(systemName: "calendar")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(recording.dateString)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Image(systemName: "clock")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(recording.durationString)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
    }
    
    // MARK: - Metadata Section
    
    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(.blue)
                Text("Metadata")
                    .font(.headline)
                Spacer()
            }
            .padding(.bottom, 8)
            
            VStack(alignment: .leading, spacing: 12) {
                metadataRow(title: "AI Method", value: summaryData.aiMethod, icon: "brain.head.profile")
                metadataRow(title: "Generation Time", value: formatDate(summaryData.generatedAt), icon: "clock.arrow.circlepath")
                metadataRow(title: "Content Type", value: summaryData.contentType.rawValue, icon: "doc.text")
                metadataRow(title: "Word Count", value: "\(summaryData.wordCount) words", icon: "text.word.spacing")
                metadataRow(title: "Compression Ratio", value: summaryData.formattedCompressionRatio, icon: "chart.bar.fill")
                metadataRow(title: "Processing Time", value: summaryData.formattedProcessingTime, icon: "timer")
                metadataRow(title: "Quality", value: summaryData.qualityDescription, icon: "star.fill", valueColor: qualityColor)
                metadataRow(title: "Confidence", value: "\(Int(summaryData.confidence * 100))%", icon: "checkmark.shield.fill", valueColor: confidenceColor)
            }
        }
        .onTapGesture {
            toggleSection("metadata")
        }
    }
    
    private func metadataRow(title: String, value: String, icon: String, valueColor: Color = .primary) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 20)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.caption)
                .foregroundColor(valueColor)
                .fontWeight(.medium)
        }
    }
    
    private var qualityColor: Color {
        switch summaryData.qualityDescription {
        case "High Quality": return .green
        case "Good Quality": return .blue
        case "Fair Quality": return .orange
        default: return .red
        }
    }
    
    private var confidenceColor: Color {
        switch summaryData.confidence {
        case 0.8...1.0: return .green
        case 0.6..<0.8: return .blue
        case 0.4..<0.6: return .orange
        default: return .red
        }
    }
    
    // MARK: - Summary Section
    
    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "text.quote")
                    .foregroundColor(.accentColor)
                Text("Summary")
                    .font(.headline)
                Spacer()
            }
            .padding(.bottom, 8)
            
            AITextView(text: summaryData.summary)
                .font(.body)
                .lineSpacing(4)
                .padding(.top, 4)
                .textSelection(.enabled)
        }
        .onTapGesture {
            toggleSection("summary")
        }
    }
    
    // MARK: - Tasks Section
    
    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "checklist")
                    .foregroundColor(.green)
                Text("Tasks")
                    .font(.headline)
                if summaryData.tasks.count > 0 {
                    Text("(\(summaryData.tasks.count))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.bottom, 8)
            
            if summaryData.tasks.isEmpty {
                emptyStateView(message: "No tasks found", icon: "checkmark.circle")
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(summaryData.tasks, id: \.id) { task in
                        EnhancedTaskRowView(task: task, recordingName: summaryData.recordingName)
                    }
                }
                .padding(.top, 4)
            }
        }
        .onTapGesture {
            toggleSection("tasks")
        }
    }
    
    // MARK: - Reminders Section
    
    private var remindersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "bell")
                    .foregroundColor(.orange)
                Text("Reminders")
                    .font(.headline)
                if summaryData.reminders.count > 0 {
                    Text("(\(summaryData.reminders.count))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.bottom, 8)
            
            if summaryData.reminders.isEmpty {
                emptyStateView(message: "No reminders found", icon: "bell.slash")
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(summaryData.reminders, id: \.id) { reminder in
                        EnhancedReminderRowView(reminder: reminder, recordingName: summaryData.recordingName)
                    }
                }
                .padding(.top, 4)
            }
        }
        .onTapGesture {
            toggleSection("reminders")
        }
    }
    
    // MARK: - Titles Section
    
    private var titlesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "text.quote")
                    .foregroundColor(Color.purple)
                Text("Titles")
                    .font(.headline)
                if summaryData.titles.count > 0 {
                    Text("(\(summaryData.titles.count))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.bottom, 8)
            
            if summaryData.titles.isEmpty {
                emptyStateView(message: "No titles found", icon: "text.quote")
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(summaryData.titles, id: \.id) { title in
                        TitleRowView(title: title, recordingName: summaryData.recordingName)
                    }
                }
                .padding(.top, 4)
            }
        }
        .onTapGesture {
            toggleSection("titles")
        }
        .onTapGesture {
            toggleSection("titles")
        }
    }
    
    // MARK: - Regenerate Section
    
    private var regenerateSection: some View {
        VStack(spacing: 16) {
            Divider()
                .padding(.horizontal)
            
            VStack(spacing: 12) {
                Text("Need a different summary?")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text("Regenerate this summary with the current AI engine settings")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Button(action: {
                    Task {
                        await regenerateSummary()
                    }
                }) {
                    HStack {
                        if isRegenerating {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text(isRegenerating ? "Regenerating..." : "Regenerate Summary")
                    }
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(isRegenerating ? Color.gray : Color.orange)
                    .cornerRadius(10)
                }
                .disabled(isRegenerating)
            }
            .padding(.horizontal)
            
            // Delete Section
            deleteSection
        }
    }
    
    // MARK: - Delete Section
    
    private var deleteSection: some View {
        VStack(spacing: 12) {
            Divider()
                .padding(.horizontal)
            
            VStack(spacing: 8) {
                Text("Delete Summary")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text("Remove this summary while keeping the audio file and transcript")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Button(action: {
                    showingDeleteConfirmation = true
                }) {
                    HStack {
                        Image(systemName: "trash")
                        Text("Delete")
                    }
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.red)
                    .cornerRadius(10)
                }
            }
            .padding(.horizontal)
        }
    }
    
    // MARK: - Delete Logic
    
    private func deleteSummary() {
        print("🗑️ Deleting summary for: \(summaryData.recordingName)")
        print("🆔 Summary ID: \(summaryData.id)")
        
        // Delete the summary from Core Data
        appCoordinator.coreDataManager.deleteSummary(id: summaryData.id)
        print("✅ Summary deleted from Core Data")
        
        // Update the recording to remove summary reference
        if let recordingId = summaryData.recordingId,
           let recording = appCoordinator.getRecording(id: recordingId) {
            recording.summaryId = nil
            recording.summaryStatus = ProcessingStatus.notStarted.rawValue
            recording.lastModified = Date()
            
            // Save the updated recording
            do {
                try appCoordinator.coreDataManager.saveContext()
                print("✅ Recording updated to remove summary reference")
            } catch {
                print("❌ Failed to update recording: \(error)")
            }
        }
        
        print("✅ Summary deletion completed")
        dismiss()
    }
    
    // MARK: - Regeneration Logic
    
    private func regenerateSummary() async {
        guard !isRegenerating else { return }
        
        await MainActor.run {
            isRegenerating = true
        }
        
        do {
            // Get the recording data
            guard let recordingId = summaryData.recordingId,
                  let recordingData = appCoordinator.getCompleteRecordingData(id: recordingId) else {
                throw NSError(domain: "SummaryRegeneration", code: 2, userInfo: [NSLocalizedDescriptionKey: "No recording data found"])
            }
            
            // Get the transcript
            guard let transcript = recordingData.transcript else {
                throw NSError(domain: "SummaryRegeneration", code: 3, userInfo: [NSLocalizedDescriptionKey: "No transcript found for this recording"])
            }
            
            print("🔄 Starting summary regeneration for: \(summaryData.recordingName)")
            print("📝 Transcript length: \(transcript.plainText.count) characters")
            print("🤖 Current AI method: \(summaryData.aiMethod)")
            
            // Generate new summary using the current AI engine
            let newEnhancedSummary = try await SummaryManager.shared.generateEnhancedSummary(
                from: transcript.plainText,
                for: summaryData.recordingURL,
                recordingName: summaryData.recordingName,
                recordingDate: summaryData.recordingDate
            )
            
            print("✅ New summary generated successfully")
            print("📄 New summary length: \(newEnhancedSummary.summary.count) characters")
            print("📋 New tasks: \(newEnhancedSummary.tasks.count)")
            print("📋 New reminders: \(newEnhancedSummary.reminders.count)")
            print("📋 New titles: \(newEnhancedSummary.titles.count)")
            
            // Delete the old summary from Core Data
            appCoordinator.coreDataManager.deleteSummary(id: summaryData.id)
            print("🗑️ Deleted old summary with ID: \(summaryData.id)")
            
            // Create new summary entry in Core Data
            let newSummaryId = appCoordinator.workflowManager.createSummary(
                for: recordingId,
                transcriptId: summaryData.transcriptId ?? UUID(),
                summary: newEnhancedSummary.summary,
                tasks: newEnhancedSummary.tasks,
                reminders: newEnhancedSummary.reminders,
                titles: newEnhancedSummary.titles,
                contentType: newEnhancedSummary.contentType,
                aiMethod: newEnhancedSummary.aiMethod,
                originalLength: newEnhancedSummary.originalLength,
                processingTime: newEnhancedSummary.processingTime
            )
            
            if newSummaryId != nil {
                print("✅ New summary saved to Core Data with ID: \(newSummaryId?.uuidString ?? "nil")")
                
                await MainActor.run {
                    isRegenerating = false
                    // Dismiss the view to refresh the data
                    dismiss()
                }
            } else {
                throw NSError(domain: "SummaryRegeneration", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to save new summary to Core Data"])
            }
            
        } catch {
            print("❌ Summary regeneration failed: \(error)")
            await MainActor.run {
                regenerationError = "Failed to regenerate summary: \(error.localizedDescription)"
                showingRegenerationAlert = true
                isRegenerating = false
            }
        }
    }
    
    // MARK: - Helper Views
    
    private func emptyStateView(message: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.secondary)
            
            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .italic()
        }
        .padding(.top, 4)
    }
    
    private func toggleSection(_ section: String) {
        if expandedSections.contains(section) {
            expandedSections.remove(section)
        } else {
            expandedSections.insert(section)
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Enhanced Task Row Component

struct EnhancedTaskRowView: View {
    let task: TaskItem
    let recordingName: String
    @StateObject private var integrationManager = SystemIntegrationManager()
    @State private var showingIntegrationSelection = false
    @State private var showingSuccessAlert = false
    @State private var showingErrorAlert = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Priority indicator
            Circle()
                .fill(priorityColor)
                .frame(width: 8, height: 8)
                .padding(.top, 6)
            
            // Task content
            VStack(alignment: .leading, spacing: 4) {
                Text(task.text)
                    .font(.body)
                    .foregroundColor(.primary)
                    .lineLimit(nil)
                
                // Task metadata
                HStack {
                    Image(systemName: task.category.icon)
                        .font(.caption2)
                        .foregroundColor(categoryColor)
                    
                    Text(task.category.rawValue)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    if let timeRef = task.timeReference {
                        Image(systemName: "clock")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Text(timeRef)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // Confidence indicator
                    HStack(spacing: 2) {
                        ForEach(0..<3, id: \.self) { index in
                            Circle()
                                .fill(index < confidenceLevel ? .green : .gray.opacity(0.3))
                                .frame(width: 4, height: 4)
                        }
                    }
                }
                
                // Integration button
                HStack {
                    Spacer()
                    
                    Button(action: {
                        showingIntegrationSelection = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle")
                                .font(.caption)
                            Text("Add to System")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .disabled(integrationManager.isProcessing)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.systemGray6).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .sheet(isPresented: $showingIntegrationSelection) {
            IntegrationSelectionView(
                title: "Add Task to System",
                subtitle: "Choose where you'd like to add this task",
                onRemindersSelected: {
                    Task {
                        let success = await integrationManager.addTaskToReminders(task, recordingName: recordingName)
                        await MainActor.run {
                            if success {
                                showingSuccessAlert = true
                            } else {
                                showingErrorAlert = true
                            }
                        }
                    }
                },
                onCalendarSelected: {
                    Task {
                        let success = await integrationManager.addTaskToCalendar(task, recordingName: recordingName)
                        await MainActor.run {
                            if success {
                                showingSuccessAlert = true
                            } else {
                                showingErrorAlert = true
                            }
                        }
                    }
                }
            )
        }
        .alert("Success", isPresented: $showingSuccessAlert) {
            Button("OK") { }
        } message: {
            Text("Task successfully added to system.")
        }
        .alert("Error", isPresented: $showingErrorAlert) {
            Button("OK") { }
        } message: {
            Text(integrationManager.lastError ?? "Failed to add task to system.")
        }
        .background(Color(.systemGray6).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private var priorityColor: Color {
        switch task.priority {
        case .high: return .red
        case .medium: return .orange
        case .low: return .green
        }
    }
    
    private var categoryColor: Color {
        switch task.category {
        case .call: return .blue
        case .meeting: return .orange
        case .purchase: return .green
        case .research: return .indigo
        case .email: return .purple
        case .travel: return .cyan
        case .health: return .red
        case .general: return .gray
        }
    }
    
    private var confidenceLevel: Int {
        switch task.confidence {
        case 0.8...1.0: return 3
        case 0.6..<0.8: return 2
        default: return 1
        }
    }
}

// MARK: - Enhanced Reminder Row Component

struct EnhancedReminderRowView: View {
    let reminder: ReminderItem
    let recordingName: String
    @StateObject private var integrationManager = SystemIntegrationManager()
    @State private var showingIntegrationSelection = false
    @State private var showingSuccessAlert = false
    @State private var showingErrorAlert = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Urgency indicator
            Image(systemName: reminder.urgency.icon)
                .foregroundColor(urgencyColor)
                .font(.caption)
                .padding(.top, 2)
            
            // Reminder content
            VStack(alignment: .leading, spacing: 4) {
                Text(reminder.text)
                    .font(.body)
                    .foregroundColor(.primary)
                    .lineLimit(nil)
                
                // Reminder metadata
                HStack {
                    Text(reminder.urgency.rawValue)
                        .font(.caption2)
                        .foregroundColor(urgencyColor)
                        .fontWeight(.medium)
                    
                    Image(systemName: "clock")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text(reminder.timeReference.displayText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    // Confidence indicator
                    HStack(spacing: 2) {
                        ForEach(0..<3, id: \.self) { index in
                            Circle()
                                .fill(index < confidenceLevel ? .orange : .gray.opacity(0.3))
                                .frame(width: 4, height: 4)
                        }
                    }
                }
                
                // Integration button
                HStack {
                    Spacer()
                    
                    Button(action: {
                        showingIntegrationSelection = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle")
                                .font(.caption)
                            Text("Add to System")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .disabled(integrationManager.isProcessing)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.systemGray6).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .sheet(isPresented: $showingIntegrationSelection) {
            IntegrationSelectionView(
                title: "Add Reminder to System",
                subtitle: "Choose where you'd like to add this reminder",
                onRemindersSelected: {
                    Task {
                        let success = await integrationManager.addReminderToReminders(reminder, recordingName: recordingName)
                        await MainActor.run {
                            if success {
                                showingSuccessAlert = true
                            } else {
                                showingErrorAlert = true
                            }
                        }
                    }
                },
                onCalendarSelected: {
                    Task {
                        let success = await integrationManager.addReminderToCalendar(reminder, recordingName: recordingName)
                        await MainActor.run {
                            if success {
                                showingSuccessAlert = true
                            } else {
                                showingErrorAlert = true
                            }
                        }
                    }
                }
            )
        }
        .alert("Success", isPresented: $showingSuccessAlert) {
            Button("OK") { }
        } message: {
            Text("Reminder successfully added to system.")
        }
        .alert("Error", isPresented: $showingErrorAlert) {
            Button("OK") { }
        } message: {
            Text(integrationManager.lastError ?? "Failed to add reminder to system.")
        }
    }
    
    private var urgencyColor: Color {
        switch reminder.urgency {
        case .immediate: return .red
        case .today: return .orange
        case .thisWeek: return .yellow
        case .later: return .blue
        }
    }
    
    private var confidenceLevel: Int {
        switch reminder.confidence {
        case 0.8...1.0: return 3
        case 0.6..<0.8: return 2
        default: return 1
        }
    }
} 