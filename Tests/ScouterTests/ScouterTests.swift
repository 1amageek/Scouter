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
        prompt: "紅鮎について教えてください",
        url: URL(string: "https://www.apple.com/jp/")!,
        logger: nil
    )
    print(result!)
}
