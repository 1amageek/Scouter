//
//  Priority.swift
//  Scouter
//
//  Created by Norikazu Muramoto on 2025/01/22.
//

import Foundation

public enum Priority: Int, Comparable, Sendable, RawRepresentable, Codable {
    case critical = 5
    case veryHigh = 4
    case high = 3
    case medium = 2
    case low = 1
    
    public init?(rawValue: String) {
        switch rawValue.lowercased() {
        case "low": self = .low
        case "medium": self = .medium
        case "high": self = .high
        case "veryhigh": self = .veryHigh
        case "critical": self = .critical
        default: return nil
        }
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(Int.self)
        switch value {
        case ...1: self = .low
        case 2: self = .medium
        case 3: self = .high
        case 4: self = .veryHigh
        case 5...: self = .critical
        default: self = .medium
        }
    }
    
    public static func < (lhs: Priority, rhs: Priority) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}
