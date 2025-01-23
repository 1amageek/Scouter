//
//  Scouter.swift
//  Scouter
//
//  Created by Norikazu Muramoto on 2024/11/10.
//

import Foundation
import SwiftSoup
import OllamaKit
import Remark
import AspectAnalyzer
import Logging
import Unknown
import OpenAI

public struct Scouter: Sendable {

    public static func search(
        prompt: String,
        options: Options = .default(),
        logger: Logger? = nil
    ) async throws -> Result {
        let startTime = Date()
        
        // Google検索URLの作成
        let encodedQuery = try encodeGoogleSearchQuery(prompt)
        let searchUrl = URL(string: "https://www.google.com/search?q=\(encodedQuery)")!
        
        // Google検索結果の取得
        let searchResults = try await fetchGoogleSearchResults(searchUrl, logger: logger)
        // クローラーの初期化と実行
        let crawler = Crawler(
            query: prompt,
            maxConcurrent: options.maxConcurrentCrawls
        )        
        // 初期URLセットからクローリング開始
        for url in searchResults {
            try await crawler.crawl(startUrl: url)
        }
        
        // 結果の取得
        let pages = await crawler.getCrawledPages()
        let duration = Date().timeIntervalSince(startTime)

        return Result(
            query: prompt,
            pages: pages,
            searchDuration: duration
        )
    }
    
    private static func fetchGoogleSearchResults(
        _ url: URL,
        logger: Logger?
    ) async throws -> [URL] {
        logger?.info("Fetching Google search results", metadata: ["url": .string(url.absoluteString)])
        
        // Google検索ページの取得
        let remark = try await Remark.fetch(from: url, method: .interactive)
        
        // メインコンテンツ部分の抽出
        let div = try SwiftSoup.parse(remark.html).select("div#rcnt")
        let searchContent = try Remark(try div.html())
        
        // リンクの抽出と変換
        let links = try searchContent.extractLinks()
            .compactMap { link -> URL? in
                guard let url = URL(string: link.url) else { return nil }
                // Googleのリダイレクトリンクを処理
                return processGoogleRedirect(url)
            }
            .filter { url in
                // 不要なドメインを除外
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
        
        public init(query: String, pages: [Page], searchDuration: TimeInterval) {
            self.query = query
            self.pages = pages
            self.searchDuration = searchDuration
        }
    }
    /// クローラーの設定オプション
    public struct Options: Sendable {
        /// LLMの設定
        public let model: String
        
        /// クローリングの制限設定
        public let maxDepth: Int           // 最大探索深さ
        public let maxPages: Int           // 最大ページ数
        public let minRelevantPages: Int   // 必要な関連ページ数
        public let maxRetries: Int         // 最大リトライ回数
        
        /// スコアリングのしきい値
        public let relevancyThreshold: Float  // ページの関連性しきい値
        public let minimumLinkScore: Float   // リンクの最小スコア
        
        /// 並列処理の設定
        public let maxConcurrentCrawls: Int // 同時クロール数
        public let evaluateChunkSize: Int   // 一度に評価するリンク数
        
        /// タイムアウト設定
        public let timeout: TimeInterval     // ネットワークタイムアウト
        
        /// ドメイン制御
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
        
        /// デフォルト設定のインスタンスを生成
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
    
    /// ドメイン制御の設定
    public struct DomainControl: Sendable {
        /// 関連性カウントから除外するドメイン
        public let excludeFromRelevant: Set<String>
        
        /// クローリング対象から除外するドメイン
        public let excludeFromCrawling: Set<String>
        
        /// 評価対象から除外するドメイン
        public let excludeFromEvaluation: Set<String>
        
        public init(
            excludeFromRelevant: Set<String> = ["google.com", "google.co.jp"],
            excludeFromCrawling: Set<String> = [],
            excludeFromEvaluation: Set<String> = ["facebook.com", "instagram.com"]
        ) {
            self.excludeFromRelevant = excludeFromRelevant
            self.excludeFromCrawling = excludeFromCrawling
            self.excludeFromEvaluation = excludeFromEvaluation
        }
    }
    
    /// オプション設定時のエラー
    public enum OptionsError: Error, CustomStringConvertible {
        /// minimumLinkScoreがrelevancyThreshold以上の場合に発生
        case invalidThresholds(minimumLinkScore: Float, relevancyThreshold: Float)
        
        public var description: String {
            switch self {
            case .invalidThresholds(let min, let relevancy):
                return "minimumLinkScore (\(min)) must be lower than relevancyThreshold (\(relevancy))"
            }
        }
    }
}
