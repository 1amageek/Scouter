//
//  Evaluating.swift
//  Scouter
//
//  Created by Norikazu Muramoto on 2025/01/24.
//

import Foundation

public protocol Evaluating: Sendable {
    func evaluateTargets(targets: [URL: [String]], query: String) async throws -> [TargetLink]
    func evaluateContent(content: String, query: String) async throws -> Priority
}

enum EvaluatorError: Error {
    case invalidResponse
}

struct LinkEvaluatedResult: Codable {
    let links: [TargetLink]
}

struct PageEvaluatedResult: Codable {
    let priority: Priority
}

extension Evaluating {
    
    var linkEvaluationPrompt: String {
        """
        You are a link evaluator that analyzes URLs and their associated texts to determine their potential relevance to user queries.
        Focus on:
        1. URL structure and domain credibility
        2. Link text relevance to the query
        3. Likelihood of containing query-specific information
        """
    }
    
    var contentEvaluationPrompt: String {
        """
        You are a content evaluator that analyzes webpage content to determine its relevance to user queries.
        Focus on:
        1. Direct answers to the query
        2. Content depth and comprehensiveness
        3. Information accuracy and specificity
        """
    }
    
    func generatePrompt(targets: [URL: [String]], query: String) -> String {
        """
        Search Query: \(query)
        
        Goal: Evaluate which of these linked pages are most likely to contain relevant information about the query.
        For efficient web navigation and information gathering, rate each link's potential relevance:
        
        1 = Unlikely to contain query-related info
        2 = May have some related background info
        3 = Likely contains relevant information
        4 = Very likely has important query-specific content
        5 = Appears to directly address the query
        
        Links to evaluate:
        \(targets.enumerated().map { index, target in
            let url = target.key.absoluteString
            let texts = target.value.joined(separator: " | ")
            return "[\(index + 1)] URL: \(url)\nTexts: \(texts)"
        }.joined(separator: "\n\n"))
        
        Respond with JSON matching the provided format.
        """
    }
    
    func generateContentPrompt(content: String, query: String) -> String {
        """
        Search Query: \(query)
        Content to evaluate: \(content.prefix(400))
        
        Evaluate how well this content answers or relates to the search query.
        Rate from 1-5:
        1 = Contains minimal query-relevant information
        2 = Has some background or tangential information
        3 = Contains directly relevant information
        4 = Provides detailed query-specific content
        5 = Comprehensively addresses the query
        """
    }
}
