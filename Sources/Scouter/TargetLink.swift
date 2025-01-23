//
//  TargetLink.swift
//  Scouter
//
//  Created by Norikazu Muramoto on 2025/01/22.
//

import Foundation
import Remark

public struct TargetLink: Identifiable, Hashable, Sendable, Codable {
    public var id: String { url.absoluteString }
    public var priority: Priority
    public var url: URL
    public var texts: [String]
    
    enum CodingKeys: String, CodingKey {
        case priority, url, texts
    }
    
    public init(priority: Priority = .medium, url: URL, texts: [String]) {
        self.priority = priority
        self.url = url
        self.texts = texts
    }
    
    public static func == (lhs: TargetLink, rhs: TargetLink) -> Bool {
        lhs.url == rhs.url
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }
}

