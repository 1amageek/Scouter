//
//  Crawler.swift
//  Scouter
//
//  Created by Norikazu Muramoto on 2025/01/22.
//

import Foundation
import Remark

public actor Crawler {
    private let state: CrawlerState
    private let evaluator: Evaluator
    private let query: String
    
    public init(query: String, maxConcurrent: Int = 5) {
        self.query = query
        self.state = CrawlerState(maxConcurrentCrawls: maxConcurrent, maxPages: 50)
        self.evaluator = Evaluator()
    }
    
    func filterInvalidTargets(_ targets: [URL: [String]]) -> [URL: [String]] {
        let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "svg"]
        
        return targets.filter { url, texts in
            guard !texts.isEmpty else { return false }
            
            let hasOnlyImages = texts.allSatisfy { text in
                guard let ext = text.split(separator: ".").last?.lowercased() else { return false }
                return imageExtensions.contains(String(ext))
            }
            if hasOnlyImages { return false }
            
            guard url.host != nil else { return false }
            
            return true
        }
    }
    
    public func crawl(startUrl: URL) async throws {
        guard await state.canAddPage() else {
            print("Maximum pages reached. Stopping crawl.")
            return
        }
        
        let remark = try await Remark.fetch(from: startUrl)
        
        let links = try remark.extractLinks()
        var linksByUrl: [URL: [String]] = [:]
        
        for link in links {
            guard let url = URL(string: link.url), !link.text.isEmpty else {
                continue
            }
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: true) {
                var normalized = components
                normalized.fragment = nil
                if let normalizedUrl = normalized.url {
                    if linksByUrl[normalizedUrl] == nil {
                        linksByUrl[normalizedUrl] = []
                    }
                    linksByUrl[normalizedUrl]?.append(link.text)
                }
            }
        }
        
        let filteredLinksByUrl = filterInvalidTargets(linksByUrl)
        print(filteredLinksByUrl)
        let updatedTargets = try await evaluator.evaluateTargets(targets: filteredLinksByUrl, query: query)
        print(updatedTargets)
        for target in updatedTargets {
            await state.addTarget(target)
        }
        
        let page = Page(url: startUrl, remark: remark, crawledAt: Date())
        
        await state.addPage(page)
        
        await withTaskGroup(of: Void.self) { group in
            while let target = await state.nextTarget() {
                group.addTask {
                    do {
                        try await self.crawl(startUrl: target.url)
                    } catch {
                        print("Error crawling \(target.url): \(error)")
                    }
                    await self.state.completeCrawl()
                }
            }
        }
    }
    
    public func getCrawledPages() async -> [Page] {
        await state.getCrawledPages()
    }
}
