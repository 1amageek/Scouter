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
    public let depth: Int
    public var priority: Priority
    public var url: URL
    public var texts: [String]
    public var score: Float {
        return Float(priority.rawValue) * pow(0.94, Float(depth))
    }
    
    enum CodingKeys: String, CodingKey {
        case priority, url, texts, depth
    }
    
    public init(
        priority: Priority = .medium,
        depth: Int = 0,
        url: URL,
        texts: [String]
    ) {
        self.priority = priority
        self.depth = depth
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

