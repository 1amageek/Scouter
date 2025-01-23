//
//  CrawledPage.swift
//  Scouter
//
//  Created by Norikazu Muramoto on 2025/01/22.
//

import Foundation
import Remark

public struct Page: Identifiable, Hashable, Sendable {
    
    public var id: String { url.absoluteString }
    
    public var url: URL
    
    public var remark: Remark
    
    public var crawledAt: Date
    
    public init(url: URL, remark: Remark, crawledAt: Date) {
        self.url = url
        self.remark = remark
        self.crawledAt = crawledAt
    }
    
    public static func == (lhs: Page, rhs: Page) -> Bool {
        lhs.url == rhs.url
    }
    
    public nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }
}
