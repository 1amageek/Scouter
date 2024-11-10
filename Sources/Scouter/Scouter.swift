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
        public let maxRetries: Int
        public let timeout: TimeInterval
        
        public init(
            model: String = "llama3.2:latest",
            maxPages: Int = 100,
            similarityThreshold: Float = 0.33,
            maxRetries: Int = 3,
            timeout: TimeInterval = 30
        ) {
            self.model = model
            self.maxPages = maxPages
            self.similarityThreshold = similarityThreshold
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
        let data = OKEmbeddingsRequestData(model: options.model, prompt: prompt)
        let response = try await ollamaKit.embeddings(data: data)
        
        let query = Query(prompt: prompt, embedding: response.embedding!)
        
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
}
