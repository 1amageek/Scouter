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
    private let options: Scouter.Options
    private let logger: Logger?
    
    public init(
        query: String,
        options: Scouter.Options = .default(),
        evaluator: any Evaluating,
        logger: Logger? = nil
    ) {
        self.query = query
        self.options = options
        self.state = CrawlerState(options: options)
        self.evaluator = evaluator
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
            guard !options.domainControl.exclude.contains(where: { domain in
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
    
    private func evaluateAndAddTargets(_ targets: [URL: [String]], depth: Int) async throws {
        
        let highScoreTargetLinks = await state.getHighScoreTargetLinks()
        if highScoreTargetLinks.count >= options.minHighScoreLinks {
            logger?.info("Sufficient potential links found (\(highScoreTargetLinks.count)), skipping detailed evaluation")
            return
        }
        do {
            let evaluatedLinks: [LinkEvaluation] = try await evaluator.evaluateTargets(targets: targets, query: query)
            for evaluation in evaluatedLinks {
                let target = TargetLink(priority: evaluation.priority, depth: depth + 1, url: evaluation.url, texts: evaluation.texts)
                if target.score > 1.2 {
                    if await state.addTarget(target) {
                        logger?.info("\(target.logDescription)")
                    }
                } else {
                    print("🚧 ", target.logDescription)
                }
            }
        } catch {
            print(error)
            logger?.error("Failed to evaluate targets")
        }
    }
    
    public func crawl(startUrl: URL, depth: Int = 0) async throws {
        guard let normalizedUrl = normalizeUrl(startUrl) else {
            logger?.warning("Invalid URL: \(startUrl)")
            return
        }
        
        guard await state.markUrlAsCrawled(normalizedUrl) else {
            logger?.info("URL already crawled: \(normalizedUrl)")
            return
        }
        
        if let terminationReason = await state.shouldTerminate() {
            logger?.info("Crawling terminated: \(terminationReason)")
            return
        }
        
        guard let remark = try? await Remark.fetch(from: normalizedUrl) else {
            logger?.error("Failed to fetch \(normalizedUrl)")
            return
        }
        
        let links = try remark.extractLinks()
            .filter { link in
                guard let url = URL(string: link.url),
                      url.scheme?.lowercased() == "https",
                      !link.text.isEmpty else {
                    return false
                }
                return true
            }
        
        var filteredLinksByUrl: [URL: [String]] = [:]
        for link in links {
            guard let linkUrl = URL(string: link.url),
                  !link.text.isEmpty,
                  let normalizedLinkUrl = normalizeUrl(linkUrl) else { continue }
            filteredLinksByUrl[normalizedLinkUrl, default: []].append(link.text)
        }
        filteredLinksByUrl = filterInvalidTargets(filteredLinksByUrl)
        
        try await evaluateAndAddTargets(filteredLinksByUrl, depth: depth)
        
        guard let pagePriority = try? await evaluator.evaluateContent(content: remark.plainText, query: query) else {
            logger?.error("Failed to evaluate content for \(normalizedUrl)")
            return
        }
        
        let page = Page(url: normalizedUrl, remark: remark, priority: pagePriority, crawledAt: Date())
        await state.addPage(page)
        
        let progress = await state.getProgress()
        logger?.info("Crawling Progress: \(progress)")
        
        await withTaskGroup(of: Void.self) { group in
            while let nextTarget = await state.nextTarget() {
                group.addTask {
                    do {
                        try await self.crawl(startUrl: nextTarget.url, depth: nextTarget.depth)
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
