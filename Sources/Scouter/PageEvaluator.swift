//
//  PageEvaluator.swift
//  Scouter
//
//  Created by Norikazu Muramoto on 2024/11/12.
//

import Foundation
import OllamaKit
import AspectAnalyzer

/// Evaluates pages based on content relevance, semantic similarity, and aspect coverage
public actor PageEvaluator {
    
    /// Represents the evaluation results for a page
    public struct PageEvaluation: Sendable, CustomStringConvertible {
        /// The evaluated page content and metadata
        public let content: String
        public let metadata: PageMetadata
        
        /// Content relevance scores
        public let contentSimilarity: Float

        /// Detailed content analysis
        public let matchedKeywords: Set<String>
        
        /// Overall evaluation score (0.0 to 1.0)
        public var score: Float {
            let similarityFactor = contentSimilarity * 0.8
            let keywordFactor = Float(matchedKeywords.count) * 0.2
            // Combine scores
            return contentSimilarity + keywordFactor
        }
        
        public var description: String {
            // Get the aspect coverage info (there should only be one entry now)
            return """
            Score: \(String(format: "%.2f", score))
            Similarity: \(String(format: "%.2f", contentSimilarity))
            """
        }
    }
    
    private let model: String
    private let ollamaKit: OllamaKit
    
    public init(model: String) {
        self.model = model
        self.ollamaKit = OllamaKit()
    }
    
    /// Evaluates a page's content and metadata for relevance to the query
    /// - Parameters:
    ///   - content: The page content to evaluate
    ///   - metadata: Page metadata including description, keywords, etc.
    ///   - queryAnalysis: Analysis of the original query
    /// - Returns: A PageEvaluation containing detailed analysis results
    public func evaluate(
        content: String,
        metadata: PageMetadata,
        queryAnalysis: Scouter.QueryAnalysis
    ) async throws -> PageEvaluation {
        // Get embedding for page content summary
        let contentSummary = summarizeContent(content)
        let contentEmbedding = try await getContentEmbedding(contentSummary)
        
        // Calculate similarities and coverage
        let contentSimilarity = cosineSimilarity(
            contentEmbedding,
            queryAnalysis.query.embedding
        )
        
        // Find keyword matches and missing aspects
        let matchedKeywords = findKeywordMatches(
            in: content,
            aspects: queryAnalysis.analysis.aspects
        )
        
        return PageEvaluation(
            content: content,
            metadata: metadata,
            contentSimilarity: contentSimilarity,
            matchedKeywords: matchedKeywords
        )
    }
    
    /// Gets embedding for content summary
    private func getContentEmbedding(_ content: String) async throws -> [Float] {
        let data = OKEmbeddingsRequestData(model: model, prompt: content)
        let response = try await ollamaKit.embeddings(data: data)
        return response.embedding!
    }
    
    /// Calculates coverage for each aspect in the content
    private func calculateAspectCoverage(
        content: String,
        aspects: [AspectAnalyzer.Aspect]
    ) async throws -> [AspectAnalyzer.Aspect: Float] {
        var coverage: [AspectAnalyzer.Aspect: Float] = [:]
        
        let criticalAspects = aspects
        
        let targetAspects = criticalAspects.isEmpty ?
        Array(aspects.sorted { $0.importance > $1.importance }.prefix(3)) :
        criticalAspects
        
        let contentEmbedding = try await getContentEmbedding(content)
        
        for aspect in targetAspects {
            let aspectContext = [
                aspect.description,
                Array(aspect.requiredKnowledge).joined(separator: ", "),
                Array(aspect.expectedInfoTypes).joined(separator: ", ")
            ].joined(separator: ". ")
            
            let aspectEmbedding = try await getContentEmbedding(aspectContext)
            let similarity = cosineSimilarity(aspectEmbedding, contentEmbedding)
            
            coverage[aspect] = similarity * aspect.importance
        }
        
        return coverage
    }

    
    /// Finds keyword matches in the content
    private func findKeywordMatches(
        in content: String,
        aspects: [AspectAnalyzer.Aspect]
    ) -> Set<String> {
        let keywords = aspects.flatMap { aspect -> [String] in
            let words = aspect.description
                .lowercased()
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { $0.count > 3 }
            return words + Array(aspect.requiredKnowledge)
        }
        
        let contentLower = content.lowercased()
        return Set(keywords.filter { contentLower.contains($0.lowercased()) })
    }
    
    /// Identifies aspects with insufficient coverage
    private func findMissingAspects(
        coverage: [AspectAnalyzer.Aspect: Float],
        threshold: Float
    ) -> [AspectAnalyzer.Aspect] {
        return coverage.filter { $0.value < threshold }.map(\.key)
    }
    
    /// Creates a summary of the content for embedding
    private func summarizeContent(_ content: String) -> String {
        // Get first ~1000 characters as a summary
        let maxLength = 1000
        if content.count <= maxLength {
            return content
        }
        return String(content.prefix(maxLength))
    }
    
    /// Calculates cosine similarity between two embeddings
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0.0 }
        
        let dotProduct = zip(a, b).map(*).reduce(0, +)
        let normA = sqrt(a.map { $0 * $0 }.reduce(0, +))
        let normB = sqrt(b.map { $0 * $0 }.reduce(0, +))
        
        guard normA > 0 && normB > 0 else { return 0.0 }
        return dotProduct / (normA * normB)
    }
}

// MARK: - Batch Evaluation Extension
extension PageEvaluator {
    /// Evaluates multiple pages serially
    /// - Parameters:
    ///   - pages: Array of (content, metadata) tuples to evaluate
    ///   - queryAnalysis: The query analysis
    /// - Returns: Array of page evaluations sorted by score
    public func evaluatePages(
        _ pages: [(content: String, metadata: PageMetadata)],
        queryAnalysis: Scouter.QueryAnalysis
    ) async throws -> [PageEvaluation] {
        var evaluations: [PageEvaluation] = []
        
        // Process pages serially to avoid overwhelming the model
        for (content, metadata) in pages {
            let evaluation = try await evaluate(
                content: content,
                metadata: metadata,
                queryAnalysis: queryAnalysis
            )
            evaluations.append(evaluation)
        }
        
        // Sort by score in descending order
        return evaluations.sorted { $0.score > $1.score }
    }
}
