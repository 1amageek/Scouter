//
//  CrawlerState.swift
//  Scouter
//

import Foundation

public actor CrawlerState {
    private var crawledUrls: Set<URL> = []
    private var crawledPages: Set<Page> = []
    private var targetLinks: Set<TargetLink> = []
    private var lowPriorityStreak: Int = 0
    private var maxConcurrentCrawls: Int
    private var maxPages: Int
    private var maxLowPriorityStreak: Int = 2
    private var maxCrawledPages: Int
    private var activeCrawls: Int = 0
    private var terminationReason: TerminationReason?
    
    public init(
        maxConcurrentCrawls: Int = 5,
        maxPages: Int = 50,
        maxLowPriorityStreak: Int = 2,
        maxCrawledPages: Int = 10
    ) {
        self.maxConcurrentCrawls = maxConcurrentCrawls
        self.maxPages = maxPages
        self.maxLowPriorityStreak = maxLowPriorityStreak
        self.maxCrawledPages = maxCrawledPages
    }
    
    public func markUrlAsCrawled(_ url: URL) -> Bool {
        if crawledUrls.contains(url) {
            return false
        }
        crawledUrls.insert(url)
        return true
    }
    
    public func addPage(_ page: Page) {
        guard crawledPages.count < maxPages else { return }
        crawledPages.insert(page)
    }
    
    @discardableResult
    public func addTarget(_ target: TargetLink) -> Bool {
        guard !crawledUrls.contains(target.url) else { return false }
        return targetLinks.insert(target).inserted
    }
    
    public func nextTarget() -> TargetLink? {
        guard activeCrawls < maxConcurrentCrawls else { return nil }
        let nextTarget = targetLinks.max { $0.priority < $1.priority }
        if let target = nextTarget {
            targetLinks.remove(target)
            activeCrawls += 1
            
            if target.priority.rawValue <= 3 {
                lowPriorityStreak += 1
            } else {
                lowPriorityStreak = 0
            }
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
    
    public func shouldTerminate() -> Bool {
        if crawledPages.count >= maxCrawledPages {
            terminationReason = .maxPagesReached
            return true
        }
        if lowPriorityStreak >= maxLowPriorityStreak {
            terminationReason = .lowPriorityStreakExceeded
            return true
        }
        return false
    }
    
    public func getTerminationReason() -> TerminationReason {
        return terminationReason ?? .completed
    }
    
    public func getProgress() -> String {
        let crawledCount = crawledUrls.count
        let remainingTargets = targetLinks.count
        let activeCount = activeCrawls
        return "Crawled: \(crawledCount), Active: \(activeCount), Remaining: \(remainingTargets), MaxPages: \(maxPages)"
    }
}
