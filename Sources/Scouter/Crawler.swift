//
//  Crawler.swift
//  Scouter
//
//  Created by Norikazu Muramoto on 2025/01/22.
//

import Foundation
import Remark
import Logging

/// An actor that performs web crawling tasks.
///
/// `Crawler` manages the crawling process by fetching web pages, extracting links,
/// filtering invalid targets, evaluating link relevance, and storing the results.
public actor Crawler {
    private let state: CrawlerState
    private let evaluator: Evaluator
    private let query: String
    private let logger: Logger?
    
    /// Creates a new instance of `Crawler`.
    ///
    /// - Parameters:
    ///   - query: The search query to guide the crawling process.
    ///   - maxConcurrent: The maximum number of concurrent crawls. Defaults to 5.
    ///   - logger: An optional logger for recording crawl events.
    public init(query: String, maxConcurrent: Int = 5, logger: Logger? = nil) {
        self.query = query
        self.state = CrawlerState(maxConcurrentCrawls: maxConcurrent, maxPages: 30)
        self.evaluator = Evaluator()
        self.logger = logger
    }
    
    /// Normalizes a URL by removing unnecessary components and standardizing the format.
    ///
    /// - Parameter url: The URL to normalize.
    /// - Returns: A normalized URL, or `nil` if normalization fails.
    private func normalizeUrl(_ url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return nil }
        components.fragment = nil
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        return components.url
    }
    
    /// Filters out invalid targets from the extracted links.
    ///
    /// - Parameter targets: A dictionary of URLs and their associated anchor texts.
    /// - Returns: A dictionary containing only valid targets.
    func filterInvalidTargets(_ targets: [URL: [String]]) -> [URL: [String]] {
        let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "svg", "mp4", "avi", "mov"]
        
        return targets.reduce(into: [URL: [String]]()) { result, entry in
            let (url, texts) = entry
            
            // Remove duplicate texts
            let uniqueTexts = Array(Set(texts))
            
            // Filter logic
            guard !uniqueTexts.isEmpty else { return }
            let hasOnlyImages = uniqueTexts.allSatisfy { text in
                guard let ext = text.split(separator: ".").last?.lowercased() else { return false }
                return imageExtensions.contains(String(ext))
            }
            if hasOnlyImages { return }
            guard url.host != nil else { return }
            
            result[url] = uniqueTexts
        }
    }
    
    /// Initiates the crawling process from the specified starting URL.
    ///
    /// - Parameter startUrl: The URL to begin crawling from.
    /// - Throws: An error if the crawling process encounters issues.
    public func crawl(startUrl: URL) async throws {
        guard let normalizedUrl = normalizeUrl(startUrl) else {
            logger?.warning("Invalid URL: \(startUrl)")
            return
        }
        
        guard await state.markUrlAsCrawled(normalizedUrl) else {
            logger?.info("URL already crawled: \(normalizedUrl)")
            return
        }
        
        // 終了条件をチェック
        if await state.shouldTerminate() {
            logger?.info("Crawling terminated due to completion conditions")
            return
        }
        
        guard let remark = try? await Remark.fetch(from: normalizedUrl) else {
            logger?.error("Failed to fetch \(normalizedUrl)")
            return
        }
        
        let links = try remark.extractLinks()
        var filteredLinksByUrl: [URL: [String]] = [:]
        for link in links {
            guard let linkUrl = URL(string: link.url), !link.text.isEmpty,
                  let normalizedLinkUrl = normalizeUrl(linkUrl) else { continue }
            filteredLinksByUrl[normalizedLinkUrl, default: []].append(link.text)
        }
        filteredLinksByUrl = filterInvalidTargets(filteredLinksByUrl)
        guard let updatedTargets: [TargetLink] = try? await evaluator.evaluateTargets(targets: filteredLinksByUrl, query: query) else {
            logger?.error("Failed to evaluate targets for \(normalizedUrl)")
            return
        }
        
        for target in updatedTargets {
            await state.addTarget(target)
        }
        
        let page = Page(url: normalizedUrl, remark: remark, crawledAt: Date())
        await state.addPage(page)
        
        let progress = await state.getProgress()
        logger?.info("Crawling Progress: \(progress)")
        
        await withTaskGroup(of: Void.self) { group in
            while let nextTarget = await state.nextTarget() {
                group.addTask {
                    do {
                        try await self.crawl(startUrl: nextTarget.url)
                    } catch {
                        self.logger?.error("Error crawling \(nextTarget.url): \(error.localizedDescription)")
                    }
                    await self.state.completeCrawl()
                }
            }
        }
    }
    
    /// Retrieves all crawled pages.
    ///
    /// - Returns: An array of crawled pages.
    public func getCrawledPages() async -> [Page] {
        await state.getCrawledPages()
    }
}
