//
//  Transcriber.swift
//  Wraps WhisperKit. Loads model lazily on first use; subsequent calls reuse.
//

import Foundation
import WhisperKit

enum WhisperModelOption: String, CaseIterable, Identifiable {
    case fast = "openai_whisper-base.en"
    case noiseResistant = "openai_whisper-small.en"
    case maxAccuracy = "openai_whisper-large-v3-v20240930_turbo_632MB"

    static let storageKey = "whisper_model"

    var id: String { rawValue }
    var modelName: String { rawValue }

    var label: String {
        switch self {
        case .fast: return "Fast"
        case .noiseResistant: return "Noise-resistant"
        case .maxAccuracy: return "Max accuracy"
        }
    }

    var detail: String {
        switch self {
        case .fast:
            return "Base English model. Fastest, best for quiet rooms."
        case .noiseResistant:
            return "Small English model. Better with background noise; first use downloads about 244 MB."
        case .maxAccuracy:
            return "Large turbo model. Best accuracy, slower, and first use downloads about 632 MB."
        }
    }

    static var selected: WhisperModelOption {
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? WhisperModelOption.fast.rawValue
        return WhisperModelOption(rawValue: raw) ?? .fast
    }
}

actor Transcriber {

    private var whisperKit: WhisperKit?
    private var loadedModelName: String?

    /// First call downloads the model (~74MB for base.en) to Application
    /// Support. Subsequent calls reuse the local model.
    private func ensureLoaded() async throws {
        let modelName = WhisperModelOption.selected.modelName
        if whisperKit != nil, loadedModelName == modelName { return }
        if whisperKit != nil {
            DebugLog.shared.add("Whisper model changed; reloading \(modelName)")
            whisperKit = nil
            loadedModelName = nil
        }

        let localModelFolder = existingLocalModelFolder(modelName: modelName)
        if let localModelFolder {
            DebugLog.shared.add("Loading local Whisper model: \(localModelFolder.path)")
        } else {
            DebugLog.shared.add("Local Whisper model not found; attempting download for \(modelName)")
        }
        let config = WhisperKitConfig(
            model: localModelFolder == nil ? modelName : nil,
            downloadBase: modelDownloadBase(),
            modelFolder: localModelFolder?.path,
            verbose: false,
            logLevel: .error,
            prewarm: true,
            load: true,
            download: localModelFolder == nil
        )
        whisperKit = try await WhisperKit(config)
        loadedModelName = modelName
        DebugLog.shared.add("WhisperKit loaded with model \(modelName)")
    }

    private func existingLocalModelFolder(modelName: String) -> URL? {
        let folder = modelDownloadBase()
            .appendingPathComponent("argmaxinc", isDirectory: true)
            .appendingPathComponent("whisperkit-coreml", isDirectory: true)
            .appendingPathComponent(modelName, isDirectory: true)

        let requiredModelNames = [
            "MelSpectrogram.mlmodelc",
            "AudioEncoder.mlmodelc",
            "TextDecoder.mlmodelc"
        ]
        let hasRequiredFiles = requiredModelNames.allSatisfy {
            FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path)
        }

        return hasRequiredFiles ? folder : nil
    }

    private func modelDownloadBase() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)

        let base = appSupport
            .appendingPathComponent("Murmur", isDirectory: true)
            .appendingPathComponent("huggingface", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    func transcribe(audioURL: URL) async throws -> String {
        try await ensureLoaded()
        guard let kit = whisperKit else {
            throw NSError(domain: "Transcriber", code: -1)
        }

        DebugLog.shared.add("Calling WhisperKit.transcribe")
        let results = try await kit.transcribe(audioPath: audioURL.path)
        DebugLog.shared.add("WhisperKit returned \(results.count) segment(s)")

        // Clean up the temp file.
        try? FileManager.default.removeItem(at: audioURL)

        // Concatenate segments, strip Whisper's leading space, trim.
        let text = results.map(\.text).joined(separator: " ")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
