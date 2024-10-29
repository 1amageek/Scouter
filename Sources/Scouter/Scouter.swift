import Foundation
import Accelerate
import SwiftSoup
import OllamaKit
import Logging

/// The `Scouter` actor performs web content searching and link extraction based on relevance scoring.
public actor Scouter {
    
    /// Configuration options for the `Scouter` actor.
    public struct Options: Sendable {
        /// The maximum number of concurrent tasks allowed.
        public let maxTasks: Int
        
        /// The threshold for similarity score used to filter links.
        public let similarityThreshold: Double
        
        /// Creates a new instance of `Options` with specified maximum tasks and similarity threshold.
        ///
        /// - Parameters:
        ///   - maxTasks: Maximum number of concurrent tasks (default is `1`).
        ///   - similarityThreshold: Threshold for similarity score to determine link relevance (default is `0.32`).
        public init(maxTasks: Int = 1, similarityThreshold: Double = 0.32) {
            self.maxTasks = maxTasks
            self.similarityThreshold = similarityThreshold
        }
    }
    
    /// Represents a link containing a URL, title, and similarity score.
    public struct Link: Hashable, Sendable {
        /// The URL of the link.
        public var url: URL
        
        /// The title of the linked page.
        public var title: String
        
        /// The relevance score based on similarity.
        public var score: Double
    }
    
    // MARK: - Internal State Management
    
    private var links: [Link] = []
    private var readPages: Set<URL> = []
    private var currentTasks: [Task<String?, Error>] = []
    private var taskCounter: Int = 0
    
    private let ollamaKit: OllamaKit = OllamaKit()
    
    // MARK: - Public Properties
    
    /// The model identifier for embeddings and AI requests.
    public let model: String
    
    /// The options for configuring search parameters.
    public let options: Options
    
    /// Logger instance for structured logging.
    public let logger: Logging.Logger
    
    // 初期化
    init(model: String, options: Options, logger: Logging.Logger? = nil) {
        self.model = model
        self.options = options
        self.logger = logger ?? Logging.Logger(label: "Scouter")
    }
    
    // MARK: - Static Methods
    
    /// Initiates a search on the given URL with a specified prompt.
    ///
    /// - Parameters:
    ///   - model: The model identifier to use for embeddings.
    ///   - url: The URL to start the search from.
    ///   - prompt: The prompt guiding the search.
    ///   - options: The `Options` for configuring search parameters.
    ///   - logger: An optional logger for structured logging.
    ///
    /// - Returns: A string with relevant content if found, or `nil` if not.
    public static func search(model: String, url: URL, prompt: String, options: Options = .init(), logger: Logging.Logger? = nil) async throws -> String? {
        guard let scheme = url.scheme, let host = url.host, !host.isEmpty else {
            throw URLError(.badURL)
        }
        let baseURL = URL(string: "\(scheme)://\(host)")!
        let scouter = Scouter(model: model, options: options, logger: logger)
        let embedding = try await embeddings(model: model, content: prompt)
        return try await scouter.search(
            initialURL: url,
            prompt: prompt,
            embedding: embedding,
            baseURL: baseURL
        )
    }
    
    // MARK: - Instance Methods
    
    /// Performs a recursive search, starting from an initial URL and guided by a prompt.
    ///
    /// - Parameters:
    ///   - initialURL: The initial URL to start the search.
    ///   - prompt: The search prompt.
    ///   - embedding: Embedding vector for similarity comparison.
    ///   - baseURL: Base URL to resolve relative links.
    ///
    /// - Returns: A string with relevant content if found, or `nil`.
    private func search(
        initialURL: URL,
        prompt: String,
        embedding: [Double],
        baseURL: URL
    ) async throws -> String? {
        if Task.isCancelled { return nil }
        var queue: [URL] = [initialURL]
        var taskID = generateTaskId()
        
        while !queue.isEmpty {
            let url = queue.removeFirst()
            
            if Task.isCancelled { return nil }
            taskID = generateTaskId()
            logger.debug("Task \(taskID) started: URL: \(url.absoluteString)")
            
            if readPages.contains(url) { continue }
            readPages.insert(url)
            
            guard let pageContent = await fetchPageContent(url: url, taskID: taskID) else { continue }
            let doc = try SwiftSoup.parse(pageContent)
            let summary = doc.summarize()
            if try await checkContent(content: summary, prompt: prompt, taskID: taskID) {
                if let foundInfo = try await analyzeContent(content: summary, prompt: prompt, taskID: taskID) {
                    return foundInfo
                }
            }
            let content = try doc.sanitized().html()
            let links = await extractLinks(
                from: content,
                embedding: embedding,
                baseURL: baseURL,
                taskID: taskID
            )
            let sortedLinks = links.sorted { $0.score > $1.score }
            let targetLinks = try await analyzeLinks(links: sortedLinks, prompt: prompt, taskID: taskID)
            
            // Add new URLs to the queue
            for linkURL in targetLinks {
                if !readPages.contains(linkURL) {
                    queue.append(linkURL)
                }
            }
        }
        
        return nil
    }
    
    /// Fetches the content of a page for a given URL.
    ///
    /// - Parameters:
    ///   - url: The URL of the page to fetch.
    ///   - taskID: The ID of the current task for logging.
    ///
    /// - Returns: The page content as a string if successful, or `nil` if an error occurs.
    private func fetchPageContent(url: URL, taskID: Int) async -> String? {
        if Task.isCancelled { return nil }
        do {
            logger.debug("Task \(taskID) fetching page content: \(url.absoluteString)")
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 (compatible; ScouterBot/1.0)", forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: request)
            if let content = String(data: data, encoding: .utf8) {
                logger.debug("Task \(taskID) page content fetched")
                return content
            }
        } catch {
            logger.error("Task \(taskID) failed to fetch page content: \(error)")
        }
        return nil
    }
    
    /// Checks if the provided content fulfills the requirements specified by the prompt.
    ///
    /// - Parameters:
    ///   - content: The content to be checked for relevance.
    ///   - prompt: The prompt used as a reference for relevance.
    ///   - taskId: The ID of the current task for logging.
    ///
    /// - Returns: A Boolean value indicating whether the content meets the prompt's criteria.
    private func checkContent(content: String, prompt: String, taskID: Int) async throws -> Bool {
        return try await retryAsync(maxRetries: 3) {
            self.logger.debug("Task \(taskID) checking content")
            let response = try await self.LLMExecute(
                Scouter.contentCheckPrompt(
                    prompt: prompt,
                    content: content
                ),
                instruction: Scouter.contentCheckInstruction())
            if let jsonData = response.removingCodeBlocks().data(using: .utf8) {
                let decoder = JSONDecoder()
                struct CheckResult: Decodable {
                    let found: Bool
                }
                let result = try decoder.decode(CheckResult.self, from: jsonData)
                return result.found
            } else {
                throw NSError(domain: "ScouterError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert response data."])
            }
        }
    }
    
    /// Analyzes the provided content in response to the specified prompt.
    ///
    /// - Parameters:
    ///   - content: The content to be analyzed.
    ///   - prompt: The prompt guiding the analysis.
    ///   - taskID: The ID of the current task for logging.
    ///
    /// - Returns: A concise summary relevant to the prompt, if any.
    private func analyzeContent(content: String, prompt: String, taskID: Int) async throws -> String? {
        return try await retryAsync(maxRetries: 2) {
            self.logger.debug("Task \(taskID) analyzing content")
            let response = try await self.LLMExecute(
                Scouter.contentAnalysisPrompt(
                    prompt: prompt,
                    content: content
                ),
                instruction: Scouter.contentAnalysisInstruction())
            return response
        }
    }
    
    /// Extracts links from the provided HTML content and scores them based on relevance.
    ///
    /// - Parameters:
    ///   - content: The HTML content to extract links from.
    ///   - embedding: The embedding vector for similarity scoring.
    ///   - baseURL: The base URL to resolve relative links.
    ///   - taskID: The ID of the current task for logging.
    ///
    /// - Returns: An array of `Link` objects with URLs, titles, and similarity scores.
    private func extractLinks(from content: String, embedding: [Double], baseURL: URL, taskID: Int) async -> [Scouter.Link] {
        logger.debug("Task \(taskID) extracting links")
        var links: [Scouter.Link] = []
        
        do {
            let doc = try SwiftSoup.parse(content)
            guard let body = doc.body() else { return [] }
            let anchorElements = try body.select("a[href]")
            
            for anchor in anchorElements {
                // Retrieve the href attribute
                let href = try anchor.attr("href")
                
                // Generate URL from href (supporting relative, absolute, and schemeless URLs)
                guard let resolvedURL = URL(string: href, relativeTo: baseURL)?.absoluteURL else {
                    logger.debug("Task \(taskID) invalid URL: \(href)")
                    continue
                }
                
                if let resolvedHost = resolvedURL.host, let baseHost = baseURL.host, resolvedHost != baseHost {
                    continue
                }
                
                var urlComponents = URLComponents(url: resolvedURL, resolvingAgainstBaseURL: true)
                urlComponents?.fragment = nil  // Remove fragment
                urlComponents?.query = nil     // Remove query parameters
                
                guard let normalizedURL = urlComponents?.url else {
                    logger.debug("Task \(taskID) failed to normalize URL: \(resolvedURL.absoluteString)")
                    continue
                }
                
                // Skip URL if already processed
                if readPages.contains(normalizedURL) {
                    logger.debug("Task \(taskID) URL already processed: \(normalizedURL.absoluteString)")
                    continue
                }
                
                if links.contains(where: { $0.url == normalizedURL }) {
                    logger.debug("Task \(taskID) URL already added: \(normalizedURL.absoluteString)")
                    continue
                }
                
                // Determine title based on priority: aria-label > link text > img alt > title attribute
                var title = try anchor.attr("aria-label").trimmingCharacters(in: .whitespacesAndNewlines)
                
                if title.isEmpty {
                    title = try anchor.text().trimmingCharacters(in: .whitespacesAndNewlines)
                }
                
                if title.isEmpty, let img = try anchor.select("img[alt]").first() {
                    title = try img.attr("alt").trimmingCharacters(in: .whitespacesAndNewlines)
                }
                
                if title.isEmpty {
                    title = try anchor.attr("title").trimmingCharacters(in: .whitespacesAndNewlines)
                }
                
                // Skip link if title is empty
                if title.isEmpty {
                    logger.debug("Task \(taskID) skipping link due to empty title: \(normalizedURL.absoluteString)")
                    continue
                }
                
                // Calculate score
                if let score = try await score(title, embedding: embedding) {
                    if score > self.options.similarityThreshold {
                        logger.debug("Task \(taskID) adding link: \(score) \(title) (\(normalizedURL.absoluteString))")
                        let link = Scouter.Link(url: normalizedURL, title: title, score: score)
                        links.append(link)
                    }
                }
            }
            
            logger.debug("Task \(taskID) link extraction completed: \(links.count) links found")
            
        } catch {
            logger.error("Task \(taskID) failed to extract links: \(error)")
        }
        
        return links
    }
    
    /// Analyzes a list of links and returns only those that are highly relevant based on the prompt.
    ///
    /// - Parameters:
    ///   - links: The list of links to analyze.
    ///   - prompt: The prompt guiding the link analysis.
    ///   - taskID: The ID of the current task for logging.
    ///
    /// - Returns: An array of URLs that are most relevant to the prompt.
    private func analyzeLinks(links: [Link], prompt: String, taskID: Int) async throws -> [URL] {
        return try await retryAsync(maxRetries: 2) {
            self.logger.debug("Task \(taskID) extracting high-importance links")
            let content = links.map { link in
                return "\(link.title): \(link.url)"
            }.joined(separator: "\n")
            let response = try await self.LLMExecute(
                Scouter.contentAnalysisPrompt(
                    prompt: prompt,
                    content: content
                ),
                instruction: Scouter.linkExtractionInstruction())
            if let jsonData = response.removingCodeBlocks().data(using: .utf8) {
                let decoder = JSONDecoder()
                struct LinkResult: Decodable {
                    let urls: [String]
                }
                let result = try decoder.decode(LinkResult.self, from: jsonData)
                return result.urls.compactMap({ URL(string: $0) })
            } else {
                throw NSError(domain: "ScouterError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert response data."])
            }
        }
    }
    
    /// Generates a unique task ID by incrementing a counter.
    ///
    /// - Returns: A unique task ID as an integer.
    private func generateTaskId() -> Int {
        taskCounter += 1
        return taskCounter
    }
}

extension Scouter {
    
    func LLMExecute(_ content: String, instruction: String) async throws -> String {
        let data = OKChatRequestData(
            model: self.model,
            messages: [
                OKChatRequestData.Message(role: .system, content: instruction),
                OKChatRequestData.Message(role: .user, content: "\(instruction)\n\n---\n\n\(content)")
            ]) { options in
                options.mirostatTau = 0
                options.numCtx = 1024 * 3
                options.repeatLastN = 0
                options.repeatPenalty = 1.5
                options.temperature = 0
                options.topK = 1
                options.topP = 1
                options.minP = 1
            }
        var response = ""
        for try await chunk in self.ollamaKit.chat(data: data) {
            response += chunk.message?.content ?? ""
        }
        return response
    }
    
    static func embeddings(model: String, content: String) async throws -> [Double] {
        let data = OKEmbeddingsRequestData(model: model, prompt: content)
        let response = try await OllamaKit().embeddings(data: data)
        return response.embedding!
    }
    
    func score(_ content: String, embedding: [Double]) async throws -> Double? {
        let data = OKEmbeddingsRequestData(model: model, prompt: content)
        let response = try await OllamaKit().embeddings(data: data)
        return cosineSimilarity(embedding, response.embedding!)
    }
    
    func cosineSimilarity(_ vectorA: [Double], _ vectorB: [Double]) -> Double? {
        guard vectorA.count == vectorB.count else { return nil }
        
        var dotProduct = 0.0
        vDSP_dotprD(vectorA, 1, vectorB, 1, &dotProduct, vDSP_Length(vectorA.count))
        
        var normA = 0.0, normB = 0.0
        vDSP_svesqD(vectorA, 1, &normA, vDSP_Length(vectorA.count))
        vDSP_svesqD(vectorB, 1, &normB, vDSP_Length(vectorB.count))
        
        guard normA > 0 && normB > 0 else { return nil }
        
        return dotProduct / (sqrt(normA) * sqrt(normB))
    }
    
    func convertToJSON(_ content: String, instruction: String) async throws -> String {
        let data = OKChatRequestData(
            model: self.model,
            messages: [
                OKChatRequestData
                    .Message(role: .user, content: "\(instruction)\n\n\(content)")
            ]) { options in
                options.mirostatTau = 0
                options.numCtx = 1024
                options.repeatLastN = 0
                options.repeatPenalty = 1.5
                options.temperature = 0
                options.topK = 1
                options.topP = 1
                options.minP = 1
            }
        var response = ""
        for try await chunk in self.ollamaKit.chat(data: data) {
            response += chunk.message?.content ?? ""
        }
        return response
    }
}

extension Scouter {
    
    // リトライ機構を提供する汎用関数（クラス内に定義）
    private func retryAsync<T: Sendable>(
        maxRetries: Int = 2,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        var attempt = 0
        while true {
            do {
                return try await operation()
            } catch {
                attempt += 1
                if attempt >= maxRetries {
                    logger.error("Operation failed after \(maxRetries) retries: \(error)")
                    throw error // リトライ上限に達した場合はエラーをスロー
                }
                logger.warning("Retrying operation (\(attempt)/\(maxRetries)) after error: \(error)")
            }
        }
    }
}

extension String {
    /// Removes code blocks from the string if present, otherwise returns the string as is.
    func removingCodeBlocks() -> String {
        let pattern = #"^```(?:[\s\S]*?)\n([\s\S]*?)\n```$"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) {
            let range = NSRange(self.startIndex..., in: self)
            let cleanedText = regex.stringByReplacingMatches(in: self, options: [], range: range, withTemplate: "$1")
            return cleanedText.isEmpty ? self : cleanedText
        }
        return self
    }
}

extension Document {
    
    /// Cleans the document by removing specified tags and returns the sanitized document.
    ///
    /// - Parameter tags: An array of tag names to remove from the document. Default tags include "script", "style", "link", "meta", "svg", and "noscript".
    /// - Returns: The sanitized `Document` instance with specified tags removed.
    func sanitized(tags: [String] = ["script", "style", "link", "meta", "svg", "noscript"]) -> Document {
        try! self.select(tags.joined(separator: ", ")).remove()
        return self
    }
    
    /// Extracts the main content element from the document, defaulting to `<main>` if available, or `<body>` if `<main>` is not found.
    ///
    /// - Returns: The main `Element` to be used as the primary content container.
    func main() -> Element {
        return try! self.select("main").first() ?? self.body() ?? self
    }
    
    /// Summarizes the content of the document, including the title, meta description, and main body text.
    ///
    /// - Returns: A `String` summary of the document’s title, description, and content.
    func summarize() -> String {
        let title = try! self.title()
        var description = ""
        if let metaDesc = try! self.select("meta[name=description]").first() {
            description = try! metaDesc.attr("content")
        }
        let bodyText = try! self.main().text()
        return """
        Title: \(title)
        Description: \(description)
        Content: \(bodyText)
        """
    }
}
