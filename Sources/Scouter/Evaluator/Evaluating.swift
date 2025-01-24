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
        You are a link evaluator that determines the relevance of URLs and their associated texts to user queries.
        
        Step 1: Understand the user's query:
        - What is the user looking for?
        - What level of detail or specificity might they need?
        
        Step 2: Evaluate links based on:
        1. URL credibility: Is the domain trustworthy, and does the URL suggest relevant content?
        2. Link text relevance: Does the text directly relate to the query?
        3. Query-specific content: Is the link likely to contain detailed, useful information?
        
        Step 3: Adjust for irrelevant links:
        - Lower priority for terms of service, privacy policies, language-switching links, or generic forms.
        - Focus on links that provide clear, query-relevant value.
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
        
        1 = Unlikely to contain query-related info, including:
            - Links to terms of service, privacy policies, or other legal documents.
            - Language-switching links.
            - help pages, or general-purpose resources.
            - Advertising or promotional links.
            - Social media links unrelated to the query.
            - Contact forms, login/sign-up pages, or general templates.
        2 = May have some related background info but is not directly relevant.
        3 = Likely contains relevant information about the query.
        4 = Very likely has important query-specific content that addresses key aspects of the query.
        5 = Appears to directly address the query comprehensively and with high specificity.

        
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
