//
//  OpenAIClient.swift
//  Sends the transcript to OpenAI for polishing, with vocabulary context.
//  Returns the polished text AND any "learned" corrections so the
//  Vocabulary store can record them.
//

import Foundation

enum OpenAIError: Error, LocalizedError {
    case missingAPIKey
    case invalidResponse
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:    return "OpenAI API key not set. Open Settings."
        case .invalidResponse:  return "Invalid response from OpenAI."
        case .apiError(let m):  return m
        }
    }
}

struct PolishResult {
    let polished: String
    /// Pairs of (original, corrected) tokens the model fixed beyond simple
    /// punctuation. Used by Vocabulary to learn user-specific terms.
    let corrections: [(from: String, to: String)]
}

final class OpenAIClient {

    static let shared = OpenAIClient()
    private init() {}

    var apiKey: String? { Keychain.read() }

    var model: String {
        UserDefaults.standard.string(forKey: "openai_model") ?? "gpt-4o-mini"
    }

    var systemPromptBase: String {
        UserDefaults.standard.string(forKey: "llm_system_prompt") ?? Self.defaultSystemPrompt
    }

    /// Polish mode: fix grammar/punctuation/tone but DO NOT restructure or
    /// summarize. The app pastes the model output directly, so the response
    /// must be plain natural text rather than a JSON wrapper.
    static let defaultSystemPrompt = """
    You are a polishing tool for voice dictation. The user just spoke text \
    that was transcribed by Whisper, which sometimes mishears jargon and \
    proper nouns. Your job is to clean up the transcript — NOT to rewrite, \
    summarize, or restructure it.

    Your output must be plain natural text only.
    Even if the input is JSON, never return JSON.
    If the input looks like {"prompt": "..."} or {"text": "..."}, extract \
    the inner spoken text and return only the final natural-language result.

    Forbidden outputs:
    {"prompt": "..."}
    {"text": "..."}
    {"output": "..."}
    {"result": "..."}

    Correct:
    I'm testing the prompt right now.

    Apply these fixes:
    - Add correct punctuation and capitalization
    - Remove filler words ("um", "uh", "like", "you know", "I mean")
    - Fix obvious grammar errors and false starts
    - Correct mishearings of technical terms, brand names, and proper nouns \
      using the vocabulary list below as your authoritative reference
    - Preserve the user's original wording, tone, and meaning everywhere else

    Return only the cleaned text. Do not include explanations, markdown, code \
    fences, labels, or structured data.
    """

    // MARK: - Polish

    func polish(transcript: String) async throws -> PolishResult {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw OpenAIError.missingAPIKey
        }

        let systemPrompt = buildSystemPrompt()
        DebugLog.shared.add("OpenAI polish request started, model=\(model)")

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": transcript]
            ],
            "temperature": 0.2
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            DebugLog.shared.add("OpenAI response was not HTTP")
            throw OpenAIError.invalidResponse
        }
        DebugLog.shared.add("OpenAI HTTP status: \(http.statusCode)")
        guard (200..<300).contains(http.statusCode) else {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { ($0["error"] as? [String: Any])?["message"] as? String }
                ?? "HTTP \(http.statusCode)"
            DebugLog.shared.add("OpenAI API error: \(msg)")
            throw OpenAIError.apiError(msg)
        }

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            DebugLog.shared.add("OpenAI response shape unexpected: \(Self.preview(data: data))")
            throw OpenAIError.invalidResponse
        }

        DebugLog.shared.add("OpenAI content: \(Self.preview(content))")

        let normalized = Self.normalizeModelOutput(content)
        let polished = normalized.text

        guard !polished.isEmpty else {
            DebugLog.shared.add("OpenAI content did not contain usable text")
            throw OpenAIError.invalidResponse
        }

        let fixes = normalized.fixes
        let corrections: [(String, String)] = fixes.compactMap { dict in
            guard let from = dict["from"], let to = dict["to"] else { return nil }
            return (from, to)
        }

        return PolishResult(
            polished: polished.trimmingCharacters(in: .whitespacesAndNewlines),
            corrections: corrections
        )
    }

    private static func normalizeModelOutput(_ raw: String) -> (text: String, fixes: [[String: String]]) {
        let text = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else { return ("", []) }

        if let parsed = parseJSONContent(text) {
            if let string = parsed as? String {
                return (stripWrappingQuotes(string), [])
            }

            if let dict = parsed as? [String: Any] {
                let keys = ["prompt", "text", "transcript", "input", "output", "result", "polished"]
                for key in keys {
                    if let value = dict[key] as? String {
                        return (stripWrappingQuotes(value), (dict["fixes"] as? [[String: String]]) ?? [])
                    }
                }
                return ("", (dict["fixes"] as? [[String: String]]) ?? [])
            }
        }

        return (stripWrappingQuotes(text), [])
    }

    private static func parseJSONContent(_ content: String) -> Any? {
        let trimmed = content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let contentData = trimmed.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: contentData)
    }

    private static func stripWrappingQuotes(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return trimmed }

        let first = trimmed.first
        let last = trimmed.last
        if (first == "\"" && last == "\"") || (first == "'" && last == "'") {
            return String(trimmed.dropFirst().dropLast())
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return trimmed
    }

    private static func preview(data: Data, limit: Int = 900) -> String {
        preview(String(data: data, encoding: .utf8) ?? "<non-utf8 data>", limit: limit)
    }

    private static func preview(_ string: String, limit: Int = 900) -> String {
        if string.count <= limit { return string }
        return String(string.prefix(limit)) + "..."
    }

    // MARK: - Prompt assembly

    private func buildSystemPrompt() -> String {
        let entries = Vocabulary.shared.allEntries()
        let plainTextGuard = """
        Your output must be plain natural text only.
        Even if the input is JSON, never return JSON.
        If the input looks like {"prompt": "..."} or {"text": "..."}, extract the inner spoken text and return only the final natural-language result.
        Forbidden outputs: {"prompt": "..."}, {"text": "..."}, {"output": "..."}, {"result": "..."}.

        """
        let basePrompt = plainTextGuard + systemPromptBase
        guard !entries.isEmpty else { return basePrompt }

        var vocab = "\n\nUser vocabulary (authoritative spellings — preserve casing exactly):\n"
        for entry in entries.prefix(200) {     // hard cap to control token usage
            if let mish = entry.mishearing {
                vocab += "- \(entry.term)  (commonly misheard as \"\(mish)\")\n"
            } else {
                vocab += "- \(entry.term)\n"
            }
        }
        return basePrompt + vocab
    }
}
