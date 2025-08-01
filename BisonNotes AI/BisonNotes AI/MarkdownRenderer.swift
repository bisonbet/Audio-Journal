//
//  MarkdownRenderer.swift
//  Audio Journal
//
//  Utility for rendering markdown text in SwiftUI views
//

import SwiftUI
import Foundation

// MARK: - Markdown Renderer

struct MarkdownRenderer {
    
    // MARK: - Public Methods
    
    /// Renders markdown text as an AttributedString for SwiftUI
    static func renderMarkdown(_ markdown: String) -> AttributedString {
        do {
            let attributedString = try AttributedString(markdown: markdown)
            return attributedString
        } catch {
            // Fallback to plain text if markdown parsing fails
            return AttributedString(markdown)
        }
    }
    
    /// Renders markdown text with custom styling
    static func renderMarkdown(_ markdown: String, style: MarkdownStyle = .default) -> AttributedString {
        do {
            var attributedString = try AttributedString(markdown: markdown)
            
            // Apply custom styling
            attributedString = applyCustomStyling(to: attributedString, style: style)
            
            return attributedString
        } catch {
            // Fallback to plain text if markdown parsing fails
            return AttributedString(markdown)
        }
    }
    
    /// Renders markdown text with enhanced list support
    static func renderEnhancedMarkdown(_ markdown: String) -> AttributedString {
        print("🔧 MarkdownRenderer: Starting to render markdown")
        print("📝 Input markdown: \(markdown.prefix(200))...")
        
        // Clean the markdown first
        let cleanedMarkdown = cleanMarkdown(markdown)
        
        do {
            // Try the standard markdown parser first
            let attributedString = try AttributedString(markdown: cleanedMarkdown)
            print("✅ Standard markdown parsing succeeded")
            return attributedString
        } catch {
            print("❌ Standard markdown parsing failed, trying custom formatting: \(error)")
            
            // Fallback to custom formatting
            return createCustomFormattedString(from: cleanedMarkdown)
        }
    }
    

    
    /// Creates a custom formatted string when markdown parsing fails
    private static func createCustomFormattedString(from markdown: String) -> AttributedString {
        var attributedString = AttributedString()
        
        let lines = markdown.components(separatedBy: .newlines)
        
        for (index, line) in lines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            if trimmedLine.isEmpty {
                // Add paragraph break only if not at the end and not followed by another empty line
                if index < lines.count - 1 {
                    let nextLine = lines[index + 1].trimmingCharacters(in: .whitespaces)
                    if !nextLine.isEmpty {
                        attributedString.append(AttributedString("\n"))
                    }
                }
                continue
            }
            
            // Handle headers with enhanced styling
            if trimmedLine.hasPrefix("### ") {
                let text = String(trimmedLine.dropFirst(4))
                var headerString = AttributedString(text)
                headerString.font = .title3.weight(.semibold)
                headerString.foregroundColor = .primary
                
                // Add a subtle background or border effect
                attributedString.append(AttributedString("\n"))
                attributedString.append(headerString)
                attributedString.append(AttributedString("\n"))
                
                // Add a subtle separator line
                var separatorString = AttributedString("─")
                separatorString.font = .caption
                separatorString.foregroundColor = .secondary
                attributedString.append(separatorString)
                attributedString.append(AttributedString("\n\n"))
                
            } else if trimmedLine.hasPrefix("## ") {
                let text = String(trimmedLine.dropFirst(3))
                var headerString = AttributedString(text)
                headerString.font = .title2.weight(.bold)
                headerString.foregroundColor = .primary
                attributedString.append(headerString)
                attributedString.append(AttributedString("\n\n"))
                
            } else if trimmedLine.hasPrefix("# ") {
                let text = String(trimmedLine.dropFirst(2))
                var headerString = AttributedString(text)
                headerString.font = .title.weight(.bold)
                headerString.foregroundColor = .primary
                attributedString.append(headerString)
                attributedString.append(AttributedString("\n\n"))
                
            } else if trimmedLine.hasPrefix("**") && trimmedLine.hasSuffix("**") && trimmedLine.count > 4 {
                // Bold text
                let text = String(trimmedLine.dropFirst(2).dropLast(2))
                var boldString = AttributedString(text)
                boldString.font = .body.weight(.semibold)
                attributedString.append(boldString)
                attributedString.append(AttributedString("\n\n"))
                
            } else if trimmedLine.hasPrefix("- ") || trimmedLine.hasPrefix("* ") {
                // Bullet point with enhanced styling
                let text = String(trimmedLine.dropFirst(2))
                var bulletString = AttributedString("• ")
                bulletString.font = .body
                bulletString.foregroundColor = .accentColor
                attributedString.append(bulletString)
                
                var contentString = AttributedString(text)
                contentString.font = .body
                attributedString.append(contentString)
                attributedString.append(AttributedString("\n"))
                
            } else if trimmedLine.matches("^\\d+\\. ") {
                // Numbered list with enhanced styling
                let numberEndIndex = trimmedLine.firstIndex(of: " ") ?? trimmedLine.startIndex
                let number = String(trimmedLine[..<numberEndIndex])
                let text = String(trimmedLine[numberEndIndex...]).trimmingCharacters(in: .whitespaces)
                
                var numberString = AttributedString("\(number). ")
                numberString.font = .body.weight(.medium)
                numberString.foregroundColor = .accentColor
                attributedString.append(numberString)
                
                var contentString = AttributedString(text)
                contentString.font = .body
                attributedString.append(contentString)
                attributedString.append(AttributedString("\n"))
                
            } else {
                // Regular text - handle inline formatting
                let formattedText = processInlineFormatting(trimmedLine)
                attributedString.append(formattedText)
                
                // Add appropriate spacing based on context
                if index < lines.count - 1 {
                    let nextLine = lines[index + 1].trimmingCharacters(in: .whitespaces)
                    if nextLine.isEmpty {
                        // Next line is empty, add paragraph break
                        attributedString.append(AttributedString("\n\n"))
                    } else if nextLine.hasPrefix("- ") || nextLine.hasPrefix("* ") || nextLine.matches("^\\d+\\. ") {
                        // Next line is a list item, add single line break
                        attributedString.append(AttributedString("\n"))
                    } else {
                        // Next line is regular text, add single line break
                        attributedString.append(AttributedString("\n"))
                    }
                }
            }
        }
        
        return attributedString
    }
    
    /// Processes inline formatting like bold and italic text
    private static func processInlineFormatting(_ text: String) -> AttributedString {
        var attributedString = AttributedString()
        var currentIndex = text.startIndex
        
        while currentIndex < text.endIndex {
            // Look for bold text first (double asterisks)
            if let boldStart = text[currentIndex...].firstIndex(of: "*") {
                let afterFirstAsterisk = text.index(after: boldStart)
                if afterFirstAsterisk < text.endIndex && text[afterFirstAsterisk] == "*" {
                    // Found double asterisk - look for closing double asterisk
                    let afterSecondAsterisk = text.index(after: afterFirstAsterisk)
                    if let boldEnd = text[afterSecondAsterisk...].firstIndex(of: "*") {
                        let afterBoldEnd = text.index(after: boldEnd)
                        if afterBoldEnd < text.endIndex && text[afterBoldEnd] == "*" {
                            // Found closing double asterisk - create bold text
                            let boldText = String(text[afterSecondAsterisk..<boldEnd])
                            var boldString = AttributedString(boldText)
                            boldString.font = .body.weight(.semibold)
                            attributedString.append(boldString)
                            
                            // Move past the closing double asterisk
                            currentIndex = text.index(after: afterBoldEnd)
                            continue
                        }
                    }
                }
            }
            
            // Look for single asterisks for emphasis/italic
            if let asteriskStart = text[currentIndex...].firstIndex(of: "*") {
                // Add text before the asterisk
                if asteriskStart > currentIndex {
                    let beforeText = String(text[currentIndex..<asteriskStart])
                    attributedString.append(AttributedString(beforeText))
                }
                
                // Look for the closing asterisk
                let afterAsterisk = text.index(after: asteriskStart)
                if let asteriskEnd = text[afterAsterisk...].firstIndex(of: "*") {
                    // Found matching asterisks - create italic text
                    let italicText = String(text[afterAsterisk..<asteriskEnd])
                    var italicString = AttributedString(italicText)
                    italicString.font = .body.italic()
                    attributedString.append(italicString)
                    
                    // Move past the closing asterisk
                    currentIndex = text.index(after: asteriskEnd)
                } else {
                    // No closing asterisk found - treat as regular text
                    attributedString.append(AttributedString("*"))
                    currentIndex = text.index(after: asteriskStart)
                }
            } else {
                // No more asterisks - add remaining text
                let remainingText = String(text[currentIndex...])
                attributedString.append(AttributedString(remainingText))
                break
            }
        }
        
        return attributedString
    }
    
    /// Renders markdown text with minimal preprocessing for better compatibility
    static func renderSimpleMarkdown(_ markdown: String) -> AttributedString {
        do {
            let attributedString = try AttributedString(markdown: markdown)
            return attributedString
        } catch {
            print("❌ Simple markdown parsing failed: \(error)")
            print("📝 Markdown: \(markdown)")
            // Fallback to plain text if markdown parsing fails
            return AttributedString(markdown)
        }
    }
    
    /// Renders AI-generated text with proper line break handling
    static func renderAIGeneratedText(_ text: String) -> AttributedString {
        print("🔧 MarkdownRenderer: Starting to render AI-generated text")
        print("📝 Input text: \(text.prefix(200))...")
        
        // Convert \n escape sequences to proper markdown line breaks
        let processedText = convertAITextWithLineBreaks(text)
        
        do {
            let attributedString = try AttributedString(markdown: processedText)
            print("✅ AI text markdown parsing succeeded")
            return attributedString
        } catch {
            print("❌ AI text markdown parsing failed, using custom formatting: \(error)")
            return createCustomFormattedString(from: processedText)
        }
    }
    
    /// Converts AI text with \n escape sequences to proper markdown
    private static func convertAITextWithLineBreaks(_ text: String) -> String {
        var result = text
        
        // Convert \n escape sequences to actual newlines first
        result = result.replacingOccurrences(of: "\\n", with: "\n")
        
        // Split by newlines to process each line
        let lines = result.components(separatedBy: .newlines)
        var processedLines: [String] = []
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            if trimmedLine.isEmpty {
                continue
            }
            
            // If line starts with "- " or "* ", it's a bullet point
            if trimmedLine.hasPrefix("- ") || trimmedLine.hasPrefix("* ") {
                processedLines.append(trimmedLine)
            } else if trimmedLine.matches("^\\d+\\. ") {
                // Numbered list
                processedLines.append(trimmedLine)
            } else if trimmedLine.hasPrefix("**") && trimmedLine.hasSuffix("**") {
                // Bold text as header
                let headerText = String(trimmedLine.dropFirst(2).dropLast(2))
                processedLines.append("## \(headerText)")
            } else {
                // Regular text
                processedLines.append(trimmedLine)
            }
        }
        
        // Join with double newlines to create proper paragraph breaks
        let markdown = processedLines.joined(separator: "\n\n")
        
        print("🔧 Converted AI text to markdown:")
        print(markdown.prefix(300))
        
        return markdown
    }
    
    /// Converts AI text to proper markdown format
    private static func convertAITextToMarkdown(_ text: String) -> String {
        var markdown = text
        
        // First, convert \n escape sequences to actual newlines
        markdown = markdown.replacingOccurrences(of: "\\n", with: "\n")
        
        // Split into lines
        let lines = markdown.components(separatedBy: .newlines)
        var processedLines: [String] = []
        
        for (_, line) in lines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            if trimmedLine.isEmpty {
                continue
            }
            
            // Handle bullet points that might be separated by \n
            if trimmedLine.hasPrefix("- ") || trimmedLine.hasPrefix("* ") {
                processedLines.append(trimmedLine)
            } else if trimmedLine.matches("^\\d+\\. ") {
                processedLines.append(trimmedLine)
            } else if trimmedLine.hasPrefix("**") && trimmedLine.hasSuffix("**") {
                // Bold text - add as header
                let text = String(trimmedLine.dropFirst(2).dropLast(2))
                processedLines.append("## \(text)")
            } else {
                // Regular text
                processedLines.append(trimmedLine)
            }
        }
        
        // Join with proper spacing - use double newlines for paragraph breaks
        let result = processedLines.joined(separator: "\n\n")
        
        print("🔧 Converted AI text to markdown:")
        print(result.prefix(300))
        
        return result
    }
    
    /// Cleans markdown text by removing unwanted formatting
    static func cleanMarkdown(_ markdown: String) -> String {
        var cleaned = markdown
        
        // Convert \n escape sequences to actual newlines first
        cleaned = cleaned.replacingOccurrences(of: "\\n", with: "\n")
        
        // Remove any leading/trailing whitespace
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Fix common markdown issues
        // Ensure proper spacing around headers
        cleaned = cleaned.replacingOccurrences(of: "\n#", with: "\n\n#")
        cleaned = cleaned.replacingOccurrences(of: "\n##", with: "\n\n##")
        cleaned = cleaned.replacingOccurrences(of: "\n###", with: "\n\n###")
        
        // Ensure proper spacing around lists
        cleaned = cleaned.replacingOccurrences(of: "\n- ", with: "\n\n- ")
        cleaned = cleaned.replacingOccurrences(of: "\n* ", with: "\n\n* ")
        cleaned = cleaned.replacingOccurrences(of: "\n1. ", with: "\n\n1. ")
        
        // Handle bullet points that are separated by \n in the original text
        // Convert patterns like "text. \n- " to "text.\n\n- "
        cleaned = cleaned.replacingOccurrences(of: "([.!?])\\s*\\n\\s*- ", with: "$1\n\n- ", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "([.!?])\\s*\\n\\s*\\* ", with: "$1\n\n* ", options: .regularExpression)
        
        // Handle numbered lists
        cleaned = cleaned.replacingOccurrences(of: "([.!?])\\s*\\n\\s*\\d+\\. ", with: "$1\n\n$2", options: .regularExpression)
        
        // Handle Google AI specific patterns
        // Convert "• " to "- " for consistency
        cleaned = cleaned.replacingOccurrences(of: "• ", with: "- ")
        
        // Ensure proper spacing after headers
        cleaned = cleaned.replacingOccurrences(of: "(### .*?)\\n([^-\\*\\d])", with: "$1\n\n$2", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "(## .*?)\\n([^-\\*\\d])", with: "$1\n\n$2", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "(# .*?)\\n([^-\\*\\d])", with: "$1\n\n$2", options: .regularExpression)
        
        // Remove excessive newlines (but preserve intentional paragraph breaks)
        cleaned = cleaned.replacingOccurrences(of: "\n{4,}", with: "\n\n", options: .regularExpression)
        
        // Remove excessive spaces
        cleaned = cleaned.replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)
        
        // Trim whitespace again
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return cleaned
    }
    
    /// Renders Google AI-generated content with enhanced styling
    static func renderGoogleAIContent(_ content: String) -> AttributedString {
        print("🔧 MarkdownRenderer: Starting to render Google AI content")
        print("📝 Input content: \(content.prefix(200))...")
        
        // Clean and preprocess the content
        let cleanedContent = cleanGoogleAIContent(content)
        
        // For Google AI content, prefer the custom formatter to ensure proper bold text handling
        print("🔧 Using custom formatter for Google AI content")
        return createGoogleAICustomFormattedString(from: cleanedContent)
    }
    
    /// Cleans Google AI content for better rendering
    private static func cleanGoogleAIContent(_ content: String) -> String {
        var cleaned = content
        
        // Convert \n escape sequences to actual newlines first
        cleaned = cleaned.replacingOccurrences(of: "\\n", with: "\n")
        
        // Handle unstructured content that comes as a single blob
        cleaned = restructureUnstructuredContent(cleaned)
        
        // If content is still very unstructured (no line breaks), use aggressive restructuring
        if !cleaned.contains("\n") {
            cleaned = aggressivelyRestructureContent(cleaned)
        }
        
        // Handle Google AI specific patterns
        // Convert "• " to "- " for consistency
        cleaned = cleaned.replacingOccurrences(of: "• ", with: "- ")
        
        // Ensure proper spacing around headers
        cleaned = cleaned.replacingOccurrences(of: "\n###", with: "\n\n###")
        cleaned = cleaned.replacingOccurrences(of: "\n##", with: "\n\n##")
        cleaned = cleaned.replacingOccurrences(of: "\n#", with: "\n\n#")
        
        // Ensure proper spacing around bullet points
        cleaned = cleaned.replacingOccurrences(of: "\n- ", with: "\n\n- ")
        cleaned = cleaned.replacingOccurrences(of: "\n* ", with: "\n\n* ")
        
        // Handle patterns where bullet points follow text without proper spacing
        cleaned = cleaned.replacingOccurrences(of: "([.!?])\\s*\\n\\s*- ", with: "$1\n\n- ", options: .regularExpression)
        
        // Remove excessive newlines
        cleaned = cleaned.replacingOccurrences(of: "\n{4,}", with: "\n\n", options: .regularExpression)
        
        // Remove excessive spaces (but be careful not to break formatting)
        cleaned = cleaned.replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)
        
        // Trim whitespace
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return cleaned
    }
    
    /// Restructures unstructured content that comes as a single blob
    private static func restructureUnstructuredContent(_ content: String) -> String {
        var restructured = content
        
        // First, try to identify and fix common patterns in unstructured content
        
        // Fix headers that are missing proper spacing
        restructured = restructured.replacingOccurrences(of: "([^\\n])(## )", with: "$1\n\n$2", options: .regularExpression)
        restructured = restructured.replacingOccurrences(of: "([^\\n])(### )", with: "$1\n\n$2", options: .regularExpression)
        restructured = restructured.replacingOccurrences(of: "([^\\n])(# )", with: "$1\n\n$2", options: .regularExpression)
        
        // Fix bullet points that are missing proper spacing
        restructured = restructured.replacingOccurrences(of: "([.!?])(\\s*)(• )", with: "$1\n\n$3", options: .regularExpression)
        restructured = restructured.replacingOccurrences(of: "([.!?])(\\s*)(- )", with: "$1\n\n$3", options: .regularExpression)
        restructured = restructured.replacingOccurrences(of: "([.!?])(\\s*)(\\* )", with: "$1\n\n$3", options: .regularExpression)
        
        // Add line breaks after sentences that are followed by headers or bullet points
        restructured = restructured.replacingOccurrences(of: "([.!?])(\\s*)([A-Z][a-z]+)", with: "$1\n\n$3", options: .regularExpression)
        
        // Fix common patterns where text runs together (but be careful with bold text)
        restructured = restructured.replacingOccurrences(of: "([a-z])([A-Z])(?![*])", with: "$1 $2", options: .regularExpression)
        
        // Clean up excessive spaces that might have been created
        restructured = restructured.replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)
        
        return restructured
    }
    
    /// Aggressively restructures very unstructured content that comes as a single blob
    private static func aggressivelyRestructureContent(_ content: String) -> String {
        var restructured = content
        
        // If the content has no line breaks at all, it's likely very unstructured
        if !restructured.contains("\n") {
            // Try to identify headers and add line breaks
            restructured = restructured.replacingOccurrences(of: "(## [^\\s]+)", with: "\n\n$1", options: .regularExpression)
            restructured = restructured.replacingOccurrences(of: "(### [^\\s]+)", with: "\n\n$1", options: .regularExpression)
            restructured = restructured.replacingOccurrences(of: "(# [^\\s]+)", with: "\n\n$1", options: .regularExpression)
            
            // Try to identify bullet points and add line breaks
            restructured = restructured.replacingOccurrences(of: "(• [^\\s]+)", with: "\n\n$1", options: .regularExpression)
            restructured = restructured.replacingOccurrences(of: "(- [^\\s]+)", with: "\n\n$1", options: .regularExpression)
            
            // Add line breaks after sentences that end with periods
            restructured = restructured.replacingOccurrences(of: "([.!?])(\\s+)([A-Z])", with: "$1\n\n$3", options: .regularExpression)
            
            // Fix common patterns where text runs together
            restructured = restructured.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
        }
        
        return restructured
    }
    
    /// Creates custom formatted string specifically for Google AI content
    private static func createGoogleAICustomFormattedString(from content: String) -> AttributedString {
        var attributedString = AttributedString()
        
        let lines = content.components(separatedBy: .newlines)
        
        for (index, line) in lines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            if trimmedLine.isEmpty {
                if index < lines.count - 1 {
                    let nextLine = lines[index + 1].trimmingCharacters(in: .whitespaces)
                    if !nextLine.isEmpty {
                        attributedString.append(AttributedString("\n"))
                    }
                }
                continue
            }
            
            // Handle Google AI headers with enhanced styling
            if trimmedLine.hasPrefix("### ") {
                let text = String(trimmedLine.dropFirst(4))
                var headerString = AttributedString(text)
                headerString.font = .title3.weight(.semibold)
                headerString.foregroundColor = .primary
                
                // Add spacing and visual separator
                attributedString.append(AttributedString("\n"))
                attributedString.append(headerString)
                attributedString.append(AttributedString("\n"))
                
                // Add a subtle separator line
                var separatorString = AttributedString("─")
                separatorString.font = .caption
                separatorString.foregroundColor = .secondary
                attributedString.append(separatorString)
                attributedString.append(AttributedString("\n\n"))
                
            } else if trimmedLine.hasPrefix("## ") {
                let text = String(trimmedLine.dropFirst(3))
                var headerString = AttributedString(text)
                headerString.font = .title2.weight(.bold)
                headerString.foregroundColor = .primary
                attributedString.append(headerString)
                attributedString.append(AttributedString("\n\n"))
                
            } else if trimmedLine.hasPrefix("# ") {
                let text = String(trimmedLine.dropFirst(2))
                var headerString = AttributedString(text)
                headerString.font = .title.weight(.bold)
                headerString.foregroundColor = .primary
                attributedString.append(headerString)
                attributedString.append(AttributedString("\n\n"))
                
            } else if trimmedLine.hasPrefix("- ") || trimmedLine.hasPrefix("* ") {
                // Enhanced bullet points
                let text = String(trimmedLine.dropFirst(2))
                var bulletString = AttributedString("• ")
                bulletString.font = .body
                bulletString.foregroundColor = .accentColor
                attributedString.append(bulletString)
                
                // Process inline formatting for bullet point content
                let formattedContent = processInlineFormatting(text)
                attributedString.append(formattedContent)
                attributedString.append(AttributedString("\n"))
                
            } else {
                // Regular text with enhanced inline formatting
                let formattedText = processInlineFormatting(trimmedLine)
                attributedString.append(formattedText)
                
                // Add appropriate spacing
                if index < lines.count - 1 {
                    let nextLine = lines[index + 1].trimmingCharacters(in: .whitespaces)
                    if nextLine.isEmpty {
                        attributedString.append(AttributedString("\n\n"))
                    } else {
                        attributedString.append(AttributedString("\n"))
                    }
                }
            }
        }
        
        return attributedString
    }
    
    // MARK: - Private Methods
    
    private static func applyCustomStyling(to attributedString: AttributedString, style: MarkdownStyle) -> AttributedString {
        // Apply custom styling based on the style configuration
        // This can be expanded to support different themes
        return attributedString
    }
    
    private static func preprocessMarkdown(_ markdown: String) -> String {
        var processed = markdown
        
        // Remove any leading/trailing whitespace
        processed = processed.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Ensure proper spacing for headers
        processed = processed.replacingOccurrences(of: "\n#", with: "\n\n#")
        processed = processed.replacingOccurrences(of: "\n##", with: "\n\n##")
        processed = processed.replacingOccurrences(of: "\n###", with: "\n\n###")
        
        // Clean up excessive spaces (but be more careful)
        processed = processed.replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)
        
        // Ensure proper line breaks
        processed = processed.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        
        // Remove any trailing whitespace
        processed = processed.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return processed
    }
}

// MARK: - Markdown Style

struct MarkdownStyle {
    let headingColor: Color
    let bodyColor: Color
    let linkColor: Color
    let emphasisColor: Color
    
    static let `default` = MarkdownStyle(
        headingColor: .primary,
        bodyColor: .primary,
        linkColor: .accentColor,
        emphasisColor: .primary
    )
    
    static let dark = MarkdownStyle(
        headingColor: .white,
        bodyColor: .white,
        linkColor: .blue,
        emphasisColor: .white
    )
}

// MARK: - String Extensions

extension String {
    func matches(_ pattern: String) -> Bool {
        return self.range(of: pattern, options: .regularExpression) != nil
    }
}

// MARK: - AttributedString Extensions
// Removed problematic extension that caused infinite recursion

// MARK: - SwiftUI Extensions

extension View {
    /// Displays markdown text with proper rendering
    func markdownText(_ markdown: String, style: MarkdownStyle = .default) -> some View {
        let cleanedMarkdown = MarkdownRenderer.cleanMarkdown(markdown)
        let attributedString = MarkdownRenderer.renderEnhancedMarkdown(cleanedMarkdown)
        
        return Text(attributedString)
            .textSelection(.enabled)
    }
    
    /// Displays markdown text with enhanced formatting
    func enhancedMarkdownText(_ markdown: String) -> some View {
        let cleanedMarkdown = MarkdownRenderer.cleanMarkdown(markdown)
        let attributedString = MarkdownRenderer.renderEnhancedMarkdown(cleanedMarkdown)
        
        return Text(attributedString)
            .textSelection(.enabled)
    }
    
    /// Displays Google AI content with enhanced styling for headers and bullet points
    func googleAIContentText(_ content: String) -> some View {
        let attributedString = MarkdownRenderer.renderGoogleAIContent(content)
        
        return Text(attributedString)
            .textSelection(.enabled)
    }
} 