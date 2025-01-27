//
//  Summarizing.swift
//  Scouter
//
//  Created by Norikazu Muramoto on 2025/01/27.
//

import Foundation

public protocol Summarizing: Sendable {
    func summarize(pages: [Page], query: String) async throws -> Summary
}

public struct Summary: Sendable, Codable {
    public let query: String
    public let overview: String
    public let keyPoints: [String]
    public let sourceURLs: [URL]
    public let generatedAt: Date
    
    public init(
        query: String,
        overview: String,
        keyPoints: [String],
        sourceURLs: [URL],
        generatedAt: Date = Date()
    ) {
        self.query = query
        self.overview = overview
        self.keyPoints = keyPoints
        self.sourceURLs = sourceURLs
        self.generatedAt = generatedAt
    }
}

enum SummarizerError: Error {
    case invalidResponse
    case noContent
}

extension Summarizing {
    var summarySystemPrompt: String {
        """
        You are an expert technical documentation writer and analyst. Create a detailed technical analysis 
        that matches the following JSON structure exactly:
        {
          "overview": "A comprehensive technical explanation",
          "keyPoints": ["Detailed point 1", "Detailed point 2", ...],
          "sourceURLs": ["url1", "url2", ...]
        }
        
        Your analysis should:
        1. Provide exhaustive technical coverage with complete accuracy
        2. Include implementation details and practical considerations
        3. Cover all relevant specifications and methodologies
        4. Explain complex concepts thoroughly
        5. Reference concrete examples and evidence
        
        Ensure each component maintains valid JSON string format while being comprehensive.
        """
    }
    
    func generateSummaryPrompt(pages: [Page], query: String) -> String {
        """
        Primary Research Query: \(query)
        
        Analyze these source materials thoroughly (ordered by priority 5=highest to 1=lowest):
        
        \(pages.map { page in
            """
            [Priority: \(page.priority.rawValue)]
            URL: \(page.url)
            Content: \(page.remark.plainText.prefix(2000))
            ---
            """
        }.joined(separator: "\n\n"))
        
        Return a detailed analysis in this exact JSON structure:
        {
          "overview": "A comprehensive explanation covering technical background, architecture, methodology, and implications",
          "keyPoints": [
            "Detailed technical section 1 covering implementation, configuration, and best practices",
            "Detailed technical section 2 with specific examples and evidence",
            ... (create 8-12 detailed sections)
          ],
          "sourceURLs": [
            "url1",
            "url2",
            ... (ordered by relevance)
          ]
        }
        
        For the overview:
        - Provide complete technical background and context
        - Explain core concepts and architecture thoroughly
        - Include methodologies and critical analysis
        - Cover practical implications and considerations
        
        For each key point:
        - Write as a detailed technical section
        - Include implementation details and configurations
        - Provide specific examples and evidence
        - Cover best practices and considerations
        - Ensure it's formatted as a valid JSON string
        
        Make the content comprehensive and technically precise while maintaining valid JSON format.
        """
    }
}
