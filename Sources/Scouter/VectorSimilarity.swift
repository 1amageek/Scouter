import Foundation
import Accelerate
import CoreFoundation
import Dispatch
import OllamaKit

/// A utility struct providing highly optimized vector similarity calculations using vDSP.
struct VectorSimilarity {
    
    /// Gets embedding for text using OllamaKit
    static func getEmbedding(for text: String, model: String = "llama3.2:latest") async throws -> [Float] {
        let data = OKEmbeddingsRequestData(
            model: model,
            prompt: text
        )
        let response = try await OllamaKit().embeddings(data: data)
        return response.embedding!
    }
    
    static func averageEmbedding(_ embeddings: [[Float]]) -> [Float] {
        guard !embeddings.isEmpty else { return [] }
        
        let rowCount = embeddings.count
        let colCount = embeddings[0].count
        
        // フラットな配列に変換してから合計を計算
        let flattenedEmbeddings = embeddings.flatMap { $0 }
        var sum = [Float](repeating: 0, count: colCount)
        
        // vDSP で各列の合計を計算
        vDSP_mtrans(flattenedEmbeddings, 1, &sum, 1, vDSP_Length(colCount), vDSP_Length(rowCount))
        
        // 平均値を計算
        var count = Float(rowCount)
        vDSP_vsdiv(sum, 1, &count, &sum, 1, vDSP_Length(colCount))
        
        return sum
    }
    
    /// Computes cosine similarity between two single-precision vectors using vDSP operations.
    ///
    /// - Parameters:
    ///   - a: First vector
    ///   - b: Second vector
    /// - Returns: Cosine similarity value between -1 and 1, or 0 if vectors are invalid
    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        
        var dotProduct: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dotProduct, vDSP_Length(a.count))
        
        var normA: Float = 0
        var normB: Float = 0
        vDSP_svesq(a, 1, &normA, vDSP_Length(a.count))
        vDSP_svesq(b, 1, &normB, vDSP_Length(b.count))
        
        guard normA > 0 && normB > 0 else { return 0 }
        
        return dotProduct / (sqrtf(normA) * sqrtf(normB))
    }
    
    // Thread-safe cache for similarity computations
    nonisolated(unsafe) private static let cache = NSCache<NSString, NSNumber>()
    
    private static func generateCacheKey(_ a: [Float], _ b: [Float]) -> NSString {
        let prefixLength = 5
        let aPrefix = Array(a[..<min(a.count, prefixLength)])
        let bPrefix = Array(b[..<min(b.count, prefixLength)])
        return NSString(string: "\(aPrefix)-\(bPrefix)")
    }
    
    /// Computes cosine similarity with caching
    static func cosineSimilarityWithCache(_ a: [Float], _ b: [Float]) -> Float {
        let key = generateCacheKey(a, b)
        
        if let cachedValue = cache.object(forKey: key) {
            return cachedValue.floatValue
        }
        
        let result = cosineSimilarity(a, b)
        cache.setObject(NSNumber(value: result), forKey: key)
        return result
    }
}
