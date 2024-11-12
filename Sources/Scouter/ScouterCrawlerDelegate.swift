//
//  ScouterCrawlerDelegate.swift
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
import SwiftRetry

public actor ScouterCrawlerDelegate: CrawlerDelegate {
    // MARK: - Properties
    
    private let queryAnalysis: Scouter.QueryAnalysis
    private let options: Scouter.Options
    private let logger: Logger?
    private var pagesToVisit: Set<PageToVisit> = []
    private var evaluatedLinks: Set<EvaluatedLink> = []
    private var visitedPages: [VisitedPage] = []
    private let ollamaKit: OllamaKit
    private let linkEvaluator: LinkEvaluator
    private let pageEvaluator: PageEvaluator
    
    // MARK: - Initialization
    
    /// Initializes a new ScouterCrawlerDelegate instance.
    /// - Parameters:
    ///   - queryAnalysis: Analysis of the search query
    ///   - options: Configuration options for the crawler
    ///   - logger: Optional logger for debug information
    init(
        queryAnalysis: Scouter.QueryAnalysis,
        options: Scouter.Options,
        logger: Logger?
    ) {
        self.queryAnalysis = queryAnalysis
        self.options = options
        self.logger = logger
        self.ollamaKit = OllamaKit()
        self.linkEvaluator = LinkEvaluator(model: options.model)
        self.pageEvaluator = PageEvaluator(model: options.model)
    }
    
    // MARK: - Crawler State
    
    /// Determines if the crawling process is complete based on the number of relevant pages found.
    private var isCompleted: Bool {
        let relevantPageCount = visitedPages.filter { page in
            page.isRelevant && !shouldExcludeFromRelevant(page.url)
        }.count
        return relevantPageCount >= options.minRelevantPages
    }
    
    /// Determines if more links should be evaluated based on the current queue size.
    private var shouldEvaluateLinks: Bool {
        pagesToVisit.count < options.linkEvaluationLimit
    }
    
    // MARK: - Public Interface
    
    public func getVisitedPages() -> [VisitedPage] {
        // Return all pages, but mark excluded domains as not relevant
        return visitedPages.map { page in
            if shouldExcludeFromRelevant(page.url) {
                // Create a new page with isRelevant set to false for excluded domains
                return VisitedPage(
                    url: page.url,
                    title: page.title,
                    content: page.content,
                    embedding: page.embedding,
                    score: page.score,
                    summary: page.summary,
                    isRelevant: false,
                    metadata: page.metadata
                )
            }
            return page
        }
    }
    
    // MARK: - CrawlerDelegate
    
    public func crawler(_ crawler: Crawler, shouldVisitUrl url: URL) -> Crawler.Decision {
        
        if shouldExcludeFromCrawling(url) {
            logger?.debug("ScouterCrawlerDelegate: Skipping excluded domain", metadata: [
                "source": .string("ScouterCrawlerDelegate.shouldVisitUrl"),
                "url": .string(url.absoluteString)
            ])
            return .skip(.businessLogic("Domain excluded from crawling"))
        }
        
        guard url.scheme?.hasPrefix("http") == true else {
            logger?.debug("ScouterCrawlerDelegate: Skipping non-HTTP URL", metadata: [
                "source": .string("ScouterCrawlerDelegate.shouldVisitUrl"),
                "url": .string(url.absoluteString)
            ])
            return .skip(.invalidURL)
        }
        
        let skipExtensions = [".pdf", ".zip", ".jpg", ".png", ".gif", ".mp4", ".mp3"]
        if skipExtensions.contains(where: { url.lastPathComponent.lowercased().hasSuffix($0) }) {
            logger?.debug("ScouterCrawlerDelegate: Skipping unsupported file type", metadata: [
                "source": .string("ScouterCrawlerDelegate.shouldVisitUrl"),
                "url": .string(url.absoluteString),
                "fileType": .string(url.pathExtension)
            ])
            return .skip(.unsupportedFileType)
        }
        
        if visitedPages.contains(where: { $0.url == url }) {
            logger?.debug("ScouterCrawlerDelegate: Skipping already visited URL", metadata: [
                "source": .string("ScouterCrawlerDelegate.shouldVisitUrl"),
                "url": .string(url.absoluteString)
            ])
            return .skip(.businessLogic("Already visited"))
        }
        
        return .visit
    }

    public func crawler(_ crawler: Crawler) async -> URL? {
        guard visitedPages.count < options.maxPages else {
            logger?.info("ScouterCrawlerDelegate: Reached maximum pages limit", metadata: [
                "source": .string("ScouterCrawlerDelegate.crawler"),
                "maxPages": .string("\(options.maxPages)"),
                "visitedPages": .string("\(visitedPages.count)")
            ])
            return nil
        }
        
        if isCompleted {
            return nil
        }
        
        pagesToVisit
            .filter { page in
                !visitedPages.contains(where: { $0.url == page.url })
            }
            .sorted(by: { $0.score > $1.score })
            .prefix(8)
            .forEach { pageToVisit in
                print(
                    "[PageToVisit][\(String(format: "%.4f", pageToVisit.score))]",
                    (pageToVisit.title ?? "").prefix(40),
                    pageToVisit.url.absoluteString.prefix(60)
                )
            }
        
        // Get highest scoring unvisited page
        return pagesToVisit
            .filter { page in
                !visitedPages.contains(where: { $0.url == page.url })
            }
            .max(by: { $0.score < $1.score })?
            .url
    }
    
    public func crawler(_ crawler: Crawler, willVisitUrl url: URL) {
        // Nothing to do
    }
    
    public func crawler(_ crawler: Crawler, didFetchContent content: String, at url: URL) async {
        do {
            // Parse content using Remark
            let remark = try Remark(content)
            
            // Create page metadata
            let metadata = PageMetadata(
                description: remark.description,
                keywords: [],
                ogData: remark.ogData,
                lastModified: nil,
                contentHash: String(content.hash)
            )
            
            // Evaluate page content using PageEvaluator
            let evaluation: PageEvaluator.PageEvaluation = try await pageEvaluator.evaluate(
                content: remark.body,
                metadata: metadata,
                queryAnalysis: queryAnalysis
            )
            
            print("[Eval][\(String(format: "%.2f", evaluation.score))]", remark.title, url)
            
            // Get content embedding for storage
            let embedding = try await VectorSimilarity.getEmbedding(
                for: remark.body,
                model: options.model
            )
            
            // Create summary of evaluation results
            let summary = """
            Score: \(String(format: "%.2f", evaluation.score))
            Similarity: \(String(format: "%.2f", evaluation.contentSimilarity))
            Keywords: \(evaluation.matchedKeywords.joined(separator: ", "))
            """
            
            let isRelevant = evaluation.score >= options.relevancyThreshold
            // Create and store visited page with evaluation results
            let visitedPage = VisitedPage(
                url: url,
                title: remark.title,
                content: remark.body,
                embedding: embedding,
                score: evaluation.score,
                summary: summary,
                isRelevant: isRelevant,
                metadata: metadata
            )
            
            visitedPages.append(visitedPage)
            
            // Remove from pending visits if present
            if let pageToVisit = pagesToVisit.first(where: { $0.url == url }) {
                pagesToVisit.remove(pageToVisit)
            }
            
            // Log visited pages with enhanced information
            visitedPages.forEach { page in
                print(
                    "[VisitedPage][\(String(format: "%.4f", page.score))]",
                    "[\(page.isRelevant ? "Relevant" : "Not Relevant")]",
                    page.title.prefix(40),
                    page.url.absoluteString.prefix(60)
                )
            }
            
            // Log detailed evaluation results
            logger?.info("Page evaluation completed", metadata: [
                "url": .string(url.absoluteString),
                "title": .string(remark.title),
                "score": .string(String(format: "%.2f", evaluation.score))
            ])
            
        } catch {
            logger?.error("Error processing content", metadata: [
                "source": .string("ScouterCrawlerDelegate.didFetchContent"),
                "url": .string(url.absoluteString),
                "error": .string(error.localizedDescription)
            ])
        }
    }
    
    public func crawler(_ crawler: Crawler, didFindLinks links: Set<Crawler.Link>, at url: URL) async {
        guard shouldEvaluateLinks else { return }
        
        do {
            // Filter out excluded and already evaluated links
            let filteredLinks = links.filter { link in
                let processedURL = processGoogleRedirect(url: link.url)
                return !shouldExcludeFromEvaluation(processedURL) &&
                !evaluatedLinks.contains { $0.url == processedURL }
            }.map { link in
                // Create new Link with processed URL
                let processedURL = processGoogleRedirect(url: link.url)
                return Crawler.Link(url: processedURL, title: link.title)
            }
            
            guard !filteredLinks.isEmpty else { return }
            
            // Evaluate filtered links
            let evaluations = try await linkEvaluator.evaluateLinks(
                Array(filteredLinks),
                queryAnalysis: queryAnalysis
            )
            
            for evaluation in evaluations {
                // Create evaluated link record
                let evaluatedLink = EvaluatedLink(
                    url: evaluation.link.url,
                    title: evaluation.link.title,
                    querySimilarity: evaluation.querySimilarity,
                    templateSimilarity: evaluation.templateSimilarity,
                    matchedKeywords: evaluation.matchedKeywords,
                    foundAt: url,
                    evaluatedAt: Date()
                )
                
                evaluatedLinks.insert(evaluatedLink)
                
                print(
                    "[Link][\(String(format: "%.4f", evaluation.score))]",
                    evaluation.link.title.prefix(40),
                    evaluation.link.url.absoluteString.prefix(60)
                )
                
                // Filter out clearly irrelevant pages using minimumLinkScore
                if evaluation.score >= options.minimumLinkScore {
                    let pageToVisit = PageToVisit(
                        url: evaluation.link.url,
                        title: evaluation.link.title,
                        visitCount: 0,
                        score: evaluation.score
                    )
                    pagesToVisit.insert(pageToVisit)
                    
                    logger?.debug("Adding page to visit queue", metadata: [
                        "url": .string(evaluation.link.url.absoluteString),
                        "score": .string(String(format: "%.3f", evaluation.score))
                    ])
                } else {
                    logger?.debug("Filtering out low-scoring link", metadata: [
                        "url": .string(evaluation.link.url.absoluteString),
                        "score": .string(String(format: "%.3f", evaluation.score)),
                        "threshold": .string(String(format: "%.3f", options.minimumLinkScore))
                    ])
                }
            }
        } catch {
            logger?.error("Error evaluating links", metadata: [
                "source": .string("ScouterCrawlerDelegate.didFindLinks"),
                "url": .string(url.absoluteString),
                "error": .string(error.localizedDescription)
            ])
        }
    }
    
    private func processGoogleRedirect(url: URL) -> URL {
        guard let host = url.host?.lowercased(),
              host.contains("google"),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            return url
        }
        
        if url.path == "/url",
           let qValue = components.queryItems?.first(where: { $0.name == "q" })?.value,
           let redirectURL = URL(string: qValue) {
            return redirectURL
        }
        
        if url.path == "/search" {
            return url
        }
        
        return url
    }
    
    public func crawler(_ crawler: Crawler, didVisit url: URL) async {
        // Update visit count or remove from pagesToVisit if necessary
        if let pageToVisit = pagesToVisit.first(where: { $0.url == url }) {
            pagesToVisit.remove(pageToVisit)
            let updatedPage = PageToVisit(
                url: pageToVisit.url,
                title: pageToVisit.title,
                visitCount: pageToVisit.visitCount + 1,
                score: pageToVisit.score)
            pagesToVisit.insert(updatedPage)
            
            logger?.debug("ScouterCrawlerDelegate: Updated visit count", metadata: [
                "source": .string("ScouterCrawlerDelegate.didVisit"),
                "url": .string(url.absoluteString),
                "visitCount": .string("\(updatedPage.visitCount)")
            ])
        }
    }
    
    public func crawler(_ crawler: Crawler, didSkip url: URL, reason: Crawler.SkipReason) async {
        // Remove skipped URL from pagesToVisit if present
        if let pageToVisit = pagesToVisit.first(where: { $0.url == url }) {
            pagesToVisit.remove(pageToVisit)
        }
    }
}

extension ScouterCrawlerDelegate {
    // MARK: - Domain Control Helpers
    
    /// Checks if a domain should be excluded from relevancy counting
    private func shouldExcludeFromRelevant(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return true }
        return options.domainControl.excludeFromRelevant.contains { domain in
            host == domain || host.hasSuffix("." + domain)
        }
    }
    
    /// Checks if a domain should be excluded from crawling
    private func shouldExcludeFromCrawling(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return true }
        return options.domainControl.excludeFromCrawling.contains { domain in
            host == domain || host.hasSuffix("." + domain)
        }
    }
    
    /// Checks if a domain should be excluded from link evaluation
    private func shouldExcludeFromEvaluation(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return true }
        return options.domainControl.excludeFromEvaluation.contains { domain in
            host == domain || host.hasSuffix("." + domain)
        }
    }
}

extension ScouterCrawlerDelegate {
    /// Generates a comprehensive answer from collected pages
    public func crawlerDidFinish(_ crawler: Crawler) async {
        visitedPages.forEach { page in
            print("[Page][\(String(format: "%.4f", page.score))]")
            print("title:", page.title)
            print("content:", page.content.prefix(200))
        }
    }
}

extension ScouterCrawlerDelegate {
    /// Represents a link that has been evaluated for crawling
    private struct EvaluatedLink: Hashable, Sendable {
        let url: URL
        let title: String
        let querySimilarity: Float
        let templateSimilarity: Float
        let matchedKeywords: Set<String>
        let foundAt: URL
        let evaluatedAt: Date
        
        // Hashable implementation based on URL only
        func hash(into hasher: inout Hasher) {
            hasher.combine(url)
        }
        
        // Equality based on URL only
        static func == (lhs: EvaluatedLink, rhs: EvaluatedLink) -> Bool {
            return lhs.url == rhs.url
        }
    }
}
