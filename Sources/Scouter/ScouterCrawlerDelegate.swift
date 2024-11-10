//
//  ScouterCrawlerDelegate.swift
//  Scouter
//
//  Created by Norikazu Muramoto on 2024/11/10.
//

import Foundation
import Selenops
import SwiftSoup
import OllamaKit
import Remark
import Logging

public actor ScouterCrawlerDelegate: CrawlerDelegate {
    // MARK: - Properties
    
    private let query: Scouter.Query
    private let options: Scouter.Options
    private let logger: Logger?
    private var pagesToVisit: Set<PageToVisit> = []
    private var evaluatedLinks: Set<EvaluatedLink> = []
    private var visitedPages: [VisitedPage] = []
    private var answer: Scouter.Answer?
    private let ollamaKit: OllamaKit
    private let linkEvaluator: LinkEvaluator
    /// Completion analyzer for determining when to stop crawling
    private let completionAnalyzer: CrawlCompletionAnalyzer
    
    /// Configuration for completion analysis
    private let completionConfiguration: CrawlCompletionAnalyzer.Configuration
    
    /// Counter for pages processed since last analysis
    private var pagesSinceLastAnalysis: Int = 0
    
    /// Number of consecutive completion confirmations
    private var completionConfirmations: Int = 0
    
    // MARK: - Initialization
    
    init(query: Scouter.Query, options: Scouter.Options, logger: Logger?) {
        self.query = query
        self.options = options
        self.logger = logger
        self.ollamaKit = OllamaKit()
        self.linkEvaluator = LinkEvaluator(
            configuration: .init(model: options.model),
            logger: logger
        )
        self.completionAnalyzer = CrawlCompletionAnalyzer(
            model: options.model,
            logger: logger
        )
        self.completionConfiguration = CrawlCompletionAnalyzer.Configuration(
            minimumAspectCoverage: options.similarityThreshold,
            minimumSemanticCoverage: options.similarityThreshold,
            minimumCompletenessScore: options.similarityThreshold,
            confirmationCount: 3,
            analysisInterval: 5
        )
    }
    
    // MARK: - Public Interface
    
    public func getVisitedPages() -> [VisitedPage] {
        visitedPages
    }
    
    public func getAnswer() -> Scouter.Answer? {
        answer
    }
    
    // MARK: - CrawlerDelegate
    
    public func crawler(_ crawler: Crawler, shouldVisitUrl url: URL) -> Crawler.Decision {
        guard url.scheme?.hasPrefix("http") == true else {
            logger?.debug("ScouterCrawlerDelegate: Skipping non-HTTP URL", metadata: [
                "source": .string("ScouterCrawlerDelegate.shouldVisitUrl"),
                "url": .string(url.absoluteString)
            ])
            return .skip(.invalidURL)
        }
        
        let skipExtensions = [".pdf", ".zip", ".jpg", ".png", ".gif", ".mp4", ".mp3"]
        if skipExtensions.contains(where: { url.lastPathComponent.lowercased().hasSuffix($0) }) {
            logger?.debug("ScouterCrawlerDelegate: Skipping unsupported file type", metadata: [
                "source": .string("ScouterCrawlerDelegate.shouldVisitUrl"),
                "url": .string(url.absoluteString),
                "fileType": .string(url.pathExtension)
            ])
            return .skip(.unsupportedFileType)
        }
        
        if visitedPages.contains(where: { $0.url == url }) {
            logger?.debug("ScouterCrawlerDelegate: Skipping already visited URL", metadata: [
                "source": .string("ScouterCrawlerDelegate.shouldVisitUrl"),
                "url": .string(url.absoluteString)
            ])
            return .skip(.businessLogic("Already visited"))
        }
        
        return .visit
    }
    
    public func crawler(_ crawler: Crawler) async -> URL? {
        guard visitedPages.count < options.maxPages else {
            logger?.info("ScouterCrawlerDelegate: Reached maximum pages limit", metadata: [
                "source": .string("ScouterCrawlerDelegate.crawler"),
                "maxPages": .string("\(options.maxPages)"),
                "visitedPages": .string("\(visitedPages.count)")
            ])
            return nil
        }
        
        // Perform completion analysis if needed
        pagesSinceLastAnalysis += 1
        if pagesSinceLastAnalysis >= completionConfiguration.analysisInterval {
            pagesSinceLastAnalysis = 0
            
            do {
                let analysis = try await completionAnalyzer.shouldComplete(
                    pages: visitedPages,
                    query: query,
                    configuration: completionConfiguration
                )
                
                if analysis.isComplete {
                    completionConfirmations += 1
                    
                    logger?.info("Completion analysis suggests stopping", metadata: [
                        "reason": .string(analysis.reason),
                        "confirmations": .string("\(completionConfirmations)"),
                        "required": .string("\(completionConfiguration.confirmationCount)")
                    ])
                    
                    // Stop if we have enough confirmations
                    if completionConfirmations >= completionConfiguration.confirmationCount {
                        logger?.info("Crawling complete", metadata: [
                            "reason": .string(analysis.reason),
                            "visitedPages": .string("\(visitedPages.count)"),
                            "recommendations": .string(analysis.recommendations.joined(separator: "; "))
                        ])
                        return nil
                    }
                } else {
                    completionConfirmations = 0
                    
                    // Log recommendations for improving coverage
                    logger?.debug("Completion analysis recommendations", metadata: [
                        "recommendations": .string(analysis.recommendations.joined(separator: "; "))
                    ])
                }
            } catch {
                logger?.error("Error during completion analysis", metadata: [
                    "error": .string(error.localizedDescription)
                ])
                // Continue crawling on analysis error
            }
        }
        
        // Get highest scoring unvisited page
        return pagesToVisit
            .filter { page in
                !visitedPages.contains(where: { $0.url == page.url })
            }
            .max(by: { $0.score < $1.score })?
            .url
    }
    
    public func crawler(_ crawler: Crawler, willVisitUrl url: URL) {
        // Nothing to do
    }
    
    public func crawler(_ crawler: Crawler, didFetchContent content: String, at url: URL) async {
        do {
            let remark = try Remark(content)
            
            // Generate embedding for the content
            let data = OKEmbeddingsRequestData(model: options.model, prompt: remark.body)
            let response = try await ollamaKit.embeddings(data: data)
            
            // Calculate similarity
            let similarity = VectorSimilarity.cosineSimilarity(
                query.embedding,
                response.embedding!
            )
            
            let isRelevant = similarity >= options.similarityThreshold
            var summary: String? = nil
            
            if isRelevant {
                summary = try await summarizeContent(content: remark.body)
            }
            
            // Create metadata
            let metadata = PageMetadata(
                description: remark.description,
                keywords: [], // Could be extracted from content if needed
                ogData: remark.ogData,
                lastModified: nil,
                contentHash: String(content.hash)
            )
            
            // Create visited page record
            let visitedPage = VisitedPage(
                url: url,
                title: remark.title,
                content: remark.body,
                embedding: response.embedding!,
                similarity: similarity,
                summary: summary,
                isRelevant: isRelevant,
                metadata: metadata
            )
            
            visitedPages.append(visitedPage)
            logger?.info("ScouterCrawlerDelegate: Processed page", metadata: [
                "source": .string("ScouterCrawlerDelegate.didFetchContent"),
                "url": .string(url.absoluteString),
                "similarity": .string(String(format: "%.4f", similarity)),
                "isRelevant": .string("\(isRelevant)"),
                "contentLength": .string("\(remark.body.count)")
            ])
            
            // Update or remove from pagesToVisit
            if let pageToVisit = pagesToVisit.first(where: { $0.url == url }) {
                pagesToVisit.remove(pageToVisit)
            }
            
        } catch {
            logger?.error("ScouterCrawlerDelegate: Error processing content", metadata: [
                "source": .string("ScouterCrawlerDelegate.didFetchContent"),
                "url": .string(url.absoluteString),
                "error": .string(error.localizedDescription)
            ])
        }
    }
    
    public func crawler(_ crawler: Crawler, didFindLinks links: Set<Crawler.Link>, at url: URL) async {
        do {
            guard !links.isEmpty else { return }
            
            logger?.debug("ScouterCrawlerDelegate: Processing discovered links", metadata: [
                "source": .string("ScouterCrawlerDelegate.didFindLinks"),
                "url": .string(url.absoluteString),
                "linkCount": .string("\(links.count)")
            ])
            
            let unevaluatedLinks = links.filter { link in
                !evaluatedLinks.contains(where: { $0.url == link.url }) &&
                !pagesToVisit.contains(where: { $0.url == link.url }) &&
                !visitedPages.contains(where: { $0.url == link.url })
            }
            
            guard !unevaluatedLinks.isEmpty else {
                logger?.debug("ScouterCrawlerDelegate: All links already evaluated", metadata: [
                    "source": .string("ScouterCrawlerDelegate.didFindLinks"),
                    "url": .string(url.absoluteString)
                ])
                return
            }
            
            // First pass: Calculate embeddings and filter by similarity
            let linkWithSimilarities: Set<LinkWithSimilarity> = await getLinkWithSimilarities(unevaluatedLinks)
            let highSimilarityLinks: Set<LinkWithSimilarity> = linkWithSimilarities
                .filter({ $0.similarity >= options.similarityThreshold })
            
            linkWithSimilarities.forEach { link in
                evaluatedLinks
                    .insert(
                        .init(
                            url: link.link.url,
                            title: link.link.title,
                            similarity: link.similarity
                        )
                    )
            }
            
            guard !highSimilarityLinks.isEmpty else {
                logger?.debug("ScouterCrawlerDelegate: No high similarity links found", metadata: [
                    "source": .string("ScouterCrawlerDelegate.didFindLinks"),
                    "url": .string(url.absoluteString)
                ])
                return
            }
            
            // Second pass: Evaluate filtered links in chunks
            let evaluations = try await evaluateLinksInChunks(
                highSimilarityLinks: highSimilarityLinks,
                query: query.prompt,
                url: url
            )
            
            evaluations.forEach { link in
                print(
                    "[evaluations]",
                    link.priority,
                    link.title,
                    link.reasoning,
                    link.url
                )
            }
            
            // Process evaluations and add to visit queue
            for evaluation in evaluations {
                // Find corresponding similarity score
                guard let linkWithSimilarity: LinkWithSimilarity = highSimilarityLinks.first(where: { $0.link.url == evaluation.url }) else {
                    continue
                }
                
                let pageToVisit = PageToVisit(
                    from: linkWithSimilarity.link,
                    priority: evaluation.priority,
                    similarity: linkWithSimilarity.similarity
                )
                
                if pageToVisit.priority >= .medium {
                    pagesToVisit.insert(pageToVisit)
                    logger?.debug("ScouterCrawlerDelegate: Added page to visit queue", metadata: [
                        "source": .string("ScouterCrawlerDelegate.didFindLinks"),
                        "url": .string(evaluation.url.absoluteString),
                        "priority": .string("\(evaluation.priority)"),
                        "similarity": .string(String(format: "%.4f", linkWithSimilarity.similarity)),
                        "title": .string(evaluation.title)
                    ])
                }
            }
            
        } catch {
            logger?.error("ScouterCrawlerDelegate: Error processing links", metadata: [
                "source": .string("ScouterCrawlerDelegate.didFindLinks"),
                "url": .string(url.absoluteString),
                "error": .string(error.localizedDescription)
            ])
        }
    }
    
    private func evaluateLinksInChunks(
        highSimilarityLinks: Set<LinkWithSimilarity>,
        query: String,
        url: URL
    ) async throws -> [LinkEvaluation] {
        var allEvaluations: [LinkEvaluation] = []
        let links = Array(highSimilarityLinks)
        
        // Process links in chunks
        for chunk in links.chunks(of: options.evaluateLinksChunkSize) {
            let chunkLinks = Set(chunk.map { $0.link })
            
            logger?.debug("Processing link evaluation chunk", metadata: [
                "source": .string("ScouterCrawlerDelegate.evaluateLinksInChunks"),
                "chunkSize": .string("\(chunkLinks.count)"),
                "totalProcessed": .string("\(allEvaluations.count)"),
                "remainingChunks": .string("\((links.count - allEvaluations.count) / options.evaluateLinksChunkSize)")
            ])
            
            do {
                let chunkEvaluations = try await linkEvaluator.evaluate(
                    links: chunkLinks,
                    query: query,
                    currentUrl: url
                )
                
                allEvaluations.append(contentsOf: chunkEvaluations)
            } catch {
                logger?.error("Error evaluating link chunk", metadata: [
                    "error": .string(error.localizedDescription),
                    "chunkSize": .string("\(chunkLinks.count)")
                ])
                // Continue processing remaining chunks even if one fails
                continue
            }
        }
        
        return allEvaluations
    }
    
    // Helper struct to keep link and its similarity score together
    private struct LinkWithSimilarity: Hashable {
        let link: Crawler.Link
        let similarity: Float
    }
    
    private func getLinkWithSimilarities(_ links: Set<Crawler.Link>) async -> Set<LinkWithSimilarity> {
        var linkWithSimilarities: Set<LinkWithSimilarity> = []
        
        for link in links {
            // Skip if already visited or queued
            guard !visitedPages.contains(where: { $0.url == link.url }) else { continue }
            guard !pagesToVisit.contains(where: { $0.url == link.url }) else { continue }
            
            if let similarity = await calculateSimilarity(text: link.title) {
                linkWithSimilarities.insert(LinkWithSimilarity(link: link, similarity: similarity))
                logger?.debug("ScouterCrawlerDelegate: Link similarity calculated", metadata: [
                    "source": .string("ScouterCrawlerDelegate.filterLinksBySimilarity"),
                    "url": .string(link.url.absoluteString),
                    "title": .string(link.title),
                    "similarity": .string(String(format: "%.4f", similarity))
                ])
            }
        }
        
        return linkWithSimilarities
    }
    
    public func crawler(_ crawler: Crawler, didVisit url: URL) async {
        // Update visit count or remove from pagesToVisit if necessary
        if let pageToVisit = pagesToVisit.first(where: { $0.url == url }) {
            pagesToVisit.remove(pageToVisit)
            let updatedPage = PageToVisit(
                url: pageToVisit.url,
                title: pageToVisit.title,
                visitCount: pageToVisit.visitCount + 1,
                similarity: pageToVisit.similarity,
                priority: pageToVisit.priority
            )
            pagesToVisit.insert(updatedPage)
            
            logger?.debug("ScouterCrawlerDelegate: Updated visit count", metadata: [
                "source": .string("ScouterCrawlerDelegate.didVisit"),
                "url": .string(url.absoluteString),
                "visitCount": .string("\(updatedPage.visitCount)")
            ])
        }
    }
    
    public func crawler(_ crawler: Crawler, didSkip url: URL, reason: Crawler.SkipReason) async {
        // Remove skipped URL from pagesToVisit if present
        if let pageToVisit = pagesToVisit.first(where: { $0.url == url }) {
            pagesToVisit.remove(pageToVisit)
            
            logger?.debug("ScouterCrawlerDelegate: Removed skipped URL from visit queue", metadata: [
                "source": .string("ScouterCrawlerDelegate.didSkip"),
                "url": .string(url.absoluteString),
                "reason": .string("\(reason)")
            ])
        }
        
        // Add to evaluated links to prevent re-evaluation
        if !evaluatedLinks.contains(where: { $0.url == url }) {
            let evaluatedLink = EvaluatedLink(
                url: url,
                title: "", // Empty title for skipped links
                similarity: 0, // Zero similarity for skipped links
                evaluation: nil, // No evaluation for skipped links
                evaluatedAt: Date()
            )
            evaluatedLinks.insert(evaluatedLink)
            logger?.debug("ScouterCrawlerDelegate: Added skipped URL to evaluated links", metadata: [
                "source": .string("ScouterCrawlerDelegate.didSkip"),
                "url": .string(url.absoluteString)
            ])
        }
        
        logger?.debug("ScouterCrawlerDelegate: Skipped URL", metadata: [
            "source": .string("ScouterCrawlerDelegate.didSkip"),
            "url": .string(url.absoluteString),
            "reason": .string("\(reason)"),
            "remainingToVisit": .string("\(pagesToVisit.count)"),
            "evaluatedLinks": .string("\(evaluatedLinks.count)")
        ])
    }
    
    // MARK: - Private Methods
    
    private func calculateRelevanceScore(title: String) async throws -> Float {
        let embedding = try await VectorSimilarity.getEmbedding(
            for: title,
            model: self.options.model
        )
        let similarity = VectorSimilarity.cosineSimilarity(query.embedding, embedding)
        
        logger?.debug("ScouterCrawlerDelegate: Calculated relevance score", metadata: [
            "source": .string("ScouterCrawlerDelegate.calculateRelevanceScore"),
            "title": .string(title),
            "similarity": .string(String(format: "%.4f", similarity))
        ])
        
        return similarity
    }
    
    private func summarizeContent(content: String) async throws -> String {
        let data = OKChatRequestData(
            model: options.model,
            messages: [
                OKChatRequestData.Message(role: .system, content: "Summarize the content in relation to the query. Be concise and specific."),
                OKChatRequestData.Message(role: .user, content: """
                    Query: 
                    \(query.prompt)
                    
                    Content: 
                    \(content)
                    
                    Provide a relevant summary:
                    """)
            ]
        )
        
        var summary = ""
        for try await chunk in ollamaKit.chat(data: data) {
            summary += chunk.message?.content ?? ""
        }
        
        logger?.debug("ScouterCrawlerDelegate: Generated content summary", metadata: [
            "source": .string("ScouterCrawlerDelegate.summarizeContent"),
            "summaryLength": .string("\(summary.count)")
        ])
        
        return summary
    }
}

extension ScouterCrawlerDelegate {
    
    private func calculateEmbedding(for text: String) async throws -> [Float]? {
        let data = OKEmbeddingsRequestData(
            model: options.model,
            prompt: text
        )
        let response = try await ollamaKit.embeddings(data: data)
        return response.embedding
    }
    
    private func calculateSimilarity(text: String) async -> Float? {
        do {
            guard let embedding = try await calculateEmbedding(for: text) else {
                return nil
            }
            
            return VectorSimilarity.cosineSimilarity(
                query.embedding,
                embedding
            )
        } catch {
            logger?.error("Error calculating similarity", metadata: [
                "source": .string("ScouterCrawlerDelegate.calculateSimilarity"),
                "text": .string(text),
                "error": .string(error.localizedDescription)
            ])
            return nil
        }
    }
}

extension ScouterCrawlerDelegate {
    /// Generates a comprehensive answer from collected pages
    public func crawlerDidFinish(_ crawler: Crawler) async {
        logger?.info("ScouterCrawlerDelegate: Crawling finished", metadata: [
            "source": .string("ScouterCrawlerDelegate.crawlerDidFinish"),
            "visitedPages": .string("\(visitedPages.count)"),
            "remainingPages": .string("\(pagesToVisit.count)")
        ])
        
        do {
            // 1. Analyze collected information completeness
            let completionAnalysis = try await completionAnalyzer.shouldComplete(
                pages: visitedPages,
                query: query,
                configuration: completionConfiguration
            )
            
            // 2. Select relevant pages for answer generation
            let relevantPages = selectRelevantPages(analysis: completionAnalysis)
            
            // 3. Generate final answer
            let answer = try await generateAnswer(
                pages: relevantPages,
                query: query,
                analysis: completionAnalysis
            )
            
            logger?.info("Answer generated successfully", metadata: [
                "relevantPages": .string("\(relevantPages.count)"),
                "answerLength": .string("\(answer.length)")
            ])
            
            // Store or process the answer as needed
            self.answer = answer
            
        } catch {
            logger?.error("Error generating answer", metadata: [
                "error": .string(error.localizedDescription)
            ])
        }
    }
    
    /// Selects most relevant pages for answer generation
    private func selectRelevantPages(
        analysis: CrawlCompletionAnalyzer.CompletionAnalysis
    ) -> [VisitedPage] {
        // Filter relevant pages and sort by similarity
        let relevantPages = visitedPages
            .filter { page in
                page.isRelevant && page.similarity >= options.similarityThreshold
            }
            .sorted { $0.similarity > $1.similarity }
        
        // Ensure source diversity by selecting top pages from different domains
        var selectedPages: [VisitedPage] = []
        var seenDomains: Set<String> = []
        
        for page in relevantPages {
            let domain = page.url.host ?? ""
            if !seenDomains.contains(domain) {
                selectedPages.append(page)
                seenDomains.insert(domain)
            }
            
            // Limit to reasonable number of sources
            if selectedPages.count >= 5 {
                break
            }
        }
        
        return selectedPages
    }
    
    /// Generates comprehensive answer from selected pages
    private func generateAnswer(
        pages: [VisitedPage],
        query: Scouter.Query,
        analysis: CrawlCompletionAnalyzer.CompletionAnalysis
    ) async throws -> Scouter.Answer {
        // 1. Prepare context for answer generation
        let context = try await prepareAnswerContext(
            pages: pages,
            query: query,
            analysis: analysis
        )
        
        // 2. Generate answer using LLM
        let answerId = UUID().uuidString
        logger?.debug("Starting answer generation", metadata: [
            "answerId": .string(answerId),
            "contextLength": .string("\(context.count)")
        ])
        
        let data = OKChatRequestData(
            model: options.model,
            messages: [
                OKChatRequestData.Message(
                    role: .system,
                    content: """
                    You are an expert answer generator. Using the provided information:
                    1. Create a comprehensive, accurate answer
                    2. Focus on relevant information
                    3. Maintain logical flow
                    4. Cite sources appropriately
                    5. Indicate confidence level
                    """
                ),
                OKChatRequestData.Message(
                    role: .user,
                    content: """
                    Query: \(query.prompt)
                    
                    Available Information:
                    \(context)
                    
                    Generate a comprehensive answer in the following JSON format:
                    {
                        "answer": "detailed answer text",
                        "confidence": float between 0 and 1,
                        "sources": [
                            {
                                "url": "source URL",
                                "title": "source title",
                                "relevance": float between 0 and 1,
                                "snippet": "relevant quote or summary"
                            }
                        ]
                    }
                    """
                )
            ]
        ) { options in
            options.temperature = 0
            options.topP = 1
            options.topK = 1
        }
        
        // 3. Collect and parse response
        var response = ""
        for try await chunk in ollamaKit.chat(data: data) {
            response += chunk.message?.content ?? ""
        }
        
        // 4. Parse JSON response
        let decoder = JSONDecoder()
        let jsonData = response.data(using: .utf8)!
        let result = try decoder.decode(AnswerResponse.self, from: jsonData)
        
        // 5. Calculate answer metrics
        let metrics = calculateAnswerMetrics(
            sources: result.sources,
            pages: pages,
            analysis: analysis
        )
        
        // 6. Create final answer structure
        return Scouter.Answer(
            content: result.answer,
            sources: result.sources.map { source in
                Scouter.Answer.Source(
                    url: URL(string: source.url)!,
                    title: source.title,
                    relevance: source.relevance,
                    snippet: source.snippet
                )
            },
            confidence: result.confidence,
            metrics: metrics
        )
    }
    
    /// Prepares context for answer generation
    private func prepareAnswerContext(
        pages: [VisitedPage],
        query: Scouter.Query,
        analysis: CrawlCompletionAnalyzer.CompletionAnalysis
    ) async throws -> String {
        var context = ""
        
        // Add coverage information
        context += "Information Coverage:\n"
        context += "- Overall coverage: \(analysis.coverageAnalysis.score)\n"
        if !analysis.coverageAnalysis.gaps.isEmpty {
            let gapDescriptions = analysis.coverageAnalysis.gaps.map { aspect in
                aspect.description
            }
            context += "- Gaps: \(gapDescriptions.joined(separator: ", "))\n"
        }
        
        // Add relevant content from pages
        for page in pages {
            context += "\nSource: \(page.url)\n"
            context += "Title: \(page.title)\n"
            context += "Relevance: \(page.similarity)\n"
            context += "Content Summary: \(page.summary ?? page.content)\n"
        }
        
        return context
    }
    
    /// Calculates metrics for the generated answer
    private func calculateAnswerMetrics(
        sources: [AnswerResponse.Source],
        pages: [VisitedPage],
        analysis: CrawlCompletionAnalyzer.CompletionAnalysis
    ) -> Scouter.Answer.AnswerMetrics {
        // Calculate coverage score
        let coverageScore = Float(analysis.coverageAnalysis.score)
        
        // Calculate source metrics
        let sourceCount = sources.count
        let averageSourceRelevance = sources.map(\.relevance).reduce(0, +) / Float(sourceCount)
        
        // Calculate information diversity (based on domain variety)
        let uniqueDomains = Set(sources.compactMap { URL(string: $0.url)?.host }).count
        let informationDiversity = Float(uniqueDomains) / Float(sourceCount)
        
        return Scouter.Answer.AnswerMetrics(
            coverageScore: coverageScore,
            sourceCount: sourceCount,
            averageSourceRelevance: averageSourceRelevance,
            informationDiversity: informationDiversity
        )
    }
}

extension ScouterCrawlerDelegate {
    /// Represents a link that has been evaluated for crawling
    private struct EvaluatedLink: Hashable {
        /// Basic link information
        let url: URL
        let title: String
        
        /// Similarity score from embedding comparison
        let similarity: Float
        
        /// LLM evaluation result (exists only if similarity exceeds threshold)
        let evaluation: LinkEvaluation?
        
        /// Timestamp when evaluation was performed
        let evaluatedAt: Date
        
        init(
            url: URL,
            title: String,
            similarity: Float,
            evaluation: LinkEvaluation? = nil,
            evaluatedAt: Date = Date()
        ) {
            self.url = url
            self.title = title
            self.similarity = similarity
            self.evaluation = evaluation
            self.evaluatedAt = evaluatedAt
        }
        
        // Equality comparison based on URL only
        static func == (lhs: EvaluatedLink, rhs: EvaluatedLink) -> Bool {
            return lhs.url == rhs.url
        }
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(url)
        }
    }

}

// MARK: - Supporting Types

private struct AnswerResponse: Codable {
    let answer: String
    let confidence: Float
    let sources: [Source]
    
    struct Source: Codable {
        let url: String
        let title: String
        let relevance: Float
        let snippet: String
    }
}

// Extension to support chunking arrays
extension Array {
    func chunks(of size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
