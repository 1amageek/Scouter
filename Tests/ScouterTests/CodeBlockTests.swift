

import Testing
import Foundation
@testable import Scouter

@Test("Extract and remove single code block")
func testExtractAndRemoveSingleCodeBlock() {
    let text = """
    Here is some code:
    ```swift
    let x = 1
    let y = 2
    ```
    """
    
    let (codeBlocks, textWithoutBlocks) = text.extractingAndRemovingCodeBlocks()
    
    #expect(codeBlocks.count == 1)
    #expect(codeBlocks[0] == "let x = 1\nlet y = 2")
    #expect(textWithoutBlocks == text)  // 元のテキストがそのまま返される
}

@Test("Extract and remove multiple code blocks")
func testExtractAndRemoveMultipleCodeBlocks() {
    let text = """
    First block:
    ```swift
    let x = 1
    ```
    Second block:
    ```python
    print("hello")
    ```
    """
    
    let (codeBlocks, textWithoutBlocks) = text.extractingAndRemovingCodeBlocks()
    
    #expect(codeBlocks.count == 2)
    #expect(codeBlocks[0] == "let x = 1")
    #expect(codeBlocks[1] == "print(\"hello\")")
    #expect(textWithoutBlocks == text)  // 元のテキストがそのまま返される
}

@Test("Extract and remove code blocks with no language specification")
func testExtractAndRemoveCodeBlocksNoLanguage() {
    let text = """
    ```
    plain text
    no language
    ```
    """
    
    let (codeBlocks, textWithoutBlocks) = text.extractingAndRemovingCodeBlocks()
    
    #expect(codeBlocks.count == 1)
    #expect(codeBlocks[0] == "plain text\nno language")
    #expect(textWithoutBlocks == text)
}

@Test("Extract and remove from string with no code blocks")
func testExtractAndRemoveNoCodeBlocks() {
    let text = "Just a regular string without any code blocks"
    let (codeBlocks, textWithoutBlocks) = text.extractingAndRemovingCodeBlocks()
    
    #expect(codeBlocks.isEmpty)
    #expect(textWithoutBlocks == text)
}

@Test("Extract and remove code blocks with special characters")
func testExtractAndRemoveCodeBlocksWithSpecialChars() {
    let text = """
    Special chars:
    ```
    !@#$%^&*()
    日本語文字
    ```
    End
    """
    
    let (codeBlocks, textWithoutBlocks) = text.extractingAndRemovingCodeBlocks()
    
    #expect(codeBlocks.count == 1)
    #expect(codeBlocks[0] == "!@#$%^&*()\n日本語文字")
    #expect(textWithoutBlocks == text)
}

@Test("Extract and remove empty code blocks")
func testExtractAndRemoveEmptyCodeBlocks() {
    let text = """
    Empty block:
    ```
    ```
    """
    
    let (codeBlocks, textWithoutBlocks) = text.extractingAndRemovingCodeBlocks()
    
    #expect(codeBlocks.count == 1)
    #expect(codeBlocks[0].isEmpty)
    #expect(textWithoutBlocks == text)
}


@Test("Extract and remove code blocks with surrounding whitespace")
func testExtractAndRemoveCodeBlocksWithWhitespace() {
    let text = """
    
    ```swift
    let x = 1
    ```
    
    """
    
    let (codeBlocks, textWithoutBlocks) = text.extractingAndRemovingCodeBlocks()
    
    #expect(codeBlocks.count == 1)
    #expect(codeBlocks[0] == "let x = 1")
    #expect(textWithoutBlocks == text)
}

// removingCodeBlocks()のテスト
@Test("Remove code blocks from string")
func testRemovingCodeBlocks() {
    let text = """
    ```swift
    let x = 1
    let y = 2
    ```
    """
    
    let cleaned = text.removingCodeBlocks()
    #expect(cleaned == "let x = 1\nlet y = 2")
}

@Test("Remove code blocks from string with no code blocks")
func testRemovingNoCodeBlocks() {
    let text = "Just a regular string without any code blocks"
    let cleaned = text.removingCodeBlocks()
    
    #expect(cleaned == text)
}
