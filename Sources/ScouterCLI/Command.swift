//
//  Command.swift
//  Scouter
//
//  Created by Norikazu Muramoto on 2024/11/14.
//

import Foundation
import ArgumentParser
import Remark
import Scouter
import Logging

@main
struct ScouterCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scouter",
        abstract: "Search and analyze web content",
        version: "1.0.0"
    )
    
    @Argument(help: "Search query prompt")
    var prompt: String
    
    @Option(name: .long, help: "Evaluator provider (ollama/openai)")
    var evaluatorProvider: String = "ollama"
    
    @Option(name: .long, help: "Evaluator model name")
    var evaluatorModel: String = "llama3.2:latest"
    
    @Option(name: .long, help: "Summarizer provider (ollama/openai)")
    var summarizerProvider: String = "ollama"
    
    @Option(name: .long, help: "Summarizer model name")
    var summarizerModel: String = "llama3.2:latest"
    
    mutating func run() async throws {
        let logger = Logger(label: "Scouter")
        
        let options = Scouter.Options(
            evaluatorModel: .parse(evaluatorProvider, evaluatorModel),
            summarizerModel: .parse(summarizerProvider, summarizerModel)
        )
        
        let result = try await Scouter.search(prompt: prompt, options: options, logger: logger)
        let summary = try await Scouter.summarize(result: result, options: options, logger: logger)
        
        print("\n=== Summary ===")
        print(summary)
        print("\n=== Search Results ===")
        print(result)
    }
}
