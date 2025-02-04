import Foundation
import SwiftSoup
import OllamaKit
import Remark
import AspectAnalyzer
import Logging

public enum TerminationReason: String, Sendable {
    case maxPagesReached = "Reached maximum number of crawled pages"
    case lowPriorityStreakExceeded = "Too many consecutive low priority pages"
    case completed = "Successfully completed crawling"
}

public struct Scouter: Sendable {
    
    private static func fetchGoogleSearchResults(
        _ url: URL,
        logger: Logger?
    ) async throws -> [URL] {
        logger?.info("Fetching Google search results", metadata: ["url": .string(url.absoluteString)])
        
        let remark = try await Remark.fetch(from: url, method: .interactive)
        let div = try SwiftSoup.parse(remark.html).select("div#rcnt")
        let searchContent = try Remark(try div.html())
        
        let links = try searchContent.extractLinks()
            .compactMap { link -> URL? in
                guard let url = URL(string: link.url) else { return nil }
                return processGoogleRedirect(url)
            }
            .filter { url in
                !isExcludedDomain(url)
            }
        logger?.info("Found search result links", metadata: ["count": .string("\(links.count)")])
        return links
    }
    
    private static func processGoogleRedirect(_ url: URL) -> URL {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              components.path == "/url",
              let destination = components.queryItems?.first(where: { $0.name == "q" })?.value,
              let destUrl = URL(string: destination) else {
            return url
        }
        return destUrl
    }
    
    private static func isExcludedDomain(_ url: URL) -> Bool {
        let excludedDomains = ["google.com", "google.co.jp", "facebook.com", "instagram.com", "youtube.com", "pinterest.com", "twitter.com", "x.com", "line.me", "weathernews.com", "weather.cnn.co.jp", "weathernews.jp", "veltra.com"]
        guard let host = url.host?.lowercased() else { return true }
        return excludedDomains.contains { domain in
            host == domain || host.hasSuffix("." + domain)
        }
    }
    
    private static func encodeGoogleSearchQuery(_ query: String) throws -> String {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw URLError(.badURL)
        }
        return encoded
    }
}

extension Scouter {
    
    public struct Result: Sendable {
        public let query: String
        public let pages: [Page]
        public let searchDuration: TimeInterval
        public let terminationReason: TerminationReason
        
        public init(
            query: String,
            pages: [Page],
            searchDuration: TimeInterval,
            terminationReason: TerminationReason
        ) {
            self.query = query
            self.pages = pages
            self.searchDuration = searchDuration
            self.terminationReason = terminationReason
        }
    }
    
    public struct Options: Sendable {
        public let evaluatorModel: Model
        public let summarizerModel: Model
        public let maxDepth: Int
        public let maxPages: Int
        public let maxCrawledPages: Int
        public let maxLowPriorityStreak: Int
        public let minRelevantPages: Int
        public let maxRetries: Int
        public let minHighScoreLinks: Int
        public let highScoreThreshold: Float
        public let relevancyThreshold: Float
        public let minimumLinkScore: Float
        public let maxConcurrentCrawls: Int
        public let evaluateChunkSize: Int
        public let timeout: TimeInterval
        public let domainControl: DomainControl
        
        public init(
            evaluatorModel: Model = .defaultModel,
            summarizerModel: Model = .defaultModel,
            maxDepth: Int = 5,
            maxPages: Int = 45,
            maxCrawledPages: Int = 10,
            maxLowPriorityStreak: Int = 2,
            minRelevantPages: Int = 8,
            maxRetries: Int = 3,
            minHighScoreLinks: Int = 10,
            highScoreThreshold: Float = 3.1,
            relevancyThreshold: Float = 0.4,
            minimumLinkScore: Float = 0.3,
            maxConcurrentCrawls: Int = 5,
            evaluateChunkSize: Int = 20,
            timeout: TimeInterval = 30,
            domainControl: DomainControl = .init()
        ) {
            self.evaluatorModel = evaluatorModel
            self.summarizerModel = summarizerModel
            self.maxDepth = maxDepth
            self.maxPages = maxPages
            self.maxCrawledPages = maxCrawledPages
            self.maxLowPriorityStreak = maxLowPriorityStreak
            self.minRelevantPages = minRelevantPages
            self.maxRetries = maxRetries
            self.minHighScoreLinks = minHighScoreLinks
            self.highScoreThreshold = highScoreThreshold
            self.relevancyThreshold = relevancyThreshold
            self.minimumLinkScore = minimumLinkScore
            self.maxConcurrentCrawls = maxConcurrentCrawls
            self.evaluateChunkSize = evaluateChunkSize
            self.timeout = timeout
            self.domainControl = domainControl
        }
        
        public static func `default`() -> Self {
            Self()
        }
    }
    
    public enum OptionsError: Error, CustomStringConvertible {
        case invalidThresholds(minimumLinkScore: Float, relevancyThreshold: Float)
        
        public var description: String {
            switch self {
            case .invalidThresholds(let min, let relevancy):
                return "minimumLinkScore (\(min)) must be lower than relevancyThreshold (\(relevancy))"
            }
        }
    }
}

extension Scouter {
    
    public static func search(
        prompt: String,
        options: Options = .default(),
        logger: Logger? = nil
    ) async throws -> Result {
        print("Prompt: \(prompt)")
        
        let startTime = Date()
        let encodedQuery = try encodeGoogleSearchQuery(prompt)
        let searchUrl = URL(string: "https://www.google.com/search?q=\(encodedQuery)")!
        
        let searchResults = try await fetchGoogleSearchResults(searchUrl, logger: logger)
        
        let evaluator = options.evaluatorModel.createEvaluator()
        
        let crawler = Crawler(
            query: prompt,
            options: options,
            evaluator: evaluator,
            logger: logger
        )
        
        for url in searchResults {
            try await crawler.crawl(startUrl: url)
        }
        
        let (pages, terminationReason) = await crawler.getCrawlerState()
        let duration = Date().timeIntervalSince(startTime)
        
        return Result(
            query: prompt,
            pages: pages,
            searchDuration: duration,
            terminationReason: terminationReason
        )
    }
    
    public static func summarize(
        result: Result,
        options: Options,
        logger: Logger? = nil
    ) async throws -> Summary {
        logger?.info("Starting summarization")
        
        let summarizer = options.summarizerModel.createSummarizer()
        let summary = try await summarizer.summarize(pages: result.pages, query: result.query)
        
        logger?.info("Completed summarization")
        return summary
    }
}

extension Scouter.Result: CustomStringConvertible {
    public var description: String {
        let lines = [
            "Search Summary",
            "Query: \(query)",
            "Duration: \(String(format: "%.2f", searchDuration))s",
            "Pages Found: \(pages.count)",
            terminationReason.rawValue,
            "\nResults:",
            pages.map { "- [\($0.priority.rawValue)] \($0.url.absoluteString)" }.joined(separator: "\n")
        ]
        return lines.joined(separator: "\n")
    }
}
