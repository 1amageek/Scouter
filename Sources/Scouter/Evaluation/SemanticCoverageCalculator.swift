//
//  SemanticCoverageCalculator.swift
//  Scouter
//
//  Created by Norikazu Muramoto on 2024/11/10.
//

import Foundation
import AspectAnalyzer
import OllamaKit

/// Calculates semantic coverage using AspectAnalyzer for comprehensive query understanding
public actor SemanticCoverageCalculator: Sendable {
    private let aspectAnalyzer: AspectAnalyzer
    private let ollamaKit: OllamaKit
    
    public struct Coverage: Sendable {
        /// Overall coverage score (0.0 to 1.0)
        let score: Float
        /// Coverage by critical aspects identified by AspectAnalyzer
        let aspectCoverage: [AspectAnalyzer.Aspect: Float]
        /// Areas needing more information
        let gaps: [AspectAnalyzer.Aspect]
        /// Knowledge areas covered
        let coveredKnowledge: Set<String>
        /// Expected but missing information types
        let missingInfoTypes: Set<String>
    }
    
    public struct Configuration: Sendable {
        /// Minimum coverage score for each aspect (0.0 to 1.0)
        let minAspectCoverage: Float
        /// Weight for each evaluation factor
        let weights: Weights
        
        public struct Weights: Sendable {
            /// Weight for aspect coverage
            let aspectCoverage: Float
            /// Weight for knowledge area coverage
            let knowledgeCoverage: Float
            /// Weight for information type coverage
            let infoTypeCoverage: Float
            
            public init(
                aspectCoverage: Float = 0.5,
                knowledgeCoverage: Float = 0.3,
                infoTypeCoverage: Float = 0.2
            ) {
                self.aspectCoverage = aspectCoverage
                self.knowledgeCoverage = knowledgeCoverage
                self.infoTypeCoverage = infoTypeCoverage
            }
        }
        
        public init(
            minAspectCoverage: Float = 0.7,
            weights: Weights = Weights()
        ) {
            self.minAspectCoverage = minAspectCoverage
            self.weights = weights
        }
    }
    
    public init(model: String) {
        self.aspectAnalyzer = AspectAnalyzer(model: model)
        self.ollamaKit = OllamaKit()
    }
    
    /// Calculates semantic coverage based on AspectAnalyzer results
    public func calculateCoverage(
        pages: [VisitedPage],
        query: Scouter.Query,
        configuration: Configuration = Configuration()
    ) async throws -> Coverage {
        // 1. Analyze query using AspectAnalyzer
        let analysis = try await aspectAnalyzer.analyzeQuery(query.prompt)
        
        // 2. Calculate coverage for each critical aspect
        var aspectCoverage: [AspectAnalyzer.Aspect: Float] = [:]
        var gaps: [AspectAnalyzer.Aspect] = []
        
        for aspect in analysis.criticalAspects {
            let coverage = try await calculateAspectCoverage(
                aspect: aspect,
                pages: pages,
                query: query
            )
            
            aspectCoverage[aspect] = coverage
            
            if coverage < configuration.minAspectCoverage {
                gaps.append(aspect)
            }
        }
        
        // 3. Analyze knowledge area coverage
        let coveredKnowledge = extractCoveredKnowledge(
            pages: pages,
            requiredKnowledge: Set(analysis.aspects.flatMap { $0.requiredKnowledge })
        )
        
        // 4. Analyze information type coverage
        let expectedInfoTypes = Set(analysis.aspects.flatMap { $0.expectedInfoTypes })
        let coveredInfoTypes = extractCoveredInfoTypes(pages: pages)
        let missingInfoTypes = expectedInfoTypes.subtracting(coveredInfoTypes)
        
        // 5. Calculate overall coverage score
        let score = calculateOverallScore(
            aspectCoverage: aspectCoverage,
            coveredKnowledge: coveredKnowledge,
            requiredKnowledge: Set(analysis.aspects.flatMap { $0.requiredKnowledge }),
            coveredInfoTypes: coveredInfoTypes,
            expectedInfoTypes: expectedInfoTypes,
            weights: configuration.weights
        )
        
        return Coverage(
            score: score,
            aspectCoverage: aspectCoverage,
            gaps: gaps,
            coveredKnowledge: coveredKnowledge,
            missingInfoTypes: missingInfoTypes
        )
    }
    
    /// Calculates coverage for a specific aspect
    private func calculateAspectCoverage(
        aspect: AspectAnalyzer.Aspect,
        pages: [VisitedPage],
        query: Scouter.Query
    ) async throws -> Float {
        // Get embedding for aspect description
        let aspectEmbedding = try await VectorSimilarity.getEmbedding(
            for: aspect.description,
            model: aspectAnalyzer.model
        )
        
        // Calculate similarity with relevant pages
        let relevantPages = pages.filter { $0.isRelevant }
        var coverageScores: [Float] = []
        
        for page in relevantPages {
            // Calculate semantic similarity
            let similarity = VectorSimilarity.cosineSimilarity(aspectEmbedding, page.embedding)
            
            // Weight by page relevance
            let weightedScore = similarity * page.similarity
            coverageScores.append(weightedScore)
        }
        
        // Calculate weighted average coverage
        let coverage: Float = coverageScores.reduce(0.0, +) / Float(max(coverageScores.count, 1))
        
        // Apply importance-based scaling
        return coverage * aspect.importance
    }
    
    /// Extracts covered knowledge areas from collected pages
    private func extractCoveredKnowledge(
        pages: [VisitedPage],
        requiredKnowledge: Set<String>
    ) -> Set<String> {
        var coveredKnowledge: Set<String> = []
        
        for page in pages where page.isRelevant {
            // This would ideally use more sophisticated knowledge area detection
            for area in requiredKnowledge {
                if page.content.localizedCaseInsensitiveContains(area) {
                    coveredKnowledge.insert(area)
                }
            }
        }
        
        return coveredKnowledge
    }
    
    /// Extracts covered information types from collected pages
    private func extractCoveredInfoTypes(pages: [VisitedPage]) -> Set<String> {
        var coveredTypes: Set<String> = []
        
        // This would ideally use more sophisticated content type analysis
        for page in pages where page.isRelevant {
            if page.content.contains("statistics") || page.content.contains("data") {
                coveredTypes.insert("statistical")
            }
            if page.content.contains("concept") || page.content.contains("theory") {
                coveredTypes.insert("theoretical")
            }
            if page.content.contains("example") || page.content.contains("practice") {
                coveredTypes.insert("practical")
            }
            if page.content.contains("research") || page.content.contains("study") {
                coveredTypes.insert("research")
            }
        }
        
        return coveredTypes
    }
    
    /// Calculates overall coverage score
    private func calculateOverallScore(
        aspectCoverage: [AspectAnalyzer.Aspect: Float],
        coveredKnowledge: Set<String>,
        requiredKnowledge: Set<String>,
        coveredInfoTypes: Set<String>,
        expectedInfoTypes: Set<String>,
        weights: Configuration.Weights
    ) -> Float {
        // Calculate aspect coverage score
        let aspectScore = aspectCoverage.values.reduce(0.0, +) / Float(max(aspectCoverage.count, 1))
        
        // Calculate knowledge coverage score
        let knowledgeScore = Float(coveredKnowledge.count) / Float(max(requiredKnowledge.count, 1))
        
        // Calculate info type coverage score
        let infoTypeScore = Float(coveredInfoTypes.count) / Float(max(expectedInfoTypes.count, 1))
        
        // Calculate weighted final score
        return aspectScore * weights.aspectCoverage +
        knowledgeScore * weights.knowledgeCoverage +
        infoTypeScore * weights.infoTypeCoverage
    }
    

}
