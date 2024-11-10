import Testing
@testable import Scouter
import Foundation
import OllamaKit
import Logging

@Test func explore() async throws {
    LoggingSystem.bootstrap { label in
        StreamLogHandler.standardOutput(label: label)
    }
    var logger = Logger(label: "scouter")
    logger.logLevel = .debug
    let result = try await Scouter.search(
        prompt: "iPhone16の画面サイズが知りたい。",
        url: URL(string: "https://www.apple.com/jp/")!,
        logger: logger
    )
    print(result!)
}
