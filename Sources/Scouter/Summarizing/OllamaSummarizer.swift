//
//  OllamaSummarizer.swift
//  Scouter
//
//  Created by Norikazu Muramoto on 2025/01/27.
//

import Foundation
import OllamaKit

public actor OllamaSummarizer: Summarizing {
    private let model: String
    private let ollamaKit: OllamaKit
    
    public init(model: String = "llama3.2:latest") {
        self.model = model
        self.ollamaKit = OllamaKit()
    }
    
    public func summarize(pages: [Page], query: String) async throws -> Summary {
        let data = OKChatRequestData(
            model: model,
            messages: [
                .system(summarySystemPrompt),
                .user(generateSummaryPrompt(pages: pages, query: query))
            ],
            format: .object(
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
        
        var response = ""
        for try await chunk in ollamaKit.chat(data: data) {
            if let content = chunk.message?.content {
                response += content
            }
        }
        
        let jsonData = response.data(using: .utf8)!
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
