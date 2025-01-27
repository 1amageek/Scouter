//
//  OpenAISummarizer.swift
//  Scouter
//
//  Created by Norikazu Muramoto on 2025/01/27.
//

import Foundation
import LLMChatOpenAI
import JSONSchema

public actor OpenAISummarizer: Summarizing {
    private let model: String
    private let client: LLMChatOpenAI
    
    public init(model: String = "gpt-4o-mini") {
        self.client = LLMChatOpenAI(apiKey: ProcessInfo.processInfo.environment["OPENAI_API_KEY"]!)
        self.model = model
    }
    
    public func summarize(pages: [Page], query: String) async throws -> Summary {
        let completion = try await client.send(
            model: model,
            messages: [
                ChatMessage(role: .system, content: summarySystemPrompt),
                ChatMessage(role: .user, content: generateSummaryPrompt(pages: pages, query: query))
            ],
            options: ChatOptions(
                responseFormat: .init(
                    type: .jsonSchema,
                    jsonSchema: .init(
                        name: "summary_schema",
                        schema: .object(
                            description: "Summary response",
                            properties: [
                                "overview": .string(description: "A comprehensive technical explanation"),
                                "keyPoints": .array(
                                    description: "Detailed technical sections",
                                    items: .string(description: "A detailed technical explanation")
                                ),
                                "sourceURLs": .array(
                                    description: "URLs ordered by relevance",
                                    items: .string(description: "Source URL")
                                )
                            ],
                            required: ["overview", "keyPoints", "sourceURLs"]
                        )
                    )
                )
            )
        )
        
        guard let jsonString = completion.choices.first?.message.content,
              let jsonData = jsonString.data(using: .utf8) else {
            throw SummarizerError.invalidResponse
        }
        
        let decoded = try JSONDecoder().decode(SummaryResponse.self, from: jsonData)
        
        return Summary(
            query: query,
            overview: decoded.overview,
            keyPoints: decoded.keyPoints,
            sourceURLs: decoded.sourceURLs.compactMap(URL.init)
        )
    }
}

private struct SummaryResponse: Codable {
    let overview: String
    let keyPoints: [String]
    let sourceURLs: [String]
}
