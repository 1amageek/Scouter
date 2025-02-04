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
  - `OllamaKit` for Ollama model interaction
  - `LLMChatOpenAI` for OpenAI model interaction

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

// Create a search instance with default options (using Ollama)
let result = try await Scouter.search(prompt: "Swift concurrency best practices")

// Generate summary (automatically done in the search process)
let summary = try await Scouter.summarize(result: result)
```

## Using OpenAI Models

To use OpenAI models, you need to set up your API key first:

1. Set OPENAI_API_KEY in your environment:
   - In terminal: `export OPENAI_API_KEY='your-api-key'`
   - Or in Xcode: Add to scheme environment variables
   - Or in macOS: Add to system environment variables

Then you can use OpenAI models:

```swift
let options = Scouter.Options(
    evaluatorModel: .openAI("gpt-4o-mini"),
    summarizerModel: .openAI("gpt-4o-mini")
)

let result = try await Scouter.search(
    prompt: "Your search query",
    options: options
)
```

## Model Configuration

Scouter supports both Ollama and OpenAI models:

```swift
// Using Ollama models (default)
let ollamaOptions = Scouter.Options(
    evaluatorModel: .ollama("llama3.2:latest"),
    summarizerModel: .ollama("llama3.2:latest")
)

// Using OpenAI models
let openAIOptions = Scouter.Options(
    evaluatorModel: .openAI("gpt-4o-mini"),
    summarizerModel: .openAI("gpt-4o-mini")
)

// Mix and match models
let mixedOptions = Scouter.Options(
    evaluatorModel: .ollama("llama3.2:latest"),
    summarizerModel: .openAI("gpt-4o-mini")
)
```

## CLI Tool

Scouter includes a command-line interface:

```bash
# Using default Ollama models
scouter "Your search query"

# Using OpenAI models
scouter "Your search query" \
  --evaluator-provider openai --evaluator-model "gpt-4o-mini" \
  --summarizer-provider openai --summarizer-model "gpt-4o-mini"

# Mix and match models
scouter "Your search query" \
  --evaluator-provider ollama --evaluator-model "llama3.2:latest" \
  --summarizer-provider openai --summarizer-model "gpt-4o-mini"
```

## Domain Control

You can control which domains are crawled:

```swift
let options = Scouter.Options(
    evaluatorModel: .ollama("llama3.2:latest"),
    summarizerModel: .ollama("llama3.2:latest"),
    domainControl: DomainControl(
        exclude: [
            "facebook.com",
            "instagram.com",
            "youtube.com",
            "pinterest.com",
            "twitter.com",
            "x.com"
        ]
    )
)
```

## Advanced Configuration

Scouter provides extensive configuration options:

```swift
let options = Scouter.Options(
    evaluatorModel: .ollama("llama3.2:latest"),
    summarizerModel: .ollama("llama3.2:latest"),
    maxDepth: 5,                      // Maximum crawling depth
    maxPages: 45,                     // Maximum pages to crawl
    maxCrawledPages: 10,              // Maximum pages to store
    maxConcurrentCrawls: 5,           // Maximum concurrent crawls
    minHighScoreLinks: 10,            // Minimum high-scoring links
    highScoreThreshold: 3.1           // Threshold for high-score links
)
```

## Error Handling

```swift
do {
    let result = try await Scouter.search(prompt: "Your query")
    let summary = try await Scouter.summarize(result: result)
} catch {
    print("Error: \(error)")
}
```

## License

Scouter is available under the MIT license.

## Author

Created by Norikazu Muramoto ([@1amageek](https://github.com/1amageek))
