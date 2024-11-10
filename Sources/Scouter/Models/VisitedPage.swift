//
//  VisitedPage.swift
//  Scouter
//
//  Created by Norikazu Muramoto on 2024/11/10.
//

import Foundation

public struct VisitedPage: Identifiable, Sendable {
    public let id: UUID
    public let url: URL
    public let title: String
    public let content: String
    public let embedding: [Float]
    public let similarity: Float
    public let visitedAt: Date
    public let summary: String?
    public let isRelevant: Bool
    public let metadata: PageMetadata
    
    public init(
        id: UUID = UUID(),
        url: URL,
        title: String,
        content: String,
        embedding: [Float],
        similarity: Float,
        visitedAt: Date = Date(),
        summary: String? = nil,
        isRelevant: Bool = false,
        metadata: PageMetadata
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.content = content
        self.embedding = embedding
        self.similarity = similarity
        self.visitedAt = visitedAt
        self.summary = summary
        self.isRelevant = isRelevant
        self.metadata = metadata
    }
}