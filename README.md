# Scouter

Scouter is a powerful web crawling and content analysis framework for Swift that uses AI to intelligently navigate and evaluate web content. It combines advanced web crawling capabilities with AI-powered content evaluation to help you find and analyze relevant information across the web.

## Features

- 🔍 Intelligent web crawling with AI-guided navigation
- 🤖 AI-powered content evaluation and prioritization
- 🌐 Smart domain filtering and control
- 📊 Concurrent crawling with adaptive depth management
- 📝 Content summarization with multiple AI model support
- 🔗 Advanced URL normalization and filtering
- 📈 Priority-based crawling strategy
- 🛡 Built-in protection against common crawling pitfalls

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

## Basic Usage

Here's a simple example of how to use Scouter:

```swift
import Scouter

// Create a search instance with default options
let result = try await Scouter.search(
    prompt: "Swift concurrency best practices",
    logger: Logger(label: "Scouter")
)

// Access the crawled pages
for page in result.pages {
    print("URL: \(page.url)")
    print("Priority: \(page.priority)")
    print("Content: \(page.remark.plainText)")
}

// Generate a summary using OpenAI
let summarizer = OpenAISummarizer()
let summary = try await summarizer.summarize(
    pages: result.pages, 
    query: "Swift concurrency best practices"
)
```

## Advanced Configuration

Scouter provides extensive configuration options through the `Options` struct:

```swift
let options = Scouter.Options(
    model: "llama3.2:latest",         // AI model to use
    maxDepth: 5,                      // Maximum crawling depth
    maxPages: 45,                     // Maximum pages to crawl
    maxCrawledPages: 10,              // Maximum pages to store
    maxConcurrentCrawls: 5,           // Maximum concurrent crawls
    minHighScoreLinks: 10,            // Minimum high-scoring links
    highScoreThreshold: 3.1,          // Threshold for high-score links
    domainControl: DomainControl(     // Domain filtering
        exclude: ["facebook.com", "twitter.com"]
    )
)

let result = try await Scouter.search(
    prompt: "Your search query",
    options: options,
    logger: Logger(label: "Scouter")
)
```

## Key Components

### Crawler

The `Crawler` class manages the web crawling process:
- Handles concurrent crawling with depth management
- Normalizes and filters URLs
- Evaluates content relevance using AI
- Manages crawling state and termination conditions

### Evaluators

Scouter supports multiple AI evaluators:

1. `OllamaEvaluator`: Uses Ollama models for content evaluation
```swift
let evaluator = OllamaEvaluator(model: "llama3.2:latest")
```

2. `OpenAIEvaluator`: Uses OpenAI models for content evaluation
```swift
let evaluator = OpenAIEvaluator(model: "gpt-4o-mini")
```

### Summarizers

Content summarization is supported through:

1. `OllamaSummarizer`: Generates summaries using Ollama models
```swift
let summarizer = OllamaSummarizer(model: "llama3.2:latest")
```

2. `OpenAISummarizer`: Generates summaries using OpenAI models
```swift
let summarizer = OpenAISummarizer(model: "gpt-4o-mini")
```

## Domain Control

You can control which domains are crawled using the `DomainControl` struct:

```swift
let domainControl = DomainControl(
    exclude: [
        "facebook.com",
        "instagram.com",
        "youtube.com",
        "pinterest.com",
        "twitter.com",
        "x.com"
    ]
)
```

## Prioritization System

Scouter uses a sophisticated prioritization system:

- `Priority` enum with values from `.low` (1) to `.critical` (5)
- Score calculation based on priority and depth
- Adaptive crawling based on content relevance
- Low priority streak detection to prevent wasteful crawling

## CLI Tool

Scouter includes a command-line interface:

```bash
scouter "Your search query"
```

This will:
1. Perform the search
2. Crawl relevant pages
3. Generate a summary
4. Display results in the terminal

## Error Handling

Scouter provides structured error handling:

```swift
do {
    let result = try await Scouter.search(prompt: "Your query")
} catch {
    switch error {
    case let error as Scouter.OptionsError:
        print("Options error: \(error)")
    default:
        print("Unexpected error: \(error)")
    }
}
```

## Logging

Scouter uses the `Logging` framework for structured logging:

```swift
let logger = Logger(label: "Scouter")
let result = try await Scouter.search(
    prompt: "Your query",
    logger: logger
)
```

## License

Scouter is available under the MIT license.

## Author

Created by Norikazu Muramoto ([@1amageek](https://github.com/1amageek))
