//
//  Transcriber.swift
//  Wraps WhisperKit. Loads model lazily on first use; subsequent calls reuse.
//

import Foundation
import WhisperKit

actor Transcriber {

    private var whisperKit: WhisperKit?

    /// English-only model. distil-large-v3 is a 6x smaller, 6x faster
    /// distilled version of large-v3 with negligible accuracy loss.
    /// Other choices: "openai_whisper-base.en" (74MB, fastest),
    /// "openai_whisper-small.en" (244MB), "openai_whisper-large-v3-turbo".
    private let modelName: String

    init(modelName: String = "openai_whisper-base.en") {
        self.modelName = modelName
    }

    /// First call downloads the model (~74MB for base.en) to
    /// ~/Library/Application Support/. Subsequent calls are instant.
    private func ensureLoaded() async throws {
        if whisperKit != nil { return }

        let config = WhisperKitConfig(
            model: modelName,
            verbose: false,
            logLevel: .error,
            prewarm: true,
            load: true,
            download: true
        )
        whisperKit = try await WhisperKit(config)
    }

    func transcribe(audioURL: URL) async throws -> String {
        try await ensureLoaded()
        guard let kit = whisperKit else {
            throw NSError(domain: "Transcriber", code: -1)
        }

        let results = try await kit.transcribe(audioPath: audioURL.path)

        // Clean up the temp file.
        try? FileManager.default.removeItem(at: audioURL)

        // Concatenate segments, strip Whisper's leading space, trim.
        let text = results.map(\.text).joined(separator: " ")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
