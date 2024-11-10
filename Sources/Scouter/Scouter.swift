//
//  Scouter.swift
//  Scouter
//
//  Created by Norikazu Muramoto on 2024/11/10.
//

import Foundation
import Selenops
import SwiftSoup
import OllamaKit
import Remark
import AspectAnalyzer
import Logging

public struct Scouter: Sendable {
    
    public struct Result: Sendable {
        public let query: Scouter.Query
        public let answer: Answer
        public let visitedPages: [VisitedPage]
        public let relevantPages: [VisitedPage]
        public let searchDuration: TimeInterval
        
        public init(
            query: Scouter.Query,
            answer: Scouter.Answer,
            visitedPages: [VisitedPage],
            relevantPages: [VisitedPage],
            searchDuration: TimeInterval
        ) {
            self.query = query
            self.answer = answer
            self.visitedPages = visitedPages
            self.relevantPages = relevantPages
            self.searchDuration = searchDuration
        }
    }
    
    public struct Options: Sendable {
        public let model: String
        public let maxPages: Int
        public let similarityThreshold: Float
        public let evaluateLinksChunkSize: Int
        public let maxRetries: Int
        public let timeout: TimeInterval
        
        public init(
            model: String = "llama3.2:latest",
            maxPages: Int = 100,
            similarityThreshold: Float = 0.152,
            evaluateLinksChunkSize: Int = 20,
            maxRetries: Int = 3,
            timeout: TimeInterval = 30
        ) {
            self.model = model
            self.maxPages = maxPages
            self.similarityThreshold = similarityThreshold
            self.evaluateLinksChunkSize = evaluateLinksChunkSize
            self.maxRetries = maxRetries
            self.timeout = timeout
        }
    }
    
    public struct Query: Identifiable, Sendable {
        public let id: UUID
        public let prompt: String
        public let embedding: [Float]
        
        public init(
            id: UUID = UUID(),
            prompt: String,
            embedding: [Float]
        ) {
            self.id = id
            self.prompt = prompt
            self.embedding = embedding
        }
    }
    
    public static func search(
        prompt: String,
        url: URL,
        options: Options = .init(),
        logger: Logger? = nil
    ) async throws -> Result? {
        let startTime = DispatchTime.now()
        
        // Generate embedding for the prompt
        let ollamaKit = OllamaKit()
        
        // 1. Analyze query using AspectAnalyzer
        let aspectAnalyzer = AspectAnalyzer(
            model: options.model,
            logger: logger
        )
        let analysis = try await aspectAnalyzer.analyzeQuery(prompt)
        
        // 2. Generate ideal answer template
        let idealAnswerTemplate = try await generateIdealAnswerTemplate(
            analysis: analysis,
            ollamaKit: ollamaKit,
            model: options.model
        )
        print("------")
        print(idealAnswerTemplate)
        print("------")
        
        let queryEmbedding = try await VectorSimilarity.getEmbedding(
            for: prompt,
            model: options.model
        )
        
        let idealAnswerEmbedding = try await VectorSimilarity.getEmbedding(
            for: idealAnswerTemplate,
            model: options.model
        )
        
        let query = Query(prompt: prompt, embedding: idealAnswerEmbedding)
        
        // Create crawler and delegate
        let crawler = Crawler()
        let delegate = ScouterCrawlerDelegate(
            query: query,
            options: options,
            logger: logger
        )
        
        await crawler.setDelegate(delegate)
        await crawler.start(url: url)
        
        // Generate result
        let visitedPages = await delegate.getVisitedPages()
        let relevantPages = visitedPages.filter { $0.isRelevant }
        let answer = await delegate.getAnswer()!
        let duration = Double(DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000_000
        
        return Result(
            query: query,
            answer: answer,
            visitedPages: visitedPages,
            relevantPages: relevantPages,
            searchDuration: duration
        )
    }
    
    private static func generateIdealAnswerTemplate(
        analysis: AspectAnalyzer.Analysis,
        ollamaKit: OllamaKit,
        model: String
    ) async throws -> String {
        let prompt = """
        Based on the following aspects of the query, generate an ideal answer template.
        Use [TBD] as a placeholder for specific information that needs to be found.
        
        Query: \(analysis.query)
        
        Critical Aspects:
        \(analysis.criticalAspects.map { "- \($0.description) (Importance: \($0.importance))" }.joined(separator: "\n"))
        
        Required Knowledge Areas:
        \(Set(analysis.aspects.flatMap { $0.requiredKnowledge }).joined(separator: ", "))
        
        Expected Information Types:
        \(Set(analysis.aspects.flatMap { $0.expectedInfoTypes }).joined(separator: ", "))
        
        Generate a structured answer template that covers all critical aspects:
        """
        
        let data = OKChatRequestData(
            model: model,
            messages: [
                OKChatRequestData.Message(role: .system, content: "You are a template generator for web search answers."),
                OKChatRequestData.Message(role: .user, content: prompt)
            ]
        ) { options in
            options.temperature = 0.3
        }
        
        var response = ""
        for try await chunk in ollamaKit.chat(data: data) {
            response += chunk.message?.content ?? ""
        }
        return response
    }
}
