//
//  Answer.swift
//  Scouter
//
//  Created by Norikazu Muramoto on 2024/11/11.
//

import Foundation

extension Scouter {
    /// Represents a comprehensive answer to the query
    public struct Answer: Sendable {
        /// Main answer content
        let content: String
        /// Length of the answer
        var length: Int { content.count }
        /// Sources used for the answer
        let sources: [Source]
        /// Confidence score for the answer
        let confidence: Float
        /// Analysis metrics
        let metrics: AnswerMetrics
        
        /// Represents a source used in the answer
        struct Source: Sendable {
            let url: URL
            let title: String
            let relevance: Float
            let snippet: String
        }
        
        /// Metrics about the answer quality
        struct AnswerMetrics: Sendable {
            let coverageScore: Float
            let sourceCount: Int
            let averageSourceRelevance: Float
            let informationDiversity: Float
        }
    }
}
