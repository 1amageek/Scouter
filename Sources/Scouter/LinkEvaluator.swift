//
//  LinkEvaluator.swift
//  Scouter
//
//  Created by Norikazu Muramoto on 2024/11/10.
//

import Foundation
import OllamaKit
import Logging
import Selenops

/// Service responsible for evaluating links using LLM
public actor LinkEvaluator {
    /// Configuration for link evaluation
    public struct Configuration {
        /// Model to use for evaluation
        public let model: String
        
        /// Maximum number of links to evaluate in one batch
        public let batchSize: Int
        
        public let systemPrompt: String
        
        public let contextTemplate: String
        
        /// Number of times to retry evaluation on failure
        public let retryCount: Int
        
        public init(
            model: String = "llama3.2:latest",
            batchSize: Int = 10,
            systemPrompt: String? = nil,
            contextTemplate: String? = nil,
            retryCount: Int = 5
        ) {
            self.model = model
            self.batchSize = batchSize
            self.systemPrompt = systemPrompt ?? Self.defaultInstruction
            self.contextTemplate = contextTemplate ?? Self.defaultContextTemplate
            self.retryCount = retryCount
        }
        
        static let defaultInstruction: String =  """
        You are an AI assistant. Follow the user's request and respond accordingly. If an output format is specified, strictly adhere to that format.
        """
        
        static let defaultContextTemplate = """
        Your task is to evaluate a set of links extracted from HTML and assess their relevance and importance to the user's question.
        
        **Context:**
        
        - **Request**: The user's question.
        - **CurrentURL**: The URL of the current page.
        - **Links**: A list of links extracted from HTML, displayed in markdown format. Each link contains a title that should be extracted from the markdown format.
        
        **Instructions:**
        
        1. Analyze the provided "Links" in relation to "Request" and "CurrentURL."
        2. For each link, evaluate its priority ("High," "Medium," or "Low") based on its relevance to "Request."
        3. Clearly provide reasoning for the assigned priority of each link.
        4. Ensure that every link in the provided list is processed and converted into the specified JSON format.
        
        **Input:**
        ```
        Request: 
        {{query}}
        
        CurrentURL: 
        {{currentUrl}}
        
        Links: 
        // Markdown format: [title](url)
        {{links}}
        ```
        
        **Output Format:**
        
        Output the evaluation results strictly in the following JSON format:
        
        ```json
        {
        "evaluations": [
        {
            "url": "string",          // The link address
            "title": "string",        // The extracted title of the link
            "priority": "High" | "Medium" | "Low", // Priority level
            "reasoning": "string"     // Reason for the assigned priority
        }
        ]
        }
        ```
        
        **Guidelines:**
        
        Include only links that are relevant to "Request."
        Do not include any additional explanations or content outside the specified JSON format.
        Non-JSON output is not permitted.
        Avoid unverified information and speculation; include only accurate information.        
        """
    }
    
    private let configuration: Configuration
    private let ollamaKit: OllamaKit
    private let logger: Logger?
    
    /// Initializes a new link evaluator
    public init(configuration: Configuration = .init(), logger: Logger? = nil) {
        self.configuration = configuration
        self.ollamaKit = OllamaKit()
        self.logger = logger
    }
    
    /// Evaluates a set of links against a query
    /// - Parameters:
    ///   - links: Links to evaluate
    ///   - query: Search query
    ///   - currentUrl: URL where links were found
    /// - Returns: Array of link evaluations
    public func evaluate(
        links: Set<Crawler.Link>,
        query: String,
        currentUrl: URL
    ) async throws -> [LinkEvaluation] {
        // Skip if no links to evaluate
        guard !links.isEmpty else { return [] }
        
        // Prepare context for evaluation
        let context = prepareContext(
            links: links,
            query: query,
            currentUrl: currentUrl
        )
                
        // Get LLM evaluation with retry logic
        let response = try await getLLMEvaluation(context: context)
        
        // Convert responses to LinkEvaluations
        return response.evaluations.compactMap { evaluation in
            LinkEvaluation.fromLLMResponse(evaluation)
        }
    }
    
    /// Prepares context for LLM evaluation
    private func prepareContext(
        links: Set<Crawler.Link>,
        query: String,
        currentUrl: URL
    ) -> String {
        // Format links into readable format
        let linksText = links
            .map { "[\($0.title)](\($0.url))" }
            .joined(separator: "\n")
        
        // Replace placeholders in template
        return configuration.contextTemplate
            .replacingOccurrences(of: "{{query}}", with: query)
            .replacingOccurrences(of: "{{currentUrl}}", with: currentUrl.absoluteString)
            .replacingOccurrences(of: "{{links}}", with: linksText)
    }
    
    private func getLLMEvaluation(context: String) async throws -> LinkEvaluation.LLMResponse {
        let data = OKChatRequestData(
            model: configuration.model,
            messages: [
                .system(configuration.systemPrompt),
                .user(context)
            ]
        )
        
        let logger = logger
                        
        return try await withRetry(maxAttempts: configuration.retryCount, logger: logger) {
            var response = ""
            do {
                for try await chunk in self.ollamaKit.chat(data: data) {
                    response += chunk.message?.content ?? ""
                }
                
                let result = response.extracted()
                logger?.debug("LinkEvaluator: Received response from LLM", metadata: [
                    "source": .string("LinkEvaluator.getLLMEvaluation"),
                    "responseLength": .string("\(result.count)"),
                    "model": .string(self.configuration.model)
                ])
                
                do {
                    let decoder = JSONDecoder()
                    return try decoder.decode(LinkEvaluation.LLMResponse.self, from: result.data(using: .utf8)!)
                } catch {
                    logger?.error("LinkEvaluator: JSON decoding failed", metadata: [
                        "source": .string("LinkEvaluator.getLLMEvaluation"),
                        "error": .string(error.localizedDescription),
                        "response": .string(result),
                        "model": .string(self.configuration.model)
                    ])
                    throw error
                }
            } catch {
                logger?.error("LinkEvaluator: LLM chat failed", metadata: [
                    "source": .string("LinkEvaluator.getLLMEvaluation"),
                    "error": .string(error.localizedDescription),
                    "model": .string(self.configuration.model)
                ])
                throw error
            }
        }
    }
    
    // Retry function with customizable retry logic
    private func withRetry<T: Sendable>(
        maxAttempts: Int,
        logger: Logger?,
        action: @escaping () async throws -> T
    ) async throws -> T {
        var attempt = 0
        var lastError: Error?
        
        while attempt < maxAttempts {
            do {
                return try await action()
            } catch {
                attempt += 1
                lastError = error
                
                logger?.warning("LinkEvaluator: Retry attempt failed", metadata: [
                    "source": .string("LinkEvaluator.withRetry"),
                    "attempt": .string("\(attempt)"),
                    "maxAttempts": .string("\(maxAttempts)"),
                    "error": .string(error.localizedDescription)
                ])
                
                if attempt >= maxAttempts {
                    logger?.error("LinkEvaluator: Max retry attempts exceeded", metadata: [
                        "source": .string("LinkEvaluator.withRetry"),
                        "attempts": .string("\(attempt)"),
                        "maxAttempts": .string("\(maxAttempts)"),
                        "finalError": .string(error.localizedDescription)
                    ])
                    throw LinkEvaluatorError.decodingFailed(
                        attempt: attempt,
                        maxAttempts: maxAttempts,
                        underlyingError: lastError
                    )
                }
            }
        }
        
        throw LinkEvaluatorError.unexpectedError
    }
}


/// Custom error type for LinkEvaluator
public enum LinkEvaluatorError: Error, LocalizedError {
    case decodingFailed(attempt: Int, maxAttempts: Int, underlyingError: Error?)
    case unexpectedError
    
    public var errorDescription: String? {
        switch self {
        case .decodingFailed(let attempt, let maxAttempts, let underlyingError):
            var description = "Failed to decode LLM response. Attempt \(attempt) of \(maxAttempts)."
            if let underlyingError = underlyingError {
                description += " Underlying error: \(underlyingError.localizedDescription)"
            }
            return description
        case .unexpectedError:
            return "An unexpected error occurred in LinkEvaluator."
        }
    }
}
