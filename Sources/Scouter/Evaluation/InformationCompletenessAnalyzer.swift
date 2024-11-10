//
//  InformationCompletenessAnalyzer.swift
//  Scouter
//
//  Created by Norikazu Muramoto on 2024/11/10.
//

import Foundation
import AspectAnalyzer

/// Analyzes the completeness of collected information using both aspect analysis and semantic coverage
public struct InformationCompletenessAnalyzer: Sendable {
    
    private let aspectAnalyzer: AspectAnalyzer
    private let coverageCalculator: SemanticCoverageCalculator
    
    public struct CompletenessResult: Sendable {
        /// Overall completeness score (0.0 to 1.0)
        let score: Float
        /// Analysis of query aspects and their coverage
        let aspectAnalysis: AspectAnalyzer.Analysis
        /// Semantic coverage analysis
        let coverageAnalysis: SemanticCoverageCalculator.Coverage
        /// Whether the information collection is complete
        let isComplete: Bool
        /// Detailed completion metrics
        let metrics: CompletionMetrics
        /// Reasoning for completion status
        let reasoning: String
    }
    
    public struct CompletionMetrics: Sendable {
        /// Number of distinct aspects covered
        let aspectsCovered: Int
        /// Total number of aspects identified
        let totalAspects: Int
        /// Number of relevant sources found
        let relevantSources: Int
        /// Coverage score for critical aspects
        let criticalAspectsCoverage: Float
        /// Information gain trend
        let recentGainTrend: [Float]
    }
    
    public struct Configuration {
        /// Minimum overall completeness score required
        let minimumCompletenessScore: Float
        /// Minimum coverage required for critical aspects
        let criticalAspectCoverageThreshold: Float
        /// Minimum number of relevant sources required
        let minimumRelevantSources: Int
        /// Maximum number of uncovered critical aspects allowed
        let maxUncoveredCriticalAspects: Int
        /// Threshold for information gain significance
        let gainSignificanceThreshold: Float
        
        public init(
            minimumCompletenessScore: Float = 0.75,
            criticalAspectCoverageThreshold: Float = 0.8,
            minimumRelevantSources: Int = 3,
            maxUncoveredCriticalAspects: Int = 0,
            gainSignificanceThreshold: Float = 0.1
        ) {
            self.minimumCompletenessScore = minimumCompletenessScore
            self.criticalAspectCoverageThreshold = criticalAspectCoverageThreshold
            self.minimumRelevantSources = minimumRelevantSources
            self.maxUncoveredCriticalAspects = maxUncoveredCriticalAspects
            self.gainSignificanceThreshold = gainSignificanceThreshold
        }
    }
    
    public init(model: String) {
        self.aspectAnalyzer = AspectAnalyzer(model: model)
        self.coverageCalculator = SemanticCoverageCalculator(model: model)
    }
    
    /// Analyzes the completeness of collected information
    public func analyzeCompleteness(
        pages: [VisitedPage],
        query: Scouter.Query,
        config: Configuration = Configuration()
    ) async throws -> CompletenessResult {
        // 1. Perform aspect analysis
        let aspectAnalysis = try await aspectAnalyzer.analyzeQuery(query.prompt)
        
        // 2. Calculate semantic coverage
        let coverageAnalysis = try await coverageCalculator.calculateCoverage(
            pages: pages,
            query: query
        )
        
        // 3. Calculate completion metrics
        let metrics = try await calculateCompletionMetrics(
            pages: pages,
            aspectAnalysis: aspectAnalysis,
            coverageAnalysis: coverageAnalysis
        )
        
        // 4. Calculate overall completeness score
        let completenessScore = calculateCompletenessScore(
            aspectAnalysis: aspectAnalysis,
            coverageAnalysis: coverageAnalysis,
            metrics: metrics
        )
        
        // 5. Determine if information collection is complete
        let (isComplete, reasoning) = determineCompletion(
            score: completenessScore,
            metrics: metrics,
            config: config
        )
        
        return CompletenessResult(
            score: completenessScore,
            aspectAnalysis: aspectAnalysis,
            coverageAnalysis: coverageAnalysis,
            isComplete: isComplete,
            metrics: metrics,
            reasoning: reasoning
        )
    }
    
    /// Calculates detailed completion metrics
    private func calculateCompletionMetrics(
        pages: [VisitedPage],
        aspectAnalysis: AspectAnalyzer.Analysis,
        coverageAnalysis: SemanticCoverageCalculator.Coverage
    ) async throws -> CompletionMetrics {
        // Count covered aspects
        let coveredAspects = aspectAnalysis.aspects.filter { aspect in
            if let coverage = coverageAnalysis.aspectCoverage[aspect] {
                return coverage >= 0.7
            }
            return false
        }
        
        // Calculate critical aspects coverage
        let criticalAspectsCoverage = calculateCriticalAspectsCoverage(
            criticalAspects: aspectAnalysis.criticalAspects,
            coverageAnalysis: coverageAnalysis
        )
        
        // Count relevant sources
        let relevantSources = countRelevantSources(pages: pages)
        
        // Calculate recent information gain trend
        let gainTrend = calculateRecentGainTrend(pages: pages)
        
        return CompletionMetrics(
            aspectsCovered: coveredAspects.count,
            totalAspects: aspectAnalysis.aspects.count,
            relevantSources: relevantSources,
            criticalAspectsCoverage: criticalAspectsCoverage,
            recentGainTrend: gainTrend
        )
    }
    
    /// Calculates coverage for critical aspects
    private func calculateCriticalAspectsCoverage(
        criticalAspects: [AspectAnalyzer.Aspect],
        coverageAnalysis: SemanticCoverageCalculator.Coverage
    ) -> Float {
        let coverageScores = criticalAspects.compactMap { aspect in
            coverageAnalysis.aspectCoverage[aspect]
        }
        
        return coverageScores.reduce(0, +) / Float(max(1, criticalAspects.count))
    }
    
    /// Counts number of relevant sources
    private func countRelevantSources(pages: [VisitedPage]) -> Int {
        let relevantPages = pages.filter { $0.isRelevant }
        let domains = Set(relevantPages.map { $0.url.host ?? "" })
        return domains.count
    }
    
    /// Calculates trend of recent information gains
    private func calculateRecentGainTrend(pages: [VisitedPage]) -> [Float] {
        guard pages.count > 1 else { return [] }
        
        var gains: [Float] = []
        let windowSize = 3
        
        for i in stride(from: pages.count - 1, through: windowSize, by: -1) {
            let currentWindow = Array(pages[i-windowSize...i])
            let previousWindow = Array(pages[i-windowSize-1...i-1])
            
            let gain = calculateInformationGain(
                current: currentWindow,
                previous: previousWindow
            )
            gains.append(gain)
            
            if gains.count >= 5 { break } // Only keep last 5 gains
        }
        
        return gains.reversed()
    }
    
    /// Calculates information gain between two windows of pages
    private func calculateInformationGain(
        current: [VisitedPage],
        previous: [VisitedPage]
    ) -> Float {
        let currentEmbedding = VectorSimilarity.averageEmbedding(current.map { $0.embedding })
        let previousEmbedding = VectorSimilarity.averageEmbedding(previous.map { $0.embedding })
        
        return 1.0 - VectorSimilarity.cosineSimilarity(currentEmbedding, previousEmbedding)
    }
    
    /// Calculates overall completeness score
    private func calculateCompletenessScore(
        aspectAnalysis: AspectAnalyzer.Analysis,
        coverageAnalysis: SemanticCoverageCalculator.Coverage,
        metrics: CompletionMetrics
    ) -> Float {
        // Weight different factors:
        // - Aspect coverage: 0.4
        // - Semantic coverage: 0.3
        // - Critical aspects: 0.3
        
        let aspectCoverageScore = Float(metrics.aspectsCovered) / Float(metrics.totalAspects)
        let semanticCoverageScore = coverageAnalysis.score
        let criticalAspectsScore = metrics.criticalAspectsCoverage
        
        return 0.4 * aspectCoverageScore +
        0.3 * semanticCoverageScore +
        0.3 * criticalAspectsScore
    }
    
    /// Determines if information collection is complete
    private func determineCompletion(
        score: Float,
        metrics: CompletionMetrics,
        config: Configuration
    ) -> (Bool, String) {
        // Check overall completeness score
        if score < config.minimumCompletenessScore {
            return (false, "Overall completeness score below threshold")
        }
        
        // Check critical aspects coverage
        if metrics.criticalAspectsCoverage < config.criticalAspectCoverageThreshold {
            return (false, "Insufficient coverage of critical aspects")
        }
        
        // Check relevant sources
        if metrics.relevantSources < config.minimumRelevantSources {
            return (false, "Insufficient number of relevant sources")
        }
        
        // Check information gain trend
        let recentGains = metrics.recentGainTrend
        if !recentGains.isEmpty && recentGains.allSatisfy({ $0 < config.gainSignificanceThreshold }) {
            return (true, "Information gain has converged")
        }
        
        if score >= 0.9 {
            return (true, "Excellent coverage achieved")
        }
        
        return (true, "Sufficient coverage and sources found")
    }
}
