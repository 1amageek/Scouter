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
    
    /// クロール済みURLを追跡し、既に存在する場合はfalseを返す
    public func markUrlAsCrawled(_ url: URL) -> Bool {
        if crawledUrls.contains(url) {
            return false
        }
        crawledUrls.insert(url)
        return true
    }
    
    /// 成功したページを追加
    public func addPage(_ page: Page) {
        guard crawledPages.count < maxPages else { return }
        crawledPages.insert(page)
    }
    
    /// 新しいターゲットリンクを追加
    @discardableResult
    public func addTarget(_ target: TargetLink) -> Bool {
        guard !crawledUrls.contains(target.url) else { return false }
        return targetLinks.insert(target).inserted
    }
    
    /// 次のクロール対象リンクを取得
    public func nextTarget() -> TargetLink? {
        guard activeCrawls < maxConcurrentCrawls else { return nil }
        let nextTarget = targetLinks.max { $0.priority < $1.priority }
        if let target = nextTarget {
            targetLinks.remove(target)
            activeCrawls += 1
            
            // 優先度が3以下ならカウントを増加、そうでなければリセット
            if target.priority.rawValue <= 3 {
                lowPriorityStreak += 1
            } else {
                lowPriorityStreak = 0
            }
        }
        return nextTarget
    }
    
    /// クロール完了を通知
    public func completeCrawl() {
        if activeCrawls > 0 {
            activeCrawls -= 1
        }
    }
    
    /// クロール済みページを取得
    public func getCrawledPages() -> [Page] {
        Array(crawledPages)
    }
    
    /// 最大ページ数に達しているか確認
    public func canAddPage() -> Bool {
        crawledPages.count < maxPages
    }
    
    /// 終了条件を満たしているか確認
    public func shouldTerminate() -> Bool {
        return crawledPages.count >= maxCrawledPages || lowPriorityStreak >= maxLowPriorityStreak
    }
    
    /// 進捗状況を取得
    public func getProgress() -> String {
        let crawledCount = crawledUrls.count
        let remainingTargets = targetLinks.count
        let activeCount = activeCrawls
        return "Crawled: \(crawledCount), Active: \(activeCount), Remaining: \(remainingTargets), MaxPages: \(maxPages)"
    }
}
