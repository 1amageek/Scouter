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
import Unknown

public struct Scouter: Sendable {
    
    public struct Result: Sendable {
        public let query: Scouter.Query
        public let visitedPages: [VisitedPage]
        public let relevantPages: [VisitedPage]
        public let searchDuration: TimeInterval
        
        public init(
            query: Scouter.Query,
            visitedPages: [VisitedPage],
            relevantPages: [VisitedPage],
            searchDuration: TimeInterval
        ) {
            self.query = query
            self.visitedPages = visitedPages
            self.relevantPages = relevantPages
            self.searchDuration = searchDuration
        }
    }
    
    /// Domain control configuration for the crawler
    public struct DomainControl: Sendable {
        /// Domains to exclude from relevancy counting
        /// These pages will be crawled but not counted towards minRelevantPages
        public let excludeFromRelevant: Set<String>
        
        /// Domains to completely skip during crawling
        /// These pages will not be crawled at all
        public let excludeFromCrawling: Set<String>
        
        /// Domains to skip during link evaluation
        /// Links from these domains will not be evaluated for relevancy
        public let excludeFromEvaluation: Set<String>
        
        public init(
            excludeFromRelevant: Set<String> = ["google.com", "google.co.jp"],
            excludeFromCrawling: Set<String> = [],
            excludeFromEvaluation: Set<String> = ["facebook.com", "instagram.com"]
        ) {
            self.excludeFromRelevant = excludeFromRelevant
            self.excludeFromCrawling = excludeFromCrawling
            self.excludeFromEvaluation = excludeFromEvaluation
        }
    }
    
    /// Errors that can occur during Options initialization
    public enum OptionsError: Error, CustomStringConvertible {
        /// Thrown when minimumLinkScore is greater than or equal to relevancyThreshold
        case invalidThresholds(minimumLinkScore: Float, relevancyThreshold: Float)
        
        public var description: String {
            switch self {
            case .invalidThresholds(let min, let relevancy):
                return "minimumLinkScore (\(min)) must be lower than relevancyThreshold (\(relevancy))"
            }
        }
    }
    
    /// Configuration options for the Scouter web crawler.
    ///
    /// Use this structure to configure the behavior of the Scouter web crawler,
    /// including model selection, crawling limits, and relevancy thresholds.
    ///
    /// Example usage:
    /// ```swift
    /// let options = Scouter.Options(
    ///     maxPages: 50,
    ///     minRelevantPages: 3,
    ///     relevancyThreshold: 0.5
    /// )
    /// let result = try await Scouter.search(prompt: query, url: url, options: options)
    /// ```
    public struct Options: Sendable {
        /// Domain control settings
        public let domainControl: DomainControl
        
        /// The model identifier for embeddings and AI-based analysis.
        public let model: String
        
        /// Maximum number of pages to visit during crawling.
        public let maxPages: Int
        
        /// Minimum number of relevant pages required to consider the search complete.
        public let minRelevantPages: Int
        
        /// Threshold for determining page relevancy after visiting (0.0 to 1.0).
        ///
        /// Pages with similarity scores above this threshold are considered relevant.
        /// This is used for the final determination of page relevancy after content analysis.
        public let relevancyThreshold: Float
        
        /// Minimum threshold for link evaluation (0.0 to 1.0).
        ///
        /// Links with evaluation scores below this threshold will be filtered out
        /// before visiting. This should be lower than relevancyThreshold as it's
        /// just an initial filter to remove clearly irrelevant pages.
        public let minimumLinkScore: Float
        
        /// Maximum number of links to keep in evaluation queue.
        public let linkEvaluationLimit: Int
        
        /// Number of links to evaluate in each batch.
        public let evaluateLinksChunkSize: Int
        
        /// Maximum number of retry attempts for failed operations.
        public let maxRetries: Int
        
        /// Timeout duration for network operations in seconds.
        public let timeout: TimeInterval
        
        public init(
            model: String = "llama3.2:latest",
            maxPages: Int = 100,
            minRelevantPages: Int = 8,
            relevancyThreshold: Float = 0.4,
            minimumLinkScore: Float = 0.53,
            linkEvaluationLimit: Int = 400,
            evaluateLinksChunkSize: Int = 20,
            maxRetries: Int = 3,
            timeout: TimeInterval = 30,
            domainControl: DomainControl = .init()
        ) {
            self.model = model
            self.maxPages = maxPages
            self.minRelevantPages = minRelevantPages
            self.relevancyThreshold = relevancyThreshold
            self.minimumLinkScore = minimumLinkScore
            self.linkEvaluationLimit = linkEvaluationLimit
            self.evaluateLinksChunkSize = evaluateLinksChunkSize
            self.maxRetries = maxRetries
            self.timeout = timeout
            self.domainControl = domainControl
        }
        
        public static func `default`() -> Self {
            Self()
        }
    }
    
    public static func search(
        prompt: String,
        url: URL,
        options: Options = .default(),
        logger: Logger? = nil
    ) async throws -> Result? {
        let startTime = DispatchTime.now()
        let aspectAnalyzer = AspectAnalyzer(
            model: options.model,
            logger: logger
        )
        let understanding = try await Unknown(prompt).comprehend()
        
        let prompt = """
            \(prompt)
            
            context: \(understanding.definition)
            """

        let keywordAnalysis = try await aspectAnalyzer.extractKeywords(prompt)
        let keywords = keywordAnalysis.keywords
        print("[Query]:", prompt)
        print("[Keywords]:", keywords.map(\.description).joined(separator: ","))
        let url = URL(
            string: "https://www.google.com/search?q=\(keywords.joined(separator: " "))"
        )!
        print("[URL]:", url)
        let embedding = try await VectorSimilarity.getEmbedding(
            for: prompt,
            model: options.model
        )
        let query = Query(prompt: prompt, embedding: embedding)
        let queryAnalysis = try await query.analyze(model: options.model)
        print(queryAnalysis)
        // Create crawler and delegate
        let crawler = Crawler()
        let delegate = ScouterCrawlerDelegate(
            queryAnalysis: queryAnalysis,
            options: options,
            logger: logger
        )
        
        await crawler.setDelegate(delegate)
        await crawler.start(url: url)
        
        // Generate result
        let visitedPages = await delegate.getVisitedPages()
        let relevantPages = visitedPages.filter { $0.isRelevant }
        let duration = Double(DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000_000
        return Result(
            query: query,
            visitedPages: visitedPages,
            relevantPages: relevantPages,
            searchDuration: duration
        )
    }
    
    private static func encodeGoogleSearchQuery(_ query: String) throws -> String {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw URLError(.badURL)
        }
        return encoded
    }
    
    private static func encodeGoogleSearch(_ keywords: [String]) throws -> String {
        guard let encoded = keywords
            .joined(separator: " ")
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw URLError(.badURL)
        }
        return encoded
    }
}

extension Scouter.Result: CustomStringConvertible {
    public var description: String {
        let separator = String(repeating: "=", count: 80)
        let shortSeparator = String(repeating: "-", count: 40)
        
        var output = [
            separator,
            "🔍 Search Results",
            separator,
            "",
            "📝 Query:",
            query.prompt,
            "",
            "⏱️ Search Duration: \(String(format: "%.2f seconds", searchDuration))",
            "",
            "📊 Statistics:",
            "- Total Pages Visited: \(visitedPages.count)",
            "- Relevant Pages Found: \(relevantPages.count)",
            "",
            "",
            "📚 Relevant Sources:",
            shortSeparator
        ]
        
        // Add relevant pages with their similarity scores
        for (index, page) in relevantPages.enumerated() {
            output.append("""
                [\(index + 1)] \(page.url.absoluteString)
                    Similarity: \(String(format: "%.2f%%", page.score * 100))
                    Title: \(page.title)
                """)
        }
        
        output.append(separator)
        
        return output.joined(separator: "\n")
    }
}
