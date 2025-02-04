//
//  Model.swift
//  Scouter
//
//  Created by Norikazu Muramoto on 2025/02/04.
//

import Foundation

public enum Model: Sendable {
    case ollama(String)
    case openAI(String)
    
    public static func parse(_ provider: String, _ name: String) -> Model {
        switch provider.lowercased() {
        case "openai":
            return .openAI(name)
        default:
            return .ollama(name)
        }
    }
    
    func createEvaluator() -> any Evaluating {
        switch self {
        case .ollama(let model):
            return OllamaEvaluator(model: model)
        case .openAI(let model):
            return OpenAIEvaluator(model: model)
        }
    }
    
    func createSummarizer() -> any Summarizing {
        switch self {
        case .ollama(let model):
            return OllamaSummarizer(model: model)
        case .openAI(let model):
            return OpenAISummarizer(model: model)
        }
    }
    
    public static var defaultModel: Model {
        .ollama("llama3.2:latest")
    }
}
