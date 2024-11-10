//
//  PageToVisit.swift
//  Scouter
//
//  Created by Norikazu Muramoto on 2024/11/10.
//

import Foundation
import Selenops

public struct PageToVisit: Hashable, Sendable {
    /// Priority levels for page visits
    public enum Priority: Int, Comparable, Sendable {
        case critical = 3    // Critical importance and urgency
        case high = 2       // High importance
        case medium = 1     // Related content
        case low = 0        // Reference only
        
        public static func < (lhs: Priority, rhs: Priority) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }
    }
    
    /// The URL of the page - serves as unique identifier
    public let url: URL
    
    /// The title of the page if available
    public var title: String?
    
    /// Number of times the page has been visited
    public var visitCount: Int
    
    /// Combined score based on similarity and priority
    public var score: Float {
        similarity * Float(priority.rawValue + 1)
    }
    
    /// Vector similarity score
    public var similarity: Float
    
    /// Visit priority level
    public var priority: Priority
    
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
        similarity: Float,
        priority: Priority
    ) {
        self.url = url
        self.title = title
        self.visitCount = visitCount
        self.similarity = similarity
        self.priority = priority
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

// MARK: - PageToVisit + LinkEvaluation
extension PageToVisit {
    /// Creates a PageToVisit instance from a LinkEvaluation
    /// - Parameters:
    ///   - evaluation: The link evaluation to convert from
    ///   - similarity: Vector similarity score
    /// - Returns: A new PageToVisit instance
    public init(from link: Crawler.Link, priority: LinkEvaluation.Priority, similarity: Float) {
        self.url = link.url
        self.title = link.title
        self.visitCount = 0
        self.similarity = similarity
        self.priority = Priority(from: priority)
    }
}

// MARK: - PageToVisit.Priority + LinkEvaluation.Priority
extension PageToVisit.Priority {
    /// Creates a PageToVisit.Priority from a LinkEvaluation.Priority
    init(from evaluationPriority: LinkEvaluation.Priority) {
        switch evaluationPriority {
        case .critical: self = .critical
        case .high: self = .high
        case .medium: self = .medium
        case .low: self = .low
        }
    }
}
