//
//  OpenAIEvaluator.swift
//  Scouter
//
//  Created by Norikazu Muramoto on 2025/01/24.
//

import Foundation
import LLMChatOpenAI
import JSONSchema

public actor OpenAIEvaluator: Evaluating {
    private let model: String
    private let client: LLMChatOpenAI
    
    public init(model: String = "gpt-4o-mini") {
        self.client = LLMChatOpenAI(apiKey: ProcessInfo.processInfo.environment["OPENAI_API_KEY"]!)
        self.model = model
    }
    
    public func evaluateTargets(targets: [URL: [String]], query: String) async throws -> [TargetLink] {
        let completion = try await requestOpenAI(
            responseType: LinkEvaluatedResult.self,
            messages: [
                ChatMessage(role: .system, content: linkEvaluationPrompt),
                ChatMessage(role: .user, content: generatePrompt(targets: targets, query: query))
            ],
            schema: .object(
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
        return completion.links
    }
    
    public func evaluateContent(content: String, query: String) async throws -> Priority {
        let completion = try await requestOpenAI(
            responseType: PageEvaluatedResult.self,
            messages: [
                ChatMessage(role: .system, content: contentEvaluationPrompt),
                ChatMessage(role: .user, content: generateContentPrompt(content: content, query: query))
            ],
            schema: .object(
                description: "Content priority",
                properties: ["priority": .integer(description: "Rating between 1-5")],
                required: ["priority"]
            )
        )
        return completion.priority
    }
    
    private func requestOpenAI<T: Decodable>(
        responseType: T.Type,
        messages: [ChatMessage],
        schema: JSONSchema
    ) async throws -> T {
        let completion = try await client.send(
            model: model,
            messages: messages,
            options: ChatOptions(
                responseFormat: .init(
                    type: .jsonSchema,
                    jsonSchema: .init(
                        name: "response_schema",
                        schema: schema
                    )
                )
            )
        )
        
        guard let jsonString = completion.choices.first?.message.content,
              let jsonData = jsonString.data(using: .utf8) else {
            throw EvaluatorError.invalidResponse
        }
        
        return try JSONDecoder().decode(responseType, from: jsonData)
    }
}
