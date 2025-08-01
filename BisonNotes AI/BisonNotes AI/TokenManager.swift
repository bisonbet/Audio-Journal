//
//  TokenManager.swift
//  Audio Journal
//
//  Token counting and chunking utilities for large transcript processing
//

import Foundation
import NaturalLanguage

// MARK: - Token Manager

class TokenManager {
    
    // MARK: - Configuration
    
    /// Default maximum tokens per chunk. This can be overridden when calling
    /// chunking functions for models with different context sizes.
    static let maxTokensPerChunk = 2048
    static let maxTokensForFinalSummary = 4096
    static let estimatedTokensPerWord = 1.3 // Conservative estimate for English text
    
    // MARK: - Token Counting
    
    /// Estimate token count for a given text
    /// This is an approximation since we don't have access to the actual tokenizer
    static func estimateTokenCount(for text: String) -> Int {
        let words = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        
        // Count tokens more accurately by considering punctuation and special characters
        var tokenCount = 0
        
        for word in words {
            // Base word token
            tokenCount += 1
            
            // Add tokens for punctuation and special characters
            let punctuationCount = word.filter { ".,!?;:'\"()[]{}".contains($0) }.count
            tokenCount += punctuationCount
            
            // Add tokens for numbers and special characters
            let specialCharCount = word.filter { "0123456789@#$%^&*+=<>/\\|".contains($0) }.count
            tokenCount += specialCharCount
        }
        
        // Add tokens for sentence boundaries and formatting
        let sentenceCount = text.components(separatedBy: CharacterSet(charactersIn: ".!?")).count
        tokenCount += sentenceCount
        
        return max(tokenCount, 1) // Ensure at least 1 token
    }
    
    /// More accurate token estimation using NLP
    static func estimateTokenCountNLP(for text: String) -> Int {
        let tagger = NLTagger(tagSchemes: [.tokenType])
        tagger.string = text
        
        var tokenCount = 0
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .tokenType) { _, range in
            tokenCount += 1
            return true
        }
        
        // Add tokens for punctuation and special characters
        let punctuationCount = text.filter { ".,!?;:'\"()[]{}".contains($0) }.count
        tokenCount += punctuationCount
        
        return max(tokenCount, 1)
    }
    
    // MARK: - Chunking
    
    /// Split text into chunks based on token count
    static func chunkText(_ text: String, maxTokens: Int = maxTokensPerChunk) -> [String] {
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        var chunks: [String] = []
        var currentChunk: [String] = []
        var currentTokenCount = 0
        
        for sentence in sentences {
            let sentenceTokenCount = estimateTokenCount(for: sentence)
            
            // If adding this sentence would exceed the limit, start a new chunk
            if currentTokenCount + sentenceTokenCount > maxTokens && !currentChunk.isEmpty {
                // Finalize current chunk
                let chunkText = currentChunk.joined(separator: ". ") + "."
                chunks.append(chunkText)
                
                // Start new chunk
                currentChunk = [sentence]
                currentTokenCount = sentenceTokenCount
            } else {
                // Add sentence to current chunk
                currentChunk.append(sentence)
                currentTokenCount += sentenceTokenCount
            }
        }
        
        // Add remaining chunk
        if !currentChunk.isEmpty {
            let chunkText = currentChunk.joined(separator: ". ") + "."
            chunks.append(chunkText)
        }
        
        return chunks
    }
    
    /// Check if text needs chunking
    static func needsChunking(_ text: String, maxTokens: Int = maxTokensPerChunk) -> Bool {
        let tokenCount = estimateTokenCount(for: text)
        return tokenCount > maxTokens
    }
    
    /// Get token count for text
    static func getTokenCount(_ text: String) -> Int {
        return estimateTokenCount(for: text)
    }
    
    // MARK: - Chunk Processing
    
    /// Process chunks and combine results
    static func processChunks<T>(
        _ chunks: [String],
        processor: @escaping (String) async throws -> T
    ) async throws -> [T] {
        var results: [T] = []
        
        for (index, chunk) in chunks.enumerated() {
            print("🔄 Processing chunk \(index + 1) of \(chunks.count) (\(getTokenCount(chunk)) tokens)")
            
            do {
                let result = try await processor(chunk)
                results.append(result)
            } catch {
                print("❌ Failed to process chunk \(index + 1): \(error)")
                throw error
            }
        }
        
        return results
    }
    
    /// Combine multiple summaries into a cohesive meta-summary using Ollama
    static func combineSummaries(
        _ summaries: [String],
        contentType: ContentType,
        service: OllamaService
    ) async throws -> String {
        guard !summaries.isEmpty else { return "" }

        // Join all summaries into one text block
        let combinedText = summaries.joined(separator: " ")

        // Generate meta-summary ensuring context limits are respected
        let metaSummary = try await generateMetaSummary(from: combinedText, service: service)

        switch contentType {
        case .meeting:
            return "Meeting Summary: \(metaSummary)"
        case .personalJournal:
            return "Personal Reflection: \(metaSummary)"
        case .technical:
            return "Technical Discussion: \(metaSummary)"
        case .general:
            return "Summary: \(metaSummary)"
        }
    }

    /// Recursively generate a meta-summary that fits within the model's context window
    private static func generateMetaSummary(from text: String, service: OllamaService) async throws -> String {
        let maxTokens = service.maxContextTokens

        // If text fits within context window, summarize directly
        if getTokenCount(text) <= maxTokens {
            return try await service.generateSummary(from: text)
        }

        // Otherwise, chunk the text and summarize each piece
        let chunks = chunkText(text, maxTokens: maxTokens)
        var intermediateSummaries: [String] = []

        for chunk in chunks {
            let summary = try await service.generateSummary(from: chunk)
            intermediateSummaries.append(summary)
        }

        // Recursively summarize the combined intermediate summaries
        let reducedText = intermediateSummaries.joined(separator: " ")
        return try await generateMetaSummary(from: reducedText, service: service)
    }
}

// MARK: - Chunked Processing Result

struct ChunkedProcessingResult {
    let summaries: [String]
    let allTasks: [TaskItem]
    let allReminders: [ReminderItem]
    let contentType: ContentType
    let totalChunks: Int
    let processingTime: TimeInterval

    func combinedSummary(using service: OllamaService) async throws -> String {
        return try await TokenManager.combineSummaries(summaries, contentType: contentType, service: service)
    }
    
    var deduplicatedTasks: [TaskItem] {
        // Remove duplicate tasks based on text similarity
        var uniqueTasks: [TaskItem] = []
        
        for task in allTasks {
            let isDuplicate = uniqueTasks.contains { existingTask in
                let similarity = calculateTextSimilarity(task.text, existingTask.text)
                return similarity > 0.8
            }
            
            if !isDuplicate {
                uniqueTasks.append(task)
            }
        }
        
        return Array(uniqueTasks.prefix(15)) // Limit to 15 tasks
    }
    
    var deduplicatedReminders: [ReminderItem] {
        // Remove duplicate reminders based on text similarity
        var uniqueReminders: [ReminderItem] = []
        
        for reminder in allReminders {
            let isDuplicate = uniqueReminders.contains { existingReminder in
                let similarity = calculateTextSimilarity(reminder.text, existingReminder.text)
                return similarity > 0.8
            }
            
            if !isDuplicate {
                uniqueReminders.append(reminder)
            }
        }
        
        return Array(uniqueReminders.prefix(15)) // Limit to 15 reminders
    }
    
    private func calculateTextSimilarity(_ text1: String, _ text2: String) -> Double {
        let words1 = Set(text1.lowercased().components(separatedBy: .whitespacesAndNewlines))
        let words2 = Set(text2.lowercased().components(separatedBy: .whitespacesAndNewlines))
        
        let intersection = words1.intersection(words2)
        let union = words1.union(words2)
        
        return union.isEmpty ? 0.0 : Double(intersection.count) / Double(union.count)
    }
} 