//
//  CrawlCompletionAnalyzer.swift
//  Scouter
//
//  Created by Norikazu Muramoto on 2024/11/11.
//

import Foundation
import AspectAnalyzer
import Logging

/// Manages the completion strategy for web crawling using multiple analysis methods
public struct CrawlCompletionAnalyzer: Sendable {
    private let aspectAnalyzer: AspectAnalyzer
    private let coverageCalculator: SemanticCoverageCalculator
    private let completenessAnalyzer: InformationCompletenessAnalyzer
    private let logger: Logger?
    
    /// Configuration for determining crawl completion
    public struct Configuration: Sendable {
        /// Minimum aspect coverage required (0.0 to 1.0)
        let minimumAspectCoverage: Float
        /// Minimum semantic coverage required (0.0 to 1.0)
        let minimumSemanticCoverage: Float
        /// Minimum completeness score required (0.0 to 1.0)
        let minimumCompletenessScore: Float
        /// Number of consecutive analyses needed to confirm completion
        let confirmationCount: Int
        /// Interval between completion checks
        let analysisInterval: Int
        
        public init(
            minimumAspectCoverage: Float = 0.7,
            minimumSemanticCoverage: Float = 0.7,
            minimumCompletenessScore: Float = 0.7,
            confirmationCount: Int = 3,
            analysisInterval: Int = 5
        ) {
            self.minimumAspectCoverage = minimumAspectCoverage
            self.minimumSemanticCoverage = minimumSemanticCoverage
            self.minimumCompletenessScore = minimumCompletenessScore
            self.confirmationCount = confirmationCount
            self.analysisInterval = analysisInterval
        }
    }
    
    /// Detailed completion analysis results
    public struct CompletionAnalysis: Sendable {
        let aspectAnalysis: AspectAnalyzer.Analysis
        let coverageAnalysis: SemanticCoverageCalculator.Coverage
        let completenessAnalysis: InformationCompletenessAnalyzer.CompletenessResult
        let isComplete: Bool
        let reason: String
        let recommendations: [String]
    }
    
    public init(
        model: String,
        logger: Logger? = nil
    ) {
        self.aspectAnalyzer = AspectAnalyzer(model: model)
        self.coverageCalculator = SemanticCoverageCalculator(model: model)
        self.completenessAnalyzer = InformationCompletenessAnalyzer(model: model)
        self.logger = logger
    }
    
    /// Analyzes whether crawling should be completed
    public func shouldComplete(
        pages: [VisitedPage],
        query: Scouter.Query,
        configuration: Configuration
    ) async throws -> CompletionAnalysis {
        // Skip analysis if we don't have enough pages
        if pages.count < configuration.analysisInterval {
            return createIncompleteAnalysis(reason: "Insufficient pages for analysis")
        }
        
        // 1. Aspect Analysis
        let aspectAnalysis = try await aspectAnalyzer.analyzeQuery(query.prompt)
        
        // 2. Coverage Analysis
        let coverageAnalysis = try await coverageCalculator.calculateCoverage(
            pages: pages,
            query: query
        )
        
        // 3. Completeness Analysis
        let completenessAnalysis = try await completenessAnalyzer.analyzeCompleteness(
            pages: pages,
            query: query
        )
        
        // 4. Evaluate Combined Results
        let (isComplete, reason, recommendations) = evaluateResults(
            aspectAnalysis: aspectAnalysis,
            coverageAnalysis: coverageAnalysis,
            completenessAnalysis: completenessAnalysis,
            configuration: configuration
        )
        
        logger?.info("Completion analysis performed", metadata: [
            "aspectCoverage": .string(String(format: "%.2f", aspectAnalysis.complexityScore)),
            "semanticCoverage": .string(String(format: "%.2f", coverageAnalysis.score)),
            "completenessScore": .string(String(format: "%.2f", completenessAnalysis.score)),
            "isComplete": .string("\(isComplete)"),
            "reason": .string(reason)
        ])
        
        return CompletionAnalysis(
            aspectAnalysis: aspectAnalysis,
            coverageAnalysis: coverageAnalysis,
            completenessAnalysis: completenessAnalysis,
            isComplete: isComplete,
            reason: reason,
            recommendations: recommendations
        )
    }
    
    /// Evaluates combined results to determine completion
    private func evaluateResults(
        aspectAnalysis: AspectAnalyzer.Analysis,
        coverageAnalysis: SemanticCoverageCalculator.Coverage,
        completenessAnalysis: InformationCompletenessAnalyzer.CompletenessResult,
        configuration: Configuration
    ) -> (isComplete: Bool, reason: String, recommendations: [String]) {
        var recommendations: [String] = []
        
        // Check aspect coverage
        let hasAspectCoverage = aspectAnalysis.complexityScore >= configuration.minimumAspectCoverage
        if !hasAspectCoverage {
            recommendations.append("Need more coverage of critical aspects: \(aspectAnalysis.criticalAspects.map { $0.description }.joined(separator: ", "))")
        }
        
        // Check semantic coverage
        let hasSemanticCoverage = coverageAnalysis.score >= configuration.minimumSemanticCoverage
        if !hasSemanticCoverage {
            recommendations.append("Need more information about: \(coverageAnalysis.missingInfoTypes.joined(separator: ", "))")
        }
        
        // Check completeness
        let isComplete = completenessAnalysis.isComplete &&
        completenessAnalysis.score >= configuration.minimumCompletenessScore
        
        // Determine completion status and reason
        if isComplete && hasAspectCoverage && hasSemanticCoverage {
            return (
                true,
                "Sufficient coverage and completeness achieved",
                recommendations
            )
        }
        
        // If information convergence is detected
        if completenessAnalysis.metrics.recentGainTrend.suffix(configuration.confirmationCount).allSatisfy({ $0 < 0.1 }) {
            return (
                true,
                "Information convergence detected",
                recommendations
            )
        }
        
        // If we have high coverage but missing some aspects
        if hasSemanticCoverage && !hasAspectCoverage {
            return (
                false,
                "Missing coverage of some critical aspects",
                recommendations
            )
        }
        
        // If we have good aspect coverage but low semantic coverage
        if hasAspectCoverage && !hasSemanticCoverage {
            return (
                false,
                "Need more detailed information",
                recommendations
            )
        }
        
        return (
            false,
            "Continuing information collection",
            recommendations
        )
    }
    
    /// Creates an analysis result indicating incomplete crawling
    private func createIncompleteAnalysis(reason: String) -> CompletionAnalysis {
        CompletionAnalysis(
            aspectAnalysis: .init(
                query: "",
                aspects: [],
                primaryFocus: [],
                complexityScore: 0
            ),
            coverageAnalysis: .init(
                score: 0,
                aspectCoverage: [:],
                gaps: [],
                coveredKnowledge: [],
                missingInfoTypes: []
            ),
            completenessAnalysis: .init(
                score: 0,
                aspectAnalysis: .init(
                    query: "",
                    aspects: [],
                    primaryFocus: [],
                    complexityScore: 0
                ),
                coverageAnalysis: .init(
                    score: 0,
                    aspectCoverage: [:],
                    gaps: [],
                    coveredKnowledge: [],
                    missingInfoTypes: []
                ),
                isComplete: false,
                metrics: .init(
                    aspectsCovered: 0,
                    totalAspects: 0,
                    relevantSources: 0,
                    criticalAspectsCoverage: 0,
                    recentGainTrend: []
                ),
                reasoning: reason
            ),
            isComplete: false,
            reason: reason,
            recommendations: ["Continue collecting initial information"]
        )
    }
}
