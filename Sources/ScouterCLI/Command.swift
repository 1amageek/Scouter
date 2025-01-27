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
        abstract: "Convert HTML content from URLs to Markdown format",
        version: "1.0.0"
    )
    
    @Argument(help: "Search query prompt")
    var prompt: String
    
    mutating func run() async throws {
        let result = try await Scouter.search(
            prompt: prompt,
            logger: Logger(label: "Scouter")
        )
        let summarizer = OpenAISummarizer()
        let summary = try await summarizer.summarize(pages: result.pages, query: prompt)
        print(result.terminationReason)
        print("==========")
        print(summary)
    }
}

extension ScouterCommand {
    struct ValidationError: Error, LocalizedError {
        let message: String
        
        init(_ message: String) {
            self.message = message
        }
        
        var errorDescription: String? {
            return message
        }
    }
}
