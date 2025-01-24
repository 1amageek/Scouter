//
//  OllamaEvaluator.swift
//  Scouter
//
//  Created by Norikazu Muramoto on 2025/01/24.
//

import Foundation
import OllamaKit
import Remark


public actor OllamaEvaluator: Evaluating {
    private let model: String
    private let ollamaKit: OllamaKit
    
    public init(model: String = "llama3.2:latest") {
        self.model = model
        self.ollamaKit = OllamaKit()
    }
    
    public func evaluateTargets(targets: [URL: [String]], query: String) async throws -> [TargetLink] {
        let data = OKChatRequestData(
            model: model,
            messages: [
                .system(linkEvaluationPrompt),
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
        return try await requestOllama(data: data, responseType: LinkEvaluatedResult.self).links
    }
    
    public func evaluateContent(content: String, query: String) async throws -> Priority {
        let data = OKChatRequestData(
            model: model,
            messages: [
                .system(contentEvaluationPrompt),
                .user(generateContentPrompt(content: content, query: query))
            ],
            format: .object(
                description: "Content priority",
                properties: ["priority": .integer(description: "Rating between 1-5")],
                required: ["priority"]
            )
        )
        return try await requestOllama(data: data, responseType: PageEvaluatedResult.self).priority
    }
    
    private func requestOllama<T: Decodable>(data: OKChatRequestData, responseType: T.Type) async throws -> T {
        var response = ""
        for try await chunk in ollamaKit.chat(data: data) {
            if let content = chunk.message?.content {
                response += content
            }
        }
        
        let jsonData = response.data(using: .utf8)!
        return try JSONDecoder().decode(responseType, from: jsonData)
    }
}
