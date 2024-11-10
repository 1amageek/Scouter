//
//  PageMetadata.swift
//  Scouter
//
//  Created by Norikazu Muramoto on 2024/11/10.
//

import Foundation

public struct PageMetadata: Sendable {
    public let description: String?
    public let keywords: [String]
    public let ogData: [String: String]
    public let lastModified: Date?
    public let contentHash: String?
    
    public init(
        description: String? = nil,
        keywords: [String] = [],
        ogData: [String: String] = [:],
        lastModified: Date? = nil,
        contentHash: String? = nil
    ) {
        self.description = description
        self.keywords = keywords
        self.ogData = ogData
        self.lastModified = lastModified
        self.contentHash = contentHash
    }
}
