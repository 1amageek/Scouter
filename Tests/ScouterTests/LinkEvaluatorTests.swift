//
//  LinkEvaluatorTests.swift
//  Scouter
//
//  Created by Norikazu Muramoto on 2024/11/10.
//

import Testing
@testable import Scouter
import Foundation
import OllamaKit
import Logging
import Selenops


@Test("Link evaluator correctly prioritizes iPhone related links for iPhone query")
func testLinkEvaluation() async throws {
    let links: Set<Crawler.Link> = [
        Crawler.Link(url: URL(string: "https://example.com/article1")!, title: "iPhone Pro"),
        Crawler.Link(url: URL(string: "https://example.com/article2")!, title: "iPad Pro"),
        Crawler.Link(url: URL(string: "https://example.com/article3")!, title: "MacBook Pro")
    ]
    let query = "iPhoneの画面サイズが知りたい。"
    let currentUrl = URL(string: "https://example.com")!
    let linkEvaluator = LinkEvaluator()
    
    let evaluations = try await linkEvaluator.evaluate(links: links, query: query, currentUrl: currentUrl)
    
    // Check that evaluations are returned
    #expect(!evaluations.isEmpty, "Evaluations should not be empty")
    
    // Check that iPhone-related articles have high priority
    let iPhoneEvaluation = try #require(evaluations.first { $0.title == "iPhone Pro" })
    #expect(iPhoneEvaluation.priority >= .high, "iPhone article should have high or critical priority")
    
    // Check that iPad and MacBook have medium or lower priority
    let iPadEvaluation = try #require(evaluations.first { $0.title == "iPad Pro" })
    #expect(iPadEvaluation.priority <= .medium, "iPad article should have medium or lower priority")
    
    let macBookEvaluation = try #require(evaluations.first { $0.title == "MacBook Pro" })
    #expect(macBookEvaluation.priority <= .medium, "MacBook article should have medium or lower priority")
    
    // Check that reasoning is provided for each evaluation
    for evaluation in evaluations {
        #expect(!evaluation.reasoning.isEmpty, "Reasoning should not be empty for \(evaluation.title)")
    }
}

@Test("Link evaluator handles empty link set")
func testEmptyLinkSet() async throws {
    let links: Set<Crawler.Link> = []
    let query = "search query"
    let currentUrl = URL(string: "https://example.com")!
    let linkEvaluator = LinkEvaluator()
    
    let evaluations = try await linkEvaluator.evaluate(links: links, query: query, currentUrl: currentUrl)
    #expect(evaluations.isEmpty, "Empty link set should result in empty evaluations")
}

@Test("Link evaluator respects configuration settings")
func testConfigurationSettings() async throws {
    let config = LinkEvaluator.Configuration(
        model: "different-model:latest",
        batchSize: 5,
        systemPrompt: "Custom prompt",
        contextTemplate: "Custom template",
        retryCount: 3
    )
    
    let links: Set<Crawler.Link> = [
        Crawler.Link(url: URL(string: "https://example.com/test")!, title: "Test Link")
    ]
    let query = "test query"
    let currentUrl = URL(string: "https://example.com")!
    let linkEvaluator = LinkEvaluator(configuration: config)
    
    let evaluations = try await linkEvaluator.evaluate(links: links, query: query, currentUrl: currentUrl)
    #expect(!evaluations.isEmpty, "Evaluator should work with custom configuration")
}

@Test("Link evaluator handles retries on failure")
func testRetryMechanism() async throws {
    let config = LinkEvaluator.Configuration(retryCount: 2)
    let links: Set<Crawler.Link> = [
        Crawler.Link(url: URL(string: "https://example.com/test")!, title: "Test Link")
    ]
    let query = "test query"
    let currentUrl = URL(string: "https://example.com")!
    let linkEvaluator = LinkEvaluator(configuration: config)
    
    do {
        let evaluations = try await linkEvaluator.evaluate(links: links, query: query, currentUrl: currentUrl)
        #expect(!evaluations.isEmpty, "Evaluator should complete successfully after retries")
    } catch {
        if case let LinkEvaluatorError.decodingFailed(attempt, maxAttempts, _) = error {
            #expect(attempt == maxAttempts, "Should retry specified number of times")
        }
    }
}
