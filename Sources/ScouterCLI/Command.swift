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
        commandName: "remark",
        abstract: "Convert HTML content from URLs to Markdown format",
        version: "1.0.0"
    )
    
    @Argument(help: "The URL to fetch and convert to Markdown")
    var url: String
    
    @Flag(name: .shortAndLong, help: "Include front matter in the output")
    var includeFrontMatter: Bool = false
    
    @Flag(name: .shortAndLong, help: "Show only the plain text content")
    var plainText: Bool = false
    
    
    
    mutating func run() async throws {
        let result = try await Scouter.search(
            prompt: "紅鮎について教えてください",
            logger: Logger(label: "Scouter")
        )
        
        result.pages.forEach { page in
            print(page.remark.page)
        }
        
    }
}

// エラーハンドリングの拡張
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
