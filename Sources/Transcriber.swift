//
//  Transcriber.swift
//  Wraps WhisperKit. Loads model lazily on first use; subsequent calls reuse.
//

import Foundation
import WhisperKit

private enum TranscriberError: LocalizedError {
    case modelLoadTimedOut(label: String, seconds: UInt64)
    case noModelAvailable

    var errorDescription: String? {
        switch self {
        case .modelLoadTimedOut(let label, let seconds):
            return "\(label) model load timed out after \(seconds) seconds"
        case .noModelAvailable:
            return "No Whisper model was available"
        }
    }
}

private final class ModelDownloadProgressReporter {
    private let label: String
    private let lock = NSLock()
    private var lastBucket = -1
    private var finished = false

    init(label: String) {
        self.label = label
    }

    func start(modelName: String) {
        lock.lock()
        lastBucket = 0
        lock.unlock()
        DebugLog.shared.add("Downloading \(label) model: 0% (\(modelName))")
        publish(percent: 0)
    }

    func update(_ progress: Progress) {
        let fraction = progress.fractionCompleted.isFinite ? progress.fractionCompleted : 0
        let percent = Int((max(0, min(1, fraction)) * 100).rounded(.down))
        let bucket = percent == 100 ? 100 : (percent / 5) * 5

        lock.lock()
        defer { lock.unlock() }
        guard !finished, bucket != lastBucket else {
            return
        }
        lastBucket = bucket

        let amount = ModelFiles.progressAmount(progress)
        DebugLog.shared.add("Downloading \(label) model: \(bucket)%\(amount)")
        publish(percent: bucket)
    }

    func finish(folder: URL) {
        stopUpdates()
        DebugLog.shared.add("Downloading \(label) model: 100% complete at \(folder.path)")
        publish(percent: 100)
        DispatchQueue.main.async {
            StatusBarController.shared.finishModelDownload()
            NotificationCenter.default.post(name: .murmurModelDownloadFinished, object: nil)
        }
    }

    func fail(_ error: Error) {
        stopUpdates()
        DebugLog.shared.add("Downloading \(label) model failed: \(error.localizedDescription)")
        DispatchQueue.main.async {
            StatusBarController.shared.finishModelDownload()
            NotificationCenter.default.post(name: .murmurModelDownloadFinished, object: nil)
        }
    }

    private func stopUpdates() {
        lock.lock()
        finished = true
        lock.unlock()
    }

    private func publish(percent: Int) {
        DispatchQueue.main.async {
            StatusBarController.shared.setModelDownloadProgress(label: self.label, percent: percent)
            NotificationCenter.default.post(
                name: .murmurModelDownloadProgress,
                object: nil,
                userInfo: [
                    ModelDownloadProgressInfo.label: self.label,
                    ModelDownloadProgressInfo.percent: percent
                ]
            )
        }
    }
}

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
        case .noiseResistant: return "Noisy room"
        case .maxAccuracy: return "Best quality"
        }
    }

    var detail: String {
        switch self {
        case .fast:
            return "Fastest local model. Best for quiet English dictation and short everyday notes."
        case .noiseResistant:
            return "More accurate in background noise. Slower than Fast, but better for longer English dictation."
        case .maxAccuracy:
            return "Highest local accuracy. Best for difficult audio, accents, and noisy environments."
        }
    }

    var downloadSize: String {
        switch self {
        case .fast:
            return "~142 MB"
        case .noiseResistant:
            return "~244 MB"
        case .maxAccuracy:
            return "~632 MB"
        }
    }

    var speedSummary: String {
        switch self {
        case .fast:
            return "Fastest"
        case .noiseResistant:
            return "Balanced"
        case .maxAccuracy:
            return "Slowest"
        }
    }

    var accuracySummary: String {
        switch self {
        case .fast:
            return "Good in quiet rooms"
        case .noiseResistant:
            return "Better with noise"
        case .maxAccuracy:
            return "Best quality"
        }
    }

    var languageSupport: String {
        switch self {
        case .fast, .noiseResistant:
            return "English only"
        case .maxAccuracy:
            return "Auto-detects supported languages"
        }
    }

    var decodeOptions: DecodingOptions? {
        switch self {
        case .fast, .noiseResistant:
            return nil
        case .maxAccuracy:
            return DecodingOptions(detectLanguage: true)
        }
    }

    var fallbackChain: [WhisperModelOption] {
        switch self {
        case .fast:
            return [.fast]
        case .noiseResistant:
            return [.noiseResistant, .fast]
        case .maxAccuracy:
            return [.maxAccuracy, .noiseResistant, .fast]
        }
    }

    static var selected: WhisperModelOption {
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? WhisperModelOption.fast.rawValue
        return WhisperModelOption(rawValue: raw) ?? .fast
    }
}

actor Transcriber {

    private static let localLoadTimeoutSeconds: UInt64 = 20
    private static let gpuLoadTimeoutSeconds: UInt64 = 120
    private static let downloadTimeoutSeconds: UInt64 = 900

    private var whisperKit: WhisperKit?
    private var loadedModelName: String?
    private var loadedOption: WhisperModelOption?
    private let preparations = InFlightModelTasks<WhisperKit>()
    private let compilations = InFlightModelTasks<WhisperKit>()
    private let modelSelection: @Sendable () -> WhisperModelOption

    init(modelSelection: @escaping @Sendable () -> WhisperModelOption = { .selected }) {
        self.modelSelection = modelSelection
    }

    func preloadSelectedModel() async {
        let selected = modelSelection()
        DebugLog.shared.add("Preparing transcription model: \(selected.label) (\(selected.modelName))")
        do {
            try await ensureLoaded(allowDownload: true, purpose: "preload")
            let active = loadedOption?.label ?? selected.label
            if active == selected.label {
                DebugLog.shared.add("Transcription model ready: \(active)")
            } else {
                DebugLog.shared.add("Transcription model ready via fallback: \(active) for requested \(selected.label)")
            }
        } catch {
            DebugLog.shared.add("Transcription model preload failed: \(error.localizedDescription)")
        }
    }

    /// Preload may download the requested model. Active dictation avoids large
    /// downloads when a local fallback can keep the user moving.
    private func ensureLoaded(allowDownload: Bool, purpose: String) async throws {
        let selected = modelSelection()
        let downloadState = allowDownload ? "allowed" : "deferred"
        DebugLog.shared.add("Transcription model request: \(selected.label), purpose=\(purpose), downloads=\(downloadState)")

        if whisperKit != nil, loadedModelName == selected.modelName {
            DebugLog.shared.add("Selected transcription model already loaded: \(selected.label)")
            return
        }

        if let loadedOption {
            DebugLog.shared.add("Selected transcription model is \(selected.label); currently loaded model is \(loadedOption.label)")
        }

        var lastError: Error?
        var attemptedFast = false
        for option in selected.fallbackChain {
            if whisperKit != nil, loadedModelName == option.modelName {
                DebugLog.shared.add("Using already-loaded transcription model: \(option.label)")
                return
            }

            let localModelFolder = existingLocalModelFolder(modelName: option.modelName)
            if !allowDownload, localModelFolder == nil {
                DebugLog.shared.add("Skipping \(option.label) download during \(purpose); model is not local yet")
                continue
            }
            if option == .fast { attemptedFast = true }

            do {
                let kit = try await loadWhisperKit(
                    option: option,
                    requested: selected,
                    localModelFolder: localModelFolder,
                    allowDownload: allowDownload
                )
                whisperKit = kit
                loadedModelName = option.modelName
                loadedOption = option
                if option == selected {
                    DebugLog.shared.add("WhisperKit loaded with selected model: \(option.label) (\(option.modelName))")
                } else {
                    DebugLog.shared.add("WhisperKit fallback active: using \(option.label) because \(selected.label) was unavailable")
                }
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                DebugLog.shared.add("Whisper model load failed for \(option.label): \(error.localizedDescription)")
            }
        }

        if let loadedOption, whisperKit != nil {
            DebugLog.shared.add("Using previous loaded model after \(selected.label) was unavailable: \(loadedOption.label)")
            return
        }

        if !allowDownload, !attemptedFast {
            DebugLog.shared.add("No local transcription model available for dictation; downloading Fast emergency model")
            do {
                let emergency = WhisperModelOption.fast
                let kit = try await loadWhisperKit(
                    option: emergency,
                    requested: selected,
                    localModelFolder: existingLocalModelFolder(modelName: emergency.modelName),
                    allowDownload: true
                )
                whisperKit = kit
                loadedModelName = emergency.modelName
                loadedOption = emergency
                DebugLog.shared.add("Emergency transcription fallback ready: \(emergency.label)")
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                DebugLog.shared.add("Emergency Fast model load failed: \(error.localizedDescription)")
            }
        }

        throw lastError ?? TranscriberError.noModelAvailable
    }

    private func loadWhisperKit(
        option: WhisperModelOption,
        requested: WhisperModelOption,
        localModelFolder: URL?,
        allowDownload: Bool
    ) async throws -> WhisperKit {
        try await preparations.value(for: option.modelName) {
            try await self.prepareWhisperKit(
                option: option, requested: requested,
                localModelFolder: localModelFolder, allowDownload: allowDownload
            )
        }
    }

    private func prepareWhisperKit(
        option: WhisperModelOption,
        requested: WhisperModelOption,
        localModelFolder: URL?,
        allowDownload: Bool
    ) async throws -> WhisperKit {
        let modelName = option.modelName
        let modelFolder: URL
        if let localModelFolder {
            DebugLog.shared.add("Loading local Whisper model \(option.label): \(localModelFolder.path)")
            modelFolder = localModelFolder
        } else {
            let fallbackNote = option == requested ? "" : " as fallback for \(requested.label)"
            DebugLog.shared.add("Local Whisper model not found; attempting download for \(option.label)\(fallbackNote): \(modelName)")
            guard allowDownload else {
                throw TranscriberError.noModelAvailable
            }
            modelFolder = try await downloadModel(option: option, requested: requested)
        }
        // This compressed large model can stall ANE compilation and block other Core ML loads.
        if option == .maxAccuracy {
            return try await compileModel(option: option, folder: modelFolder, useGPU: true)
        }
        do {
            return try await compileModel(option: option, folder: modelFolder, useGPU: false)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            DebugLog.shared.add("\(option.label) model load failed: \(error.localizedDescription); retrying the same model on CPU/GPU")
            return try await compileModel(option: option, folder: modelFolder, useGPU: true)
        }
    }

    private func compileModel(option: WhisperModelOption, folder: URL, useGPU: Bool) async throws -> WhisperKit {
        let backend = useGPU ? "CPU/GPU" : "Neural Engine"
        let seconds = useGPU ? Self.gpuLoadTimeoutSeconds : Self.localLoadTimeoutSeconds
        let tasks = compilations
        let downloadBase = modelDownloadBase()
        DebugLog.shared.add("Loading \(option.label) model on \(backend) (timeout: \(seconds)s)")
        let kit = try await withModelLoadTimeout(seconds: seconds, label: "\(option.label) (\(backend))") {
            try await tasks.value(for: "\(option.modelName):\(backend)") {
                let config = WhisperKitConfig(
                    model: nil,
                    downloadBase: downloadBase,
                    modelFolder: folder.path,
                    computeOptions: useGPU ? ModelComputeOptions(
                        audioEncoderCompute: .cpuAndGPU, textDecoderCompute: .cpuAndGPU
                    ) : nil,
                    verbose: false,
                    logLevel: .error,
                    prewarm: !useGPU,
                    load: true,
                    download: false
                )
                return try await WhisperKit(config)
            }
        }
        DebugLog.shared.add("Loaded \(option.label) model on \(backend)")
        return kit
    }

    private func downloadModel(option: WhisperModelOption, requested: WhisperModelOption) async throws -> URL {
        let reporter = ModelDownloadProgressReporter(label: option.label)
        let downloadBase = modelDownloadBase()
        reporter.start(modelName: option.modelName)
        do {
            let folder = try await withModelLoadTimeout(seconds: Self.downloadTimeoutSeconds, label: option.label) {
                try await WhisperKit.download(
                    variant: option.modelName,
                    downloadBase: downloadBase,
                    from: "argmaxinc/whisperkit-coreml",
                    progressCallback: { progress in
                        reporter.update(progress)
                    }
                )
            }
            reporter.finish(folder: folder)
            if option != requested {
                DebugLog.shared.add("Downloaded fallback \(option.label) for requested \(requested.label)")
            }
            return folder
        } catch {
            reporter.fail(error)
            throw error
        }
    }

    private func existingLocalModelFolder(modelName: String) -> URL? {
        ModelFiles.existingFolder(downloadBase: modelDownloadBase(), modelName: modelName)
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
        try await ensureLoaded(allowDownload: false, purpose: "dictation")
        guard let kit = whisperKit else {
            throw TranscriberError.noModelAvailable
        }

        let modelLabel = loadedOption?.label ?? loadedModelName ?? "<unknown>"
        DebugLog.shared.add("Calling WhisperKit.transcribe with model \(modelLabel)")
        do {
            let text = try await transcribeOnce(
                using: kit,
                audioURL: audioURL,
                modelLabel: modelLabel,
                modelOption: loadedOption
            )
            if !text.isEmpty {
                return text
            }

            DebugLog.shared.add("WhisperKit returned empty text; checking for a local higher-quality retry")
            if let retry = higherQualityLocalRetry(after: loadedOption) {
                return try await retryEmptyTranscription(
                    audioURL: audioURL,
                    option: retry.option,
                    localModelFolder: retry.localModelFolder,
                    previousKit: kit,
                    previousOption: loadedOption,
                    previousModelName: loadedModelName
                )
            }

            DebugLog.shared.add("No local higher-quality retry model available; empty transcription will be ignored")
            return text
        } catch {
            DebugLog.shared.add("WhisperKit transcription failed with \(loadedOption?.label ?? "current model"): \(error.localizedDescription)")
            throw error
        }
    }

    func currentModelLabel() -> String {
        loadedOption?.label ?? modelSelection().label
    }

    private func transcribeOnce(
        using kit: WhisperKit,
        audioURL: URL,
        modelLabel: String,
        modelOption: WhisperModelOption?
    ) async throws -> String {
        if modelOption == .maxAccuracy {
            DebugLog.shared.add("Language auto-detect enabled for Best quality")
        }
        let results = try await kit.transcribe(audioPath: audioURL.path, decodeOptions: modelOption?.decodeOptions)
        DebugLog.shared.add("WhisperKit returned \(results.count) segment(s) from \(modelLabel)")
        let languages = Array(Set(results.map(\.language))).sorted()
        if !languages.isEmpty {
            DebugLog.shared.add("WhisperKit language result: \(languages.joined(separator: ", "))")
        }
        let text = results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            DebugLog.shared.add("WhisperKit output was empty from \(modelLabel)")
        }
        return text
    }

    private func retryEmptyTranscription(
        audioURL: URL,
        option: WhisperModelOption,
        localModelFolder: URL,
        previousKit: WhisperKit,
        previousOption: WhisperModelOption?,
        previousModelName: String?
    ) async throws -> String {
        DebugLog.shared.add("Retrying empty transcription with local \(option.label) model")
        do {
            let retryKit = try await loadWhisperKit(
                option: option,
                requested: modelSelection(),
                localModelFolder: localModelFolder,
                allowDownload: false
            )
            whisperKit = retryKit
            loadedModelName = option.modelName
            loadedOption = option
            let retryText = try await transcribeOnce(
                using: retryKit,
                audioURL: audioURL,
                modelLabel: option.label,
                modelOption: option
            )
            if retryText.isEmpty {
                DebugLog.shared.add("Higher-quality retry also returned empty text")
            } else {
                DebugLog.shared.add("Higher-quality retry recovered \(retryText.count) character(s)")
            }
            return retryText
        } catch {
            whisperKit = previousKit
            loadedOption = previousOption
            loadedModelName = previousModelName
            DebugLog.shared.add("Higher-quality retry failed; restored previous model: \(error.localizedDescription)")
            return ""
        }
    }

    private func higherQualityLocalRetry(after option: WhisperModelOption?) -> (option: WhisperModelOption, localModelFolder: URL)? {
        let qualityOrder: [WhisperModelOption] = [.fast, .noiseResistant, .maxAccuracy]
        let currentIndex = option.flatMap { qualityOrder.firstIndex(of: $0) } ?? -1
        for candidate in qualityOrder.dropFirst(currentIndex + 1) {
            if let folder = existingLocalModelFolder(modelName: candidate.modelName) {
                DebugLog.shared.add("Local retry candidate found: \(candidate.label)")
                return (candidate, folder)
            }
        }
        return nil
    }

    private nonisolated func withModelLoadTimeout<T>(
        seconds: UInt64,
        label: String,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withAsyncTimeout(
            nanoseconds: seconds * 1_000_000_000,
            timeoutError: TranscriberError.modelLoadTimedOut(label: label, seconds: seconds),
            operation: operation
        )
    }
}
