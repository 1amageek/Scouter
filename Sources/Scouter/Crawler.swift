//
//  Crawler.swift
//  Scouter
//
//  Created by Norikazu Muramoto on 2025/01/22.
//

import Foundation
import Remark
import Logging

public actor Crawler {
    private let state: CrawlerState
    private let evaluator: any Evaluating
    private let query: String
    private let domainControl: DomainControl
    private let logger: Logger?
    
    
    public init(
        query: String,
        maxConcurrent: Int = 5,
        evaluator: any Evaluating,
        domainControl: DomainControl = DomainControl(),
        logger: Logger? = nil
    ) {
        self.query = query
        self.state = CrawlerState(maxConcurrentCrawls: maxConcurrent, maxPages: 30)
        self.evaluator = evaluator
        self.domainControl = domainControl
        self.logger = logger
    }
    
    private func normalizeUrl(_ url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return nil }
        components.fragment = nil
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        return components.url
    }
    
    func filterInvalidTargets(_ targets: [URL: [String]]) -> [URL: [String]] {
        let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "svg", "mp4", "avi", "mov"]
        
        return targets.reduce(into: [URL: [String]]()) { result, entry in
            let (url, texts) = entry
            
            guard let host = url.host?.lowercased() else { return }
            guard !domainControl.exclude.contains(where: { domain in
                host == domain || host.hasSuffix("." + domain)
            }) else { return }
            
            let uniqueTexts = Array(Set(texts))
            guard !uniqueTexts.isEmpty else { return }
            
            let hasOnlyImages = uniqueTexts.allSatisfy { text in
                guard let ext = text.split(separator: ".").last?.lowercased() else { return false }
                return imageExtensions.contains(String(ext))
            }
            if hasOnlyImages { return }
            
            result[url] = uniqueTexts
        }
    }
    
    public func crawl(startUrl: URL) async throws {
        guard let normalizedUrl = normalizeUrl(startUrl) else {
            logger?.warning("Invalid URL: \(startUrl)")
            return
        }
        
        guard await state.markUrlAsCrawled(normalizedUrl) else {
            logger?.info("URL already crawled: \(normalizedUrl)")
            return
        }
        
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
        
        guard let pagePriority = try? await evaluator.evaluateContent(
            content: remark.plainText,
            query: query
        ) else {
            logger?.error("Failed to evaluate content for \(normalizedUrl)")
            return
        }
        
        let page = Page(
            url: normalizedUrl,
            remark: remark,
            priority: pagePriority,
            crawledAt: Date()
        )
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
    
    public func getCrawlerState() async -> (pages: [Page], terminationReason: TerminationReason) {
        let pages = await state.getCrawledPages()
        let reason = await state.getTerminationReason()
        return (pages, reason)
    }
    
    public func getCrawledPages() async -> [Page] {
        await state.getCrawledPages()
    }
}
