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
    /// summarize. We additionally ask the model to return its corrections
    /// in a structured form so we can learn from them.
    static let defaultSystemPrompt = """
    You are a polishing tool for voice dictation. The user just spoke text \
    that was transcribed by Whisper, which sometimes mishears jargon and \
    proper nouns. Your job is to clean up the transcript — NOT to rewrite, \
    summarize, or restructure it.

    Apply these fixes:
    - Add correct punctuation and capitalization
    - Remove filler words ("um", "uh", "like", "you know", "I mean")
    - Fix obvious grammar errors and false starts
    - Correct mishearings of technical terms, brand names, and proper nouns \
      using the vocabulary list below as your authoritative reference
    - Preserve the user's original wording, tone, and meaning everywhere else

    Respond with EXACTLY this JSON shape and nothing else:
    {
      "polished": "<the cleaned-up text>",
      "fixes": [
        {"from": "<word as transcribed>", "to": "<word it should be>"}
      ]
    }

    Only include entries in "fixes" for non-trivial substitutions you made \
    (e.g. "cubicle" → "kubectl"). Do not include punctuation/capitalization \
    fixes. If you made no such substitutions, "fixes" is an empty array.
    """

    // MARK: - Polish

    func polish(transcript: String) async throws -> PolishResult {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw OpenAIError.missingAPIKey
        }

        let systemPrompt = buildSystemPrompt()

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
            "temperature": 0.2,
            "response_format": ["type": "json_object"]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw OpenAIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { ($0["error"] as? [String: Any])?["message"] as? String }
                ?? "HTTP \(http.statusCode)"
            throw OpenAIError.apiError(msg)
        }

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String,
            let contentData = content.data(using: .utf8),
            let inner = try? JSONSerialization.jsonObject(with: contentData) as? [String: Any],
            let polished = inner["polished"] as? String
        else {
            throw OpenAIError.invalidResponse
        }

        let fixes = (inner["fixes"] as? [[String: String]]) ?? []
        let corrections: [(String, String)] = fixes.compactMap { dict in
            guard let from = dict["from"], let to = dict["to"] else { return nil }
            return (from, to)
        }

        return PolishResult(
            polished: polished.trimmingCharacters(in: .whitespacesAndNewlines),
            corrections: corrections
        )
    }

    // MARK: - Prompt assembly

    private func buildSystemPrompt() -> String {
        let entries = Vocabulary.shared.allEntries()
        guard !entries.isEmpty else { return systemPromptBase }

        var vocab = "\n\nUser vocabulary (authoritative spellings — preserve casing exactly):\n"
        for entry in entries.prefix(200) {     // hard cap to control token usage
            if let mish = entry.mishearing {
                vocab += "- \(entry.term)  (commonly misheard as \"\(mish)\")\n"
            } else {
                vocab += "- \(entry.term)\n"
            }
        }
        return systemPromptBase + vocab
    }
}
