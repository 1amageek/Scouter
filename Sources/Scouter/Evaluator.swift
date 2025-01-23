//
//  Evaluator.swift
//  Scouter
//
//  Created by Norikazu Muramoto on 2025/01/22.
//

import Foundation
import OllamaKit
import Remark

public actor Evaluator {
    
    struct EvaluatedResult: Codable {
        let links: [TargetLink]
    }
    
    private let model: String
    private let ollamaKit: OllamaKit
    
    public init(model: String = "llama3.2:latest") {
        self.model = model
        self.ollamaKit = OllamaKit()
    }
    
    public func evaluateTargets(targets: [URL: [String]], query: String) async throws -> [TargetLink] {
        var response = ""
        let data = OKChatRequestData(
            model: model,
            messages: [
                .system(systemPrompt),
                .user(generatePrompt(targets: targets, query: query))
            ],
            format: .object(
                description: "Target priorities",
                properties: ["links": .array(
                    description: "Evaluated links",
                    items: .object(properties: [
                        "url": .string(description: "Link URL"),
                        "texts": .array(description: "Link texts", items: .string(description: "Text content")),
                        "priority": .integer(description: "Rating between 1-5")
                    ], required: ["url", "texts", "priority"])
                )],
                required: ["links"]
            )
        )
        
        for try await chunk in ollamaKit.chat(data: data) {
            if let content = chunk.message?.content {
                response += content
            }
        }

        let jsonData = response.data(using: .utf8)!
        let result = try JSONDecoder().decode(EvaluatedResult.self, from: jsonData)
        return result.links
    }
    
    public func evaluateContent(content: String, query: String) async throws -> Priority {
        var response = ""
        let data = OKChatRequestData(
            model: model,
            messages: [
                .system(systemPrompt),
                .user(generateContentPrompt(content: content, query: query))
            ],
            format: .object(
                description: "Content priority",
                properties: ["rating": .integer(description: "Rating between 1-5")],
                required: ["rating"]
            )
        )
        
        for try await chunk in ollamaKit.chat(data: data) {
            if let content = chunk.message?.content {
                response += content
            }
        }
        
        if let rating = Int(response.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return Priority(rawValue: rating) ?? .low
        }
        return .low
    }
    
    private let systemPrompt = """
        You are a web content evaluator focused on identifying and prioritizing relevant information based on user queries. Follow these steps:
        
        1. Understand the query: Determine the user's intent and the type of information they seek.
        2. Evaluate each link: Check relevance, credibility, and whether the content directly addresses the query.
        3. Assign a priority: Rate each link from 1 (low relevance) to 5 (high relevance) based on its value.
        """
    
    private func generatePrompt(targets: [URL: [String]], query: String) -> String {
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
    
    private func generateContentPrompt(content: String, query: String) -> String {
        """
        Search Query: \(query)
        Content to evaluate: \(content.prefix(1000))
        
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

enum EvaluatorError: Error {
    case invalidResponse
}
