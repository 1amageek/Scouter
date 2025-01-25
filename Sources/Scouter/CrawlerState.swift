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
    private var activeCrawls: Int = 0
    private var terminationReason: TerminationReason?
    private let options: Scouter.Options
    
    public init(options: Scouter.Options = .default()) {
        self.options = options
    }
    
    public func markUrlAsCrawled(_ url: URL) -> Bool {
        if crawledUrls.contains(url) { return false }
        crawledUrls.insert(url)
        return true
    }
    
    public func addPage(_ page: Page) {
        guard crawledPages.count < options.maxPages else { return }
        crawledPages.insert(page)
    }
    
    @discardableResult
    public func addTarget(_ target: TargetLink) -> Bool {
        guard !crawledUrls.contains(target.url) else { return false }
        return targetLinks.insert(target).inserted
    }
    
    public func nextTarget() -> TargetLink? {
        guard activeCrawls < options.maxConcurrentCrawls else { return nil }
        let nextTarget = targetLinks.max { a, b in
            return a.score < b.score
        }
        if let target = nextTarget {
            targetLinks.remove(target)
            activeCrawls += 1
            if crawledPages.count > 3 && target.score <= options.minimumLinkScore {
                lowPriorityStreak += 1
            } else {
                lowPriorityStreak = 0
            }
        }
        return nextTarget
    }
    
    public func completeCrawl() {
        if activeCrawls > 0 { activeCrawls -= 1 }
    }
    
    public func getHighScoreTargetLinks() -> Set<TargetLink> {
        targetLinks.filter { $0.score >= options.highScoreThreshold }
    }
    
    public func getCrawledPages() -> [Page] {
        Array(crawledPages)
    }
    
    public func shouldTerminate() -> TerminationReason? {
        if crawledPages.count >= options.maxCrawledPages {
            terminationReason = .maxPagesReached
            return terminationReason
        }
        if lowPriorityStreak >= options.maxLowPriorityStreak {
            terminationReason = .lowPriorityStreakExceeded
            return terminationReason
        }
        return nil
    }
    
    public func getTerminationReason() -> TerminationReason {
        return terminationReason ?? .completed
    }
    
    public func getProgress() -> String {
        let crawledCount = crawledUrls.count
        let remainingTargets = targetLinks.count
        let activeCount = activeCrawls
        let highScoreCount = getHighScoreTargetLinks().count
        
        return "Crawled: \(crawledCount), Active: \(activeCount), High-Score: \(highScoreCount), Remaining: \(remainingTargets), MaxPages: \(options.maxPages)"
    }
}
