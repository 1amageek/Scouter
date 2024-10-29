# Scouter

Scouter is a Swift library that performs web content searching and link extraction based on relevance scoring. It is designed to analyze web pages, extract relevant links, and score them based on a specified similarity threshold. Scouter uses `SwiftSoup` for HTML parsing, `OllamaKit` for AI interactions, and `Accelerate` for efficient similarity calculations.

## Features

- **Recursive Web Content Search**: Starts searches from a given URL and explores relevant links recursively based on a search prompt.
- **Link Extraction**: Retrieves links from HTML content and scores them for relevance to a specified prompt.
- **Similarity Scoring**: Uses cosine similarity scoring for extracted links to filter out irrelevant content.
- **Configurable Options**: Allows customization of maximum tasks and similarity threshold for more focused searches.

## Requirements

- **Swift 6.0 or later**
- **iOS 18.0+**, **macOS 15.0+**
- Dependencies:
  - `SwiftSoup` for HTML parsing
  - `OllamaKit` for AI model interaction
  - `Logging` for structured log management

## Installation

### Swift Package Manager

To integrate Scouter into your project, add it as a dependency using Swift Package Manager:

```swift
dependencies: [
    .package(url: "https://github.com/1amageek/Scouter", from: "1.0.0")
]
```

## Usage

### Performing a Search
Use the search method to initiate a content search on a specific URL with a search prompt. This method returns relevant content if found, or nil if no relevant content is detected.

```swift
let url = URL(string: "https://example.com")!
let prompt = "Find information about AI in Swift"

Task {
    do {
        let result = try await Scouter.search(
            model: "YourModelIdentifier",
            url: url,
            prompt: prompt
        )
        if let content = result {
            print("Found content: \(content)")
        } else {
            print("No relevant content found.")
        }
    } catch {
        print("Search failed with error: \(error)")
    }
}
```
