//
//  LinkEvalutor.swift
//  Scouter
//
//  Created by Norikazu Muramoto on 2024/11/12.
//

import Foundation
import OllamaKit
import Selenops
import AspectAnalyzer

/// Evaluates links based on similarity to query and presence of keywords
public actor LinkEvaluator {
    
    /// Represents the evaluation results for a link
    public struct LinkEvaluation: Sendable, CustomStringConvertible {
        /// Priority levels for evaluated links
        public enum Priority: Int, Comparable, Sendable {
            case critical = 3  // Highly relevant to both query and template
            case high = 2      // Relevant to query or template
            case medium = 1    // Contains keywords
            case low = 0       // Basic match
            
            public static func < (lhs: Priority, rhs: Priority) -> Bool {
                return lhs.rawValue < rhs.rawValue
            }
        }
        
        /// The evaluated link
        public let link: Crawler.Link
        
        /// Similarity score with query
        public let querySimilarity: Float
        
        /// Similarity score with ideal answer template
        public let templateSimilarity: Float
        
        /// Keywords found in the title
        public let matchedKeywords: Set<String>
        
        /// Assigned priority level
        public let priority: Priority
        
        /// Combined evaluation score
        public var score: Float {
            // Take the maximum of query and template similarities
            let similarityScore = max(querySimilarity, templateSimilarity)
            
            // Keyword bonus points - each keyword adds 0.15 to the score
            let keywordBonus = Float(matchedKeywords.count) * 0.8
            
            // Combine scores with maximum cap
            let totalScore = similarityScore + keywordBonus
            return min(totalScore, 1.0)
        }
        
        public var description: String {
            switch priority {
            case .low: return "Low"
            case .medium: return "Medium"
            case .high: return "High"
            case .critical: return "Critical"
            }
        }
    }
    
    private let model: String
    private let ollamaKit: OllamaKit
    
    public init(model: String) {
        self.model = model
        self.ollamaKit = OllamaKit()
    }
    
    /// Evaluates a link's relevance to the query and ideal answer template
    /// - Parameters:
    ///   - link: The link to evaluate
    ///   - queryAnalysis: The query analysis containing embeddings and keywords
    /// - Returns: A LinkEvaluation containing similarity scores and priority
    public func evaluate(
        link: Crawler.Link,
        queryAnalysis: Scouter.QueryAnalysis
    ) async throws -> LinkEvaluation {
        // Get embedding for link title
        let titleEmbedding = try await getLinkEmbedding(title: link.title)
        
        // Calculate similarities
        let querySimilarity = cosineSimilarity(
            titleEmbedding,
            queryAnalysis.query.embedding
        )
        
        let templateSimilarity = cosineSimilarity(
            titleEmbedding,
            queryAnalysis.idealAnswerTemplateEmbedding
        )
        
        // Find keyword matches
        let matchedKeywords = findKeywordMatches(
            in: link.title,
            aspects: queryAnalysis.analysis.aspects
        )
        
        // Determine priority
        let priority = calculatePriority(
            querySimilarity: querySimilarity,
            templateSimilarity: templateSimilarity,
            keywordCount: matchedKeywords.count
        )
        
        return LinkEvaluation(
            link: link,
            querySimilarity: querySimilarity,
            templateSimilarity: templateSimilarity,
            matchedKeywords: matchedKeywords,
            priority: priority
        )
    }
    
    /// Gets embedding for link title
    private func getLinkEmbedding(title: String) async throws -> [Float] {
        let data = OKEmbeddingsRequestData(model: model, prompt: title)
        let response = try await ollamaKit.embeddings(data: data)
        return response.embedding!
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
    
    /// Finds keyword matches in the title
    private func findKeywordMatches(
        in title: String,
        aspects: [AspectAnalyzer.Aspect]
    ) -> Set<String> {
        // Collect keywords from aspects
        let keywords = aspects.flatMap { aspect -> [String] in
            // Split aspect description into potential keywords
            let words = aspect.description
                .lowercased()
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { $0.count > 3 } // Filter out short words
            
            // Add knowledge areas as keywords
            return words + Array(aspect.requiredKnowledge)
        }
        
        // Find matches in title
        let titleLower = title.lowercased()
        return Set(keywords.filter { titleLower.contains($0.lowercased()) })
    }
    
    /// Calculates priority based on similarity scores and keyword matches
    private func calculatePriority(
        querySimilarity: Float,
        templateSimilarity: Float,
        keywordCount: Int
    ) -> LinkEvaluation.Priority {
        // Thresholds for different priority levels
        let criticalThreshold: Float = 0.8
        let highThreshold: Float = 0.6
        let mediumThreshold: Float = 0.4
        
        // Check for critical priority
        if querySimilarity >= criticalThreshold && templateSimilarity >= criticalThreshold {
            return .critical
        }
        
        // Check for high priority
        if querySimilarity >= highThreshold || templateSimilarity >= highThreshold {
            return .high
        }
        
        // Check for medium priority
        if querySimilarity >= mediumThreshold || templateSimilarity >= mediumThreshold || keywordCount >= 2 {
            return .medium
        }
        
        // Default to low priority
        return .low
    }
}

// TODO: 
//// MARK: - Batch Evaluation Extension
//extension LinkEvaluator {
//    /// Evaluates multiple links in parallel
//    /// - Parameters:
//    ///   - links: Array of links to evaluate
//    ///   - queryAnalysis: The query analysis
//    ///   - maxConcurrent: Maximum number of concurrent evaluations
//    /// - Returns: Array of link evaluations
//    public func evaluateLinks(
//        _ links: [Crawler.Link],
//        queryAnalysis: Scouter.QueryAnalysis,
//        maxConcurrent: Int = 5
//    ) async throws -> [LinkEvaluation] {
//        var evaluations: [LinkEvaluation] = []
//        
//        // Process links in chunks to limit concurrency
//        for chunk in links.chunked(into: maxConcurrent) {
//            try await withThrowingTaskGroup(of: LinkEvaluation.self) { group in
//                for link in chunk {
//                    group.addTask {
//                        try await self.evaluate(link: link, queryAnalysis: queryAnalysis)
//                    }
//                }
//                
//                for try await evaluation in group {
//                    evaluations.append(evaluation)
//                }
//            }
//        }
//        
//        // Sort by score in descending order
//        return evaluations.sorted { $0.score > $1.score }
//    }
//}

// MARK: - Batch Evaluation Extension
extension LinkEvaluator {
    /// Evaluates multiple links serially
    /// - Parameters:
    ///   - links: Array of links to evaluate
    ///   - queryAnalysis: The query analysis
    /// - Returns: Array of link evaluations sorted by score
    public func evaluateLinks(
        _ links: [Crawler.Link],
        queryAnalysis: Scouter.QueryAnalysis
    ) async throws -> [LinkEvaluation] {
        var evaluations: [LinkEvaluation] = []
        
        // Process links serially
        for link in links {
            let evaluation = try await evaluate(link: link, queryAnalysis: queryAnalysis)
            evaluations.append(evaluation)
        }
        
        // Sort by score in descending order
        return evaluations.sorted { $0.score > $1.score }
    }
}

// MARK: - Array Extension for Chunking
private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
