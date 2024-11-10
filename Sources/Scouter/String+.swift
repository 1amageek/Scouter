//
//  String+.swift
//  Scouter
//
//  Created by Norikazu Muramoto on 2024/11/10.
//

import Foundation

extension String {
    
    func extracted() -> String {
        let (codeBlocks, _) = self.extractingAndRemovingCodeBlocks()
        if (codeBlocks.isEmpty) { return self.removingCodeBlocks() }
        return codeBlocks.first?.removingCodeBlocks() ?? self
    }
    
    func extractingAndRemovingCodeBlocks() -> ([String], String) {
        let pattern = #"(?ms)```(?:.*?\n)?([\s\S]*?)\n?```"#
        var codeBlocks: [String] = []
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(self.startIndex..., in: self)
            let matches = regex.matches(in: self, range: range)
            for match in matches.reversed() {
                if let codeRange = Range(match.range(at: 1), in: self) {
                    let codeBlock = String(self[codeRange])
                    codeBlocks.insert(codeBlock, at: 0)
                }
            }
        }
        return (codeBlocks, self)
    }
    
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
