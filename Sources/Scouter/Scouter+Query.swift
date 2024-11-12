//
//  Scouter+Query.swift
//  Scouter
//
//  Created by Norikazu Muramoto on 2024/11/12.
//

import Foundation
import AspectAnalyzer
import OllamaKit

extension Scouter {
    
    public struct Query: Identifiable, Sendable {
        public let id: UUID
        public let prompt: String
        public let embedding: [Float]
        
        public init(
            id: UUID = UUID(),
            prompt: String,
            embedding: [Float]
        ) {
            self.id = id
            self.prompt = prompt
            self.embedding = embedding
        }
    }
    
    /// A structure that combines a query with its analysis results and ideal answer template.
    public struct QueryAnalysis: Identifiable, Sendable {
        /// The unique identifier for the query analysis
        public let id: UUID
        
        /// The original query information
        public let query: Query
        
        /// The analysis results from AspectAnalyzer
        public let analysis: AspectAnalyzer.Analysis
        
        /// The template for an ideal answer to the query
        public let idealAnswerTemplate: String
        
        public let idealAnswerTemplateEmbedding: [Float]
        
        /// Timestamp when the analysis was performed
        public let analyzedAt: Date
        
        /// Creates a new QueryAnalysis instance.
        /// - Parameters:
        ///   - id: The unique identifier (default: new UUID)
        ///   - query: The query being analyzed
        ///   - analysis: Results from AspectAnalyzer
        ///   - idealAnswerTemplate: Template for the ideal answer
        ///   - analyzedAt: Timestamp of analysis (default: current date)
        public init(
            id: UUID = UUID(),
            query: Query,
            analysis: AspectAnalyzer.Analysis,
            idealAnswerTemplate: String,
            idealAnswerTemplateEmbedding: [Float],
            analyzedAt: Date = Date()
        ) {
            self.id = id
            self.query = query
            self.analysis = analysis
            self.idealAnswerTemplate = idealAnswerTemplate
            self.idealAnswerTemplateEmbedding = idealAnswerTemplateEmbedding
            self.analyzedAt = analyzedAt
        }
        
        /// Returns whether the query is considered complex based on analysis
        public var isComplex: Bool {
            analysis.complexityScore > 0.7
        }
        
        /// Returns all knowledge areas required across all aspects
        public var requiredKnowledge: Set<String> {
            Set(analysis.aspects.flatMap { $0.requiredKnowledge })
        }
        
        /// Returns all expected information types across all aspects
        public var expectedInfoTypes: Set<String> {
            Set(analysis.aspects.flatMap { $0.expectedInfoTypes })
        }
        
        /// Returns aspects sorted by importance, filtered by a minimum threshold
        /// - Parameter threshold: Minimum importance score (default: 0.5)
        /// - Returns: Array of aspects meeting the threshold, sorted by importance
        public func significantAspects(threshold: Float = 0.5) -> [AspectAnalyzer.Aspect] {
            analysis.aspects
                .filter { $0.importance >= threshold }
                .sorted { $0.importance > $1.importance }
        }
    }
}

// MARK: - Query Extension
extension Scouter.Query {
    /// Creates a QueryAnalysis by performing aspect analysis and generating an ideal answer template
    /// - Parameters:
    ///   - model: The model identifier to use for analysis
    ///   - ollamaKit: The OllamaKit instance to use
    /// - Returns: A complete QueryAnalysis instance
    public func analyze(
        model: String
    ) async throws -> Scouter.QueryAnalysis {
        let analyzer = AspectAnalyzer(model: model)
        let analysis = try await analyzer.analyzeQuery(prompt)
        let idealAnswerTemplate = try await Scouter.Query.generateIdealAnswerTemplate(
            query: prompt,
            model: model
        )
        let embedding = try await Scouter.Query.getEmbedding(for: idealAnswerTemplate, model: model)
        return Scouter.QueryAnalysis(
            query: self,
            analysis: analysis,
            idealAnswerTemplate: idealAnswerTemplate,
            idealAnswerTemplateEmbedding: embedding
        )
    }
    
    /// Generates an ideal answer template based on the query
    /// - Parameters:
    ///   - prompt: The query prompt
    ///   - ollamaKit: The OllamaKit instance to use
    ///   - model: The model identifier
    /// - Returns: A template string for the ideal answer
    private static func generateIdealAnswerTemplate(
        query: String,
        model: String
    ) async throws -> String {
        let data = OKChatRequestData(
            model: model,
            messages: [
                .system(
                    """
                    You are an AI assistant. Please respond to the user’s requests.
                    
                    **Guidelines**:
                    - Show respect to the user and maintain a polite and friendly demeanor.
                    - Provide helpful and accurate information for the user.
                    - Avoid content that could harm or offend the user.
                    - Refrain from making unethical statements or providing inappropriate content.
                    - Make every effort to avoid hallucinations (information that is incorrect or misleading).
                    - Always maintain a fair and neutral stance.
                    - Use the *same language as the query language*.
                    
                    Please create an ideal answer template in response to the user's question, using placeholders in all cases. Regardless of whether the information is known or unknown, include all information with placeholders such as `[TBD]` or appropriate categories (e.g., [Name:TBD], [Date:TBD]). Ensure that no specific objects are included in the answer. Additionally, structure the response in natural language, making it easy for humans to read. Your response will be used for search purposes.
                    Your knowledge may be outdated due to the cutoff. Even for questions related to a timeline, assume information exists and use `[TBD]` for unknown details when creating the template.
                    
                    Please execute each of the following steps one at a time:
                    
                    **Step**:
                    1. Carefully read and understand the user’s query.
                    2. Determine the user’s language.
                    3. Clearly identify the specific information the user wants to know (target information).
                    4. Create an ideal response template in natural language that includes the target information.
                    5. Ensure that the target information is marked as `[TBD]` in the template.
                    6. Display the final response template for the query.
                    
                    Note: The user's question is referred to as "Query."
                    """
                ),
                .user(
                    """
                    Query: 
                    \(query)
                    
                    Ideal answer template(Use same language as the query language):
                    """)
            ]
        ) { options in
            options.temperature = 0.3
        }
        
        var response = ""
        for try await chunk in OllamaKit().chat(data: data) {
            response += chunk.message?.content ?? ""
        }
        return response
    }
    
    /// Gets embedding for text using OllamaKit
    static func getEmbedding(for text: String, model: String = "llama3.2:latest") async throws -> [Float] {
        let data = OKEmbeddingsRequestData(
            model: model,
            prompt: text
        )
        let response = try await OllamaKit().embeddings(data: data)
        return response.embedding!
    }
}

extension Scouter.QueryAnalysis: CustomStringConvertible {
    public var description: String {
        """
        📝 Query Analysis Report
        ═══════════════════════
        
        🔍 Query: "\(query.prompt)"
        
        📊 Analysis Metrics:
        • Complexity Score: \(String(format: "%.1f%%", analysis.complexityScore * 100))
        • Analysis Time: \(analyzedAt.formatted())
        
        🎯 Critical Aspects (\(analysis.criticalAspects.count)):
        \(formatAspects(analysis.criticalAspects))
        
        🔑 Key Knowledge Areas:
        \(formatSet(requiredKnowledge, bullet: "•"))
        
        📚 Expected Information Types:
        \(formatSet(expectedInfoTypes, bullet: "•"))
        
        📋 Ideal Answer Template:
        ───────────────────────
        \(formatTemplate(idealAnswerTemplate))
        ───────────────────────
        
        🏷 Primary Focus Areas:
        \(formatSet(analysis.primaryFocus, bullet: "•"))
        
        \(complexityNote)
        """
    }
    
    private func formatAspects(_ aspects: [AspectAnalyzer.Aspect]) -> String {
        guard !aspects.isEmpty else {
            return "  No critical aspects identified"
        }
        
        let keywords = extractKeywords(from: aspects)
        
        return """
    📎 Keywords: [\(keywords.joined(separator: ", "))]
    
    \(aspects
        .map { aspect -> String in
            """
              • \(aspect.description)
                Importance: \(String(format: "%.1f%%", aspect.importance * 100))
                Knowledge: [\(aspect.requiredKnowledge.joined(separator: ", "))]
                Info Types: [\(aspect.expectedInfoTypes.joined(separator: ", "))]
            """
        }
        .joined(separator: "\n\n"))
    """
    }
    
    private func formatSet(_ set: Set<String>, bullet: String) -> String {
        guard !set.isEmpty else {
            return "  None specified"
        }
        return set.sorted()
            .map { "  \(bullet) \($0)" }
            .joined(separator: "\n")
    }
    
    private func formatTemplate(_ template: String) -> String {
        template
            .split(separator: "\n")
            .map { "  \($0)" }
            .joined(separator: "\n")
    }
    
    private func extractKeywords(from aspects: [AspectAnalyzer.Aspect]) -> [String] {
        var keywords = Set<String>()
        
        // Extract words from aspect descriptions
        for aspect in aspects {
            let words = aspect.description
                .lowercased()
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { $0.count > 3 } // Filter out short words
            keywords.formUnion(words)
            
            // Add knowledge areas as keywords
            keywords.formUnion(aspect.requiredKnowledge)
        }
        
        // Sort keywords for consistent display
        return Array(keywords).sorted()
    }
    
    private var complexityNote: String {
        let complexityLevel: String
        switch analysis.complexityScore {
        case 0.0..<0.3:
            complexityLevel = "Low complexity query"
        case 0.3..<0.6:
            complexityLevel = "Moderate complexity query"
        case 0.6..<0.8:
            complexityLevel = "High complexity query"
        default:
            complexityLevel = "Very high complexity query"
        }
        
        return """
        📌 Note: \(complexityLevel) (Score: \(String(format: "%.2f", analysis.complexityScore)))
        """
    }
}
