//
//  CrawlerState.swift
//  Scouter
//

import Foundation

public actor CrawlerState {
    private var crawledPages: Set<Page> = []
    private var targetLinks: Set<TargetLink> = []
    private let maxConcurrentCrawls: Int
    private let maxPages: Int
    private var activeCrawls: Int = 0
    
    public init(maxConcurrentCrawls: Int = 5, maxPages: Int = 50) {
        self.maxConcurrentCrawls = maxConcurrentCrawls
        self.maxPages = maxPages
    }
    
    public func addPage(_ page: Page) {
        crawledPages.insert(page)
    }
    
    public func addTarget(_ target: TargetLink) -> Bool {
        guard !crawledPages.contains(where: { $0.url == target.url }) else {
            return false
        }
        return targetLinks.insert(target).inserted
    }
    
    public func nextTarget() -> TargetLink? {
        guard activeCrawls < maxConcurrentCrawls else {
            return nil
        }
        let nextTarget = targetLinks.max { $0.priority < $1.priority }
        if let target = nextTarget {
            targetLinks.remove(target)
            activeCrawls += 1
        }
        return nextTarget
    }
    
    public func completeCrawl() {
        if activeCrawls > 0 {
            activeCrawls -= 1
        }
    }
    
    public func getCrawledPages() -> [Page] {
        Array(crawledPages)
    }
    
    public func canAddPage() -> Bool {
        crawledPages.count < maxPages
    }
}
