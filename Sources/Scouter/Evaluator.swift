//
//import Foundation
//import OllamaKit
//import Remark
//
//public actor Evaluator {
//    
//    struct LinkEvaluatedResult: Codable {
//        let links: [TargetLink]
//    }
//    
//    struct PageEvaluatedResult: Codable {
//        let priority: Priority
//    }
//    
//    private let model: String
//    private let ollamaKit: OllamaKit
//    
//    public init(model: String = "llama3.2:latest") {
//        self.model = model
//        self.ollamaKit = OllamaKit()
//    }
//    
//    public func evaluateTargets(targets: [URL: [String]], query: String) async throws -> [TargetLink] {
//        var response = ""
//        let data = OKChatRequestData(
//            model: model,
//            messages: [
//                .system(linkEvaluationPrompt),
//                .user(generatePrompt(targets: targets, query: query))
//            ],
//            format: .object(
//                description: "Target priorities",
//                properties: ["links": .array(
//                    description: "Evaluated links",
//                    items: .object(properties: [
//                        "url": .string(description: "Link URL"),
//                        "texts": .array(description: "Link texts", items: .string(description: "Text content")),
//                        "priority": .integer(description: "Rating between 1-5")
//                    ], required: ["url", "texts", "priority"])
//                )],
//                required: ["links"]
//            )
//        )
//        
//        for try await chunk in ollamaKit.chat(data: data) {
//            if let content = chunk.message?.content {
//                response += content
//            }
//        }
//
//        let jsonData = response.data(using: .utf8)!
//        let result = try JSONDecoder().decode(LinkEvaluatedResult.self, from: jsonData)
//        return result.links
//    }
//    
//    public func evaluateContent(content: String, query: String) async throws -> Priority {
//        var response = ""
//        let data = OKChatRequestData(
//            model: model,
//            messages: [
//                .system(contentEvaluationPrompt),
//                .user(generateContentPrompt(content: content, query: query))
//            ],
//            format: .object(
//                description: "Content priority",
//                properties: ["priority": .integer(description: "Rating between 1-5")],
//                required: ["priority"]
//            )
//        )
//        
//        for try await chunk in ollamaKit.chat(data: data) {
//            if let content = chunk.message?.content {
//                response += content
//            }
//        }
//        
//        let jsonData = response.data(using: .utf8)!
//        let result = try JSONDecoder().decode(PageEvaluatedResult.self, from: jsonData)
//        return result.priority
//    }
//    
//    private let linkEvaluationPrompt = """
//        You are a link evaluator that analyzes URLs and their associated texts to determine their potential relevance to user queries.
//        Focus on:
//        1. URL structure and domain credibility
//        2. Link text relevance to the query
//        3. Likelihood of containing query-specific information
//        """
//    
//    private let contentEvaluationPrompt = """
//        You are a content evaluator that analyzes webpage content to determine its relevance to user queries.
//        Focus on:
//        1. Direct answers to the query
//        2. Content depth and comprehensiveness
//        3. Information accuracy and specificity
//        """
//    
//    private func generatePrompt(targets: [URL: [String]], query: String) -> String {
//        """
//        Search Query: \(query)
//        
//        Goal: Evaluate which of these linked pages are most likely to contain relevant information about the query.
//        For efficient web navigation and information gathering, rate each link's potential relevance:
//        
//        1 = Unlikely to contain query-related info
//        2 = May have some related background info
//        3 = Likely contains relevant information
//        4 = Very likely has important query-specific content
//        5 = Appears to directly address the query
//        
//        Links to evaluate:
//        \(targets.enumerated().map { index, target in
//            let url = target.key.absoluteString
//            let texts = target.value.joined(separator: " | ")
//            return "[\(index + 1)] URL: \(url)\nTexts: \(texts)"
//        }.joined(separator: "\n\n"))
//        
//        Respond with JSON matching the provided format.
//        """
//    }
//    
//    private func generateContentPrompt(content: String, query: String) -> String {
//        """
//        Search Query: \(query)
//        Content to evaluate: \(content.prefix(400))
//        
//        Evaluate how well this content answers or relates to the search query.
//        Rate from 1-5:
//        1 = Contains minimal query-relevant information
//        2 = Has some background or tangential information
//        3 = Contains directly relevant information
//        4 = Provides detailed query-specific content
//        5 = Comprehensively addresses the query
//        """
//    }
//}
