import Foundation
import SwiftSoup
import OllamaKit
import Remark
import AspectAnalyzer
import Logging
import Unknown
import OpenAI

public enum TerminationReason: String, Sendable {
    case maxPagesReached = "Reached maximum number of crawled pages"
    case lowPriorityStreakExceeded = "Too many consecutive low priority pages"
    case completed = "Successfully completed crawling"
}

public struct Scouter: Sendable {
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
        let crawler = Crawler(
            query: prompt,
            maxConcurrent: options.maxConcurrentCrawls,
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
        let excludedDomains = ["google.com", "google.co.jp", "facebook.com", "instagram.com"]
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
        public let model: String
        public let maxDepth: Int
        public let maxPages: Int
        public let minRelevantPages: Int
        public let maxRetries: Int
        public let relevancyThreshold: Float
        public let minimumLinkScore: Float
        public let maxConcurrentCrawls: Int
        public let evaluateChunkSize: Int
        public let timeout: TimeInterval
        public let domainControl: DomainControl
        
        public init(
            model: String = "llama3.2:latest",
            maxDepth: Int = 5,
            maxPages: Int = 100,
            minRelevantPages: Int = 8,
            maxRetries: Int = 3,
            relevancyThreshold: Float = 0.4,
            minimumLinkScore: Float = 0.3,
            maxConcurrentCrawls: Int = 5,
            evaluateChunkSize: Int = 20,
            timeout: TimeInterval = 30,
            domainControl: DomainControl = .init()
        ) {
            self.model = model
            self.maxDepth = maxDepth
            self.maxPages = maxPages
            self.minRelevantPages = minRelevantPages
            self.maxRetries = maxRetries
            self.relevancyThreshold = relevancyThreshold
            self.minimumLinkScore = minimumLinkScore
            self.maxConcurrentCrawls = maxConcurrentCrawls
            self.evaluateChunkSize = evaluateChunkSize
            self.timeout = timeout
            self.domainControl = domainControl
        }
        
        public static func `default`() -> Self {
            Self(
                model: "llama3.2:latest",
                maxDepth: 2,
                maxPages: 100,
                minRelevantPages: 8,
                maxRetries: 3,
                relevancyThreshold: 0.4,
                minimumLinkScore: 0.3,
                maxConcurrentCrawls: 5,
                evaluateChunkSize: 20,
                timeout: 30
            )
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

