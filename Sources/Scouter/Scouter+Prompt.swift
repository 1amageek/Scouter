//
//  Scouter+Prompt.swift
//  Scouter
//
//  Created by Norikazu Muramoto on 2024/10/29.
//

extension Scouter {
    
    /// コンテンツのチェックプロンプトとその指示
    static func contentCheckPrompt(prompt: String, content: String) -> String {
        return """
        [Query]: 
        \(prompt)
        
        [Content]:
        ```
        \(content)
        ```
        
        Please check if the information corresponding to the answer to the request is included and respond according to the JSON format.
        ```json
        {
            "found": boolean // true if "[Content]" includes clear, specific information that fully answers the "[Query]"; false if not. *required
            "reason": string // Reasons for being able to answer
        }
        ```
        [Response(Only JSON)]:
        """
    }
    
    static func contentCheckInstruction() -> String {
        return """
        You are a JSON Formatter. "[Query]" is the user's question, and "[Content]" is the retrieved data. Follow these steps to respond accurately. Avoid including any unverified information or speculation to prevent hallucinations.
        
        1. Analyze the Request: Read "[Query]" and identify the needed information.  
        2. Check for Answerable Information: Verify if "[Content]" contains specific information that directly answers the question. Ignore unrelated information.  
        3. Respond **only in JSON format**: Regardless of whether an answer is found or not, respond exclusively in the exact JSON format below. Do not add any additional explanations, comments, or content.  
        4. If information is present, set `found` to true; if not, set `found` to false.
        
        Respond only in the following strict JSON format:
        
        ```json
        {
            "found": boolean // true if "[Content]" includes clear, specific information that fully answers the "[Query]"; false if not. *required
            "reason": string // Reasons for being able to answer
        }
        ```
        found: Set to true only if "[Content]" contains clear and specific information that directly answers the "[Query]".
        Important: Follow this exact JSON format only, and do not include any additional text, explanations, or commentary outside this format. Failure to comply with this format will result in a penalty.
        """
    }
    
    /// コンテンツの分析プロンプトとその指示
    static func contentAnalysisPrompt(prompt: String, content: String) -> String {
        return """
        [Request]:
        ```
        \(prompt)
        ```
        
        [Content]:
        ```
        \(content)
        ```
        
        Using information from [Content], provide a concise summary relevant to [Request].
        
        [Response]:
        """
    }
    
    static func contentAnalysisInstruction() -> String {
        return """
        You are an advanced information retrieval assistant. [Request] represents the user’s question, and [Content] is HTML data collected from the web. Follow the steps below to extract information directly relevant to [Request] and provide a concise summary.
        
        1. Identify keywords related to [Request] and use them to locate relevant sections within the HTML data.
        2. Select the most relevant information from [Content] that directly addresses [Request].
        3. Summarize the relevant information concisely, including only verified facts. Avoid unverified information, speculation, or hallucinations (generating information that does not actually exist).
        4. Ensure the final response provides a direct and reliable answer to [Request].
        
        Follow these steps to deliver fact-based information only.
        """
    }
    
    /// リンクの抽出プロンプトとその指示
    static func linkExtractionPrompt(prompt: String, content: String) -> String {
        return """
        [Request]:
        \(prompt)
        [Content]:
        ```
        \(content)
        ```
        
        [Response(JSON)]:
        """
    }
    
    static func linkExtractionInstruction() -> String {
        return """
        You are an advanced information retrieval assistant. "[Request]" represents the user’s question, and "[Content]" is data gathered from the web. Analyze "[Content]" to extract only URLs directly relevant to "[Request]" and output them in the specified JSON format. Exclude any unrelated information and focus solely on necessary URLs.
        
        Please adhere to the following output format:
        ```json
        {
            "urls": string[] // URL
        }
        ```
        Ensure no additional explanations or generated content beyond this response.
        Avoid including any unverified information or speculation to prevent hallucinations.
        """
    }
}
