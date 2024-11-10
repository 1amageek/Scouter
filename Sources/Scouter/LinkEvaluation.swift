//
//  LinkEvaluation.swift
//  Scouter
//
//  Created by Norikazu Muramoto on 2024/11/10.
//

import Foundation

/// Represents the evaluation of a link by LLM
public struct LinkEvaluation: Codable, Sendable {
    /// Priority levels for link crawling
    public enum Priority: String, Codable, Comparable, Sendable {
        case critical = "Critical" // Essential content directly answering the query
        case high = "High"         // Strongly related content
        case medium = "Medium"     // Related content
        case low = "Low"           // Tangentially related content
        
        public static func < (lhs: Priority, rhs: Priority) -> Bool {
            return lhs.order < rhs.order
        }
        
        private var order: Int {
            switch self {
            case .critical: return 3
            case .high: return 2
            case .medium: return 1
            case .low: return 0
            }
        }
    }

    
    /// Target URL
    public let url: URL
    
    /// Link title
    public let title: String
    
    /// Crawling priority determined by LLM
    public let priority: Priority
    
    /// Reasoning for the priority assignment
    public let reasoning: String
}

// MARK: - LLM Response Handling
extension LinkEvaluation {
    /// Structure for parsing LLM response
    struct LLMResponse: Codable {
        let evaluations: [EvaluationResponse]
        
        struct EvaluationResponse: Codable {
            let url: String
            let title: String
            let priority: Priority
            let reasoning: String
        }
    }
    
    /// Creates a LinkEvaluation from LLM response
    static func fromLLMResponse(_ response: LLMResponse.EvaluationResponse) -> LinkEvaluation? {
        guard let url = URL(string: response.url) else { return nil }
        
        return LinkEvaluation(
            url: url,
            title: response.title,
            priority: response.priority,
            reasoning: response.reasoning
        )
    }
}
