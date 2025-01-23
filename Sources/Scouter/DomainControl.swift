//
//  DomainControl.swift
//  Scouter
//
//  Created by Norikazu Muramoto on 2025/01/23.
//

import Foundation

public struct DomainControl: Sendable {
    public let exclude: Set<String>
    
    public init(
        exclude: Set<String> = ["facebook.com", "instagram.com"]
    ) {
        self.exclude = exclude
    }
}