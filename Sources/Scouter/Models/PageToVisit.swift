//
//  PageToVisit.swift
//  Scouter
//
//  Created by Norikazu Muramoto on 2024/11/10.
//

import Foundation
import Selenops

public struct PageToVisit: Hashable, Sendable {
    
    /// The URL of the page - serves as unique identifier
    public let url: URL
    
    /// The title of the page if available
    public var title: String?
    
    /// Number of times the page has been visited
    public var visitCount: Int
    
    public var score: Float
    
    
    /// Initializes a new PageToVisit instance
    /// - Parameters:
    ///   - url: The URL to visit
    ///   - title: Optional title of the page
    ///   - visitCount: Number of visits (defaults to 0)
    ///   - similarity: Vector similarity score
    ///   - priority: Visit priority level
    public init(
        url: URL,
        title: String? = nil,
        visitCount: Int = 0,
        score: Float
    ) {
        self.url = url
        self.title = title
        self.visitCount = visitCount
        self.score = score
    }
    
    // Hashable implementation based on URL only
    public func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }
    
    // Equality based on URL only
    public static func == (lhs: PageToVisit, rhs: PageToVisit) -> Bool {
        return lhs.url == rhs.url
    }
}
