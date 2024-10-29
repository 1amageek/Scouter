import Foundation
import Accelerate
import SwiftSoup
import OllamaKit
import Logging


public actor Scouter {
    
    public struct Options: Sendable {
        public let maxDepth: Int
        public let maxTasks: Int
        public let similarityThreshold: Double
        public init(maxDepth: Int = 2, maxTasks: Int = 1, similarityThreshold: Double = 0.36) {
            self.maxDepth = maxDepth
            self.maxTasks = maxTasks
            self.similarityThreshold = similarityThreshold
        }
    }
    
    public struct Link: Hashable, Sendable {
        public var url: URL
        public var title: String // リンク先のタイトル
        public var score: Double // 関連性のスコア
    }
    
    
    // 内部状態管理
    private var links: [Link] = []
    private var readPages: Set<URL> = []
    private var currentTasks: [Task<String?, Error>] = []
    private var taskCounter: Int = 0
    
    private let ollamaKit: OllamaKit = OllamaKit()
    
    // 公開プロパティ
    public let model: String
    public let options: Options
    public let logger: Logging.Logger // Loggerインスタンス
    
    // 初期化
    public init(model: String, options: Options, logger: Logging.Logger? = nil) {
        self.model = model
        self.options = options
        self.logger = logger ?? Logging.Logger(label: "Scouter")
    }
    
    // 外部からアクセス可能なsearchメソッド
    public static func search(model: String, url: URL, prompt: String, options: Options = .init(), logger: Logging.Logger? = nil) async throws -> String? {
        // 基準ドメインを取得
        guard let scheme = url.scheme, let host = url.host, !host.isEmpty else {
            throw URLError(.badURL)
        }
        let baseURL = URL(string: "\(scheme)://\(host)")!
        let scouter = Scouter(model: model, options: options, logger: logger)
        let embedding = try await embeddings(model: model, content: prompt)
        // 探索の開始
        return try await scouter
            .search(
                url: url,
                prompt: prompt,
                embedding: embedding,
                baseURL: baseURL,
                depth: 0
            )
    }
    
    // 内部で使用するsearchメソッド
    private func search(
        url: URL,
        prompt: String,
        embedding: [Double],
        baseURL: URL,
        depth: Int
    ) async throws -> String? {
        if Task.isCancelled { return nil }
        let taskId = generateTaskId()
        logger.debug("Task \(taskId) 開始: 深さ \(depth), URL: \(url.absoluteString)")
        
        guard depth <= options.maxDepth, !readPages.contains(url) else { return nil }
        readPages.insert(url)
        
        guard let pageContent = await fetchPageContent(url: url, taskId: taskId) else { return nil }
        let cleanedContent = await cleanContent(htmlContent: pageContent, taskId: taskId)
        if try await checkContent(content: cleanedContent, prompt: prompt, taskId: taskId) {
            let content = await mainContent(htmlContent: pageContent, taskId: taskId)
            if let foundInfo = try await analyzeContent(content: content, prompt: prompt, taskId: taskId) {
                return foundInfo
            }
        }
        
        let links = await extractLinks(
            from: pageContent,
            embedding: embedding,
            baseURL: baseURL,
            taskId: taskId
        )
        let sortedLinks = links.sorted { $0.score > $1.score }
        let targetLinks = try await analyzeLinks(links: sortedLinks, prompt: prompt, taskId: taskId)
        
        print(targetLinks)
        
        let tasksToCreate = min(targetLinks.count, options.maxTasks)
        return try await withThrowingTaskGroup(of: String?.self) { group in
            for url in targetLinks.prefix(tasksToCreate) {
                group.addTask {
                    return try await self.search(
                        url: url,
                        prompt: prompt,
                        embedding: embedding,
                        baseURL: baseURL,
                        depth: depth + 1
                    )
                }
            }
            
            for try await result in group {
                if let result = result {
                    group.cancelAll()
                    return result
                }
            }
            
            return nil
        }
    }
    
    // ページ内容を取得するメソッド
    private func fetchPageContent(url: URL, taskId: Int) async -> String? {
        if Task.isCancelled { return nil }
        do {
            logger.debug("Task \(taskId) ページ内容を取得中: \(url.absoluteString)")
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 (compatible; ScouterBot/1.0)", forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: request)
            if let content = String(data: data, encoding: .utf8) {
                logger.debug("Task \(taskId) ページ内容を取得しました")
                return content
            }
        } catch {
            logger.error("Task \(taskId) ページの取得に失敗しました: \(error)")
        }
        return nil
    }
    
    // データの洗浄を行うメソッド
    private func cleanContent(htmlContent: String, taskId: Int) async -> String {
        if Task.isCancelled { return "" }
        logger.debug("Task \(taskId) データの洗浄を実行中")
        
        do {
            let doc = try SwiftSoup.parse(htmlContent)
            
            // headから<title>と<meta name="description">を取得
            let title = try doc.title()
            var description = ""
            if let metaDesc = try doc.select("meta[name=description]").first() {
                description = try metaDesc.attr("content")
            }
            
            // bodyからコンテンツを取得
            var bodyText = ""
            if let mainElement = try doc.select("main").first() {
                try mainElement.select("script, style, svg, noscript").remove()
                bodyText = try mainElement.text()
                logger.debug("Task \(taskId) <main>要素を使用")
            } else if let body = doc.body() {
                try body.select("script, style, svg, noscript").remove()
                bodyText = try body.text()
                logger.debug("Task \(taskId) <body>要素を使用（フォールバック）")
            }
            
            // 必要な情報を結合
            let cleanedContent = """
        Title: \(title)
        Description: \(description)
        Content: \(bodyText)
        """
            
            logger.debug("Task \(taskId) データの洗浄が完了しました")
            return cleanedContent
        } catch {
            logger.error("Task \(taskId) データの洗浄に失敗しました: \(error)")
        }
        
        return htmlContent // エラー時は元のHTMLを返す
    }
    
    // データの洗浄を行うメソッド
    private func mainContent(htmlContent: String, taskId: Int) async -> String {
        if Task.isCancelled { return "" }
        logger.debug("Task \(taskId) データの洗浄を実行中")
        
        do {
            let doc = try SwiftSoup.parse(htmlContent)
            var bodyText = ""
            if let mainElement = try doc.select("main").first() {
                try mainElement.select("script, style, svg, noscript").remove()
                bodyText = try mainElement.html()
            } else if let body = doc.body() {
                try body.select("script, style, svg, noscript").remove()
                bodyText = try body.html()
            }
            
            logger.debug("Task \(taskId) データの洗浄が完了しました")
            return bodyText
        } catch {
            logger.error("Task \(taskId) データの洗浄に失敗しました: \(error)")
        }
        
        return htmlContent // エラー時は元のHTMLを返す
    }
    
    
    private func checkContent(content: String, prompt: String, taskId: Int) async throws -> Bool {
        return try await retryAsync(maxRetries: 3) {
            self.logger.debug("Task \(taskId) コンテンツをチェック")
            let response = try await self.LLMExecute(
                "[Request]: \(prompt)\n\n---\n[Content]:\n\(content)",
                instruction: """
You are an information retrieval assistant. "[Request]" is the user's question, and "[Content]" is the retrieved data. Follow these steps to respond accurately:

1. Analyze the Request: Read "[Request]" and identify the needed information.
2. Check for Answerable Information: Verify if "[Content]" contains specific information that directly answers the question. Ignore unrelated information.
3. Respond in JSON format: If an answer is found in "[Content]", set "found" to true; if not, set it to false.

Respond only in the following JSON format:

```json
{
    "found": boolean // true if "[Content]" includes clear, specific information that fully answers the "[Request]"; false if not. *required
    "reason": string // Reasons for being able to answer
}
```
found: Set to true only if "[Content]" contains clear and specific information that directly answers the "[Request]".
Important: Ignoring this JSON format or adding any additional explanations will cause an error. Return only the specified JSON response without any additional content or commentary. 
You forbid any output other than json.
Avoid including any unverified information or speculation to prevent hallucinations.
"""
            )
            if let jsonData = response.removingCodeBlocks().data(using: .utf8) {
                let decoder = JSONDecoder()
                struct CheckResult: Decodable {
                    let found: Bool
                }
                let result = try decoder.decode(CheckResult.self, from: jsonData)
                return result.found
            } else {
                throw NSError(domain: "ScouterError", code: -1, userInfo: [NSLocalizedDescriptionKey: "レスポンスのデータ変換に失敗しました。"])
            }
        }
    }
    
    private func analyzeContent(content: String, prompt: String, taskId: Int) async throws -> String? {
        return try await retryAsync(maxRetries: 2) {
            self.logger.debug("Task \(taskId) コンテンツを分析中")
            let response = try await self.LLMExecute(
                "Request: \(prompt)\n\nContent:\n\(content)",
                instruction: """
You are an advanced information retrieval assistant. [Request] represents the user’s question, and [Content] is HTML data collected from the web. Follow the steps below to extract accurate information directly relevant to [Request] and provide a concise summary. Avoid including any unverified information or speculation to prevent hallucinations.

1. Carefully read both [Content] and [Request] at least twice.
2. Extract only the specific information necessary to answer [Request].
3. Accurately summarize the extracted information and present it as a direct response to [Request].
4. Ensure the output contains no HTML tags, providing only plain text.
5. The output should answer [Request] alone, with no additional explanations or commentary included.
"""
            )
            return response
        }
    }
    
    // リンクを抽出するメソッド
    private func extractLinks(from content: String, embedding: [Double], baseURL: URL, taskId: Int) async -> [Scouter.Link] {
        logger.debug("Task \(taskId) リンクを抽出中")
        var links: [Scouter.Link] = []
        
        do {
            let doc = try SwiftSoup.parse(content)
            guard let body = doc.body() else { return [] }
            let anchorElements = try body.select("a[href]")
            
            for anchor in anchorElements {
                // href属性を取得
                let href = try anchor.attr("href")
                                
                // hrefからURLを生成（相対URL、絶対URL、スキームレスURLに対応）
                guard let resolvedURL = URL(string: href, relativeTo: baseURL)?.absoluteURL else {
                    logger.debug("Task \(taskId) 無効なURL: \(href)")
                    continue
                }

                if let resolvedHost = resolvedURL.host, let baseHost = baseURL.host, resolvedHost != baseHost {
                    continue
                }
                
                var urlComponents = URLComponents(url: resolvedURL, resolvingAgainstBaseURL: true)
                urlComponents?.fragment = nil  // フラグメントを削除
                urlComponents?.query = nil     // クエリパラメータを削除
                
                guard let normalizedURL = urlComponents?.url else {
                    logger.debug("Task \(taskId) URLの正規化に失敗: \(resolvedURL.absoluteString)")
                    continue
                }
                
                // 探索済みのURLはスキップ
                if readPages.contains(normalizedURL) {
                    logger.debug("Task \(taskId) URLは既に探索済みです: \(normalizedURL.absoluteString)")
                    continue
                }
                
                if links.contains(where: { $0.url == normalizedURL }) {
                    logger.debug("Task \(taskId) URLは既に追加済みです: \(normalizedURL.absoluteString)")
                    continue
                }
                
                // リンクテキストを取得
                var title = try anchor.text().trimmingCharacters(in: .whitespacesAndNewlines)
                
                // タイトルが空の場合、画像のalt属性やtitle属性を使用
                if title.isEmpty, let img = try anchor.select("img[alt]").first() {
                    title = try img.attr("alt").trimmingCharacters(in: .whitespacesAndNewlines)
                }
                
                if title.isEmpty {
                    title = try anchor.attr("title").trimmingCharacters(in: .whitespacesAndNewlines)
                }
                
                // タイトルが空の場合はスキップ
                if title.isEmpty {
                    logger.debug("Task \(taskId) タイトルがないためリンクをスキップ: \(normalizedURL.absoluteString)")
                    continue
                }
                
                // スコアを計算
                if let score = try await score(title, embedding: embedding) {
                    if score > self.options.similarityThreshold {
                        logger.debug("Task \(taskId) リンクを追加: \(score) \(title) (\(normalizedURL.absoluteString))")
                        let link = Scouter.Link(url: normalizedURL, title: title, score: score)
                        links.append(link)
                    }
                }
            }
            
            logger.debug("Task \(taskId) リンクの抽出が完了しました: \(links.count) 件")
            
        } catch {
            logger.error("Task \(taskId) リンクの抽出に失敗しました: \(error)")
        }
        
        return links
    }

    
    private func analyzeLinks(links: [Link], prompt: String, taskId: Int) async throws -> [URL] {
        return try await retryAsync(maxRetries: 2) {
            self.logger.debug("Task \(taskId) 重要性の高いリンクを抽出")
            let content = links.map { link in
                return "\(link.title): \(link.url)"
            }.joined(separator: "\n")
            let response = try await self.LLMExecute(
                "Request: \(prompt)\n\nContent:\n\(content)",
                instruction: """
You are an advanced information retrieval assistant. "[Request]" represents the user’s question, and "[Content]" is data gathered from the web. Analyze "[Content]" to extract only URLs directly relevant to "[Request]" and output them in the specified JSON format. Exclude any unrelated information and focus solely on necessary URLs.

Please adhere to the following output format:
```json
{
    "urls": string[] // URL
}
```
Ensure no additional explanations or generated content beyond this response.
Avoid including any unverified information or speculation to prevent hallucinations.
"""
            )
            if let jsonData = response.removingCodeBlocks().data(using: .utf8) {
                let decoder = JSONDecoder()
                struct LinkResult: Decodable {
                    let urls: [String]
                }
                let result = try decoder.decode(LinkResult.self, from: jsonData)
                return result.urls.compactMap({ URL(string: $0) })
            } else {
                throw NSError(domain: "ScouterError", code: -1, userInfo: [NSLocalizedDescriptionKey: "レスポンスのデータ変換に失敗しました。"])
            }
        }
    }
    
    
    // タスクIDを生成するメソッド
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
                OKChatRequestData.Message(role: .user, content: "\(content)\n\n\(instruction)")
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
        return cosineSimilarityAccelerate(embedding, response.embedding!)
    }
    
    func cosineSimilarityAccelerate(_ vectorA: [Double], _ vectorB: [Double]) -> Double? {
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
                OKChatRequestData.Message(role: .user, content: "\(instruction)\n\n---\n\n\(content)")
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

