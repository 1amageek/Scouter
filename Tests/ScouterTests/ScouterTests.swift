import Testing
@testable import Scouter
import Foundation
import OllamaKit
import Logging

@Test func example() async throws {
    
    LoggingSystem.bootstrap { label in
        StreamLogHandler.standardOutput(label: label)
    }
    
    var logger = Logger(label: "scouter")
    logger.logLevel = .debug

    let result = try await Scouter.search(
        model: "llama3.2:latest",
        url: URL(string: "https://www.apple.com/jp/")!,
        prompt: "iPhone16の画面サイズが知りたい。",
        logger: logger
    )
    
    print(result)
    
}
