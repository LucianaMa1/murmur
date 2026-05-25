//
//  DictationCoordinator.swift
//  Pipeline: hotkey -> record -> transcribe -> optional LLM polish -> paste.
//

import Cocoa

enum DictationCoordinatorState {
    case idle
    case recording(DictationMode)
    case processing
    case error(String)
}

@MainActor
final class DictationCoordinator {

    private let recorder = AudioRecorder()
    private let transcriber = Transcriber()
    private let hotkeys = HotkeyManager()
    private var activeMode: DictationMode?
    private var isProcessing = false
    private var currentSessionID: UUID?
    private var targetApp: NSRunningApplication?
    private var selectedContext: String?
    private var activeStyleProfile: StyleProfile?

    var onStateChange: ((DictationCoordinatorState) -> Void)?

    var autoPaste: Bool {
        if UserDefaults.standard.object(forKey: "auto_paste") == nil { return true }
        return UserDefaults.standard.bool(forKey: "auto_paste")
    }

    func start() {
        hotkeys.onPress = { [weak self] mode in self?.handlePress(mode) }
        hotkeys.onRelease = { [weak self] mode in self?.handleRelease(mode) }
        DebugLog.shared.add("Starting hotkey manager")
        if !hotkeys.start() {
            DebugLog.shared.add("Hotkey manager failed: Input Monitoring permission required")
            StatusBarController.shared.setError("Input Monitoring permission required")
        } else {
            DebugLog.shared.add("Hotkey manager started")
        }
    }

    func stop() {
        DebugLog.shared.add("Stopping coordinator")
        hotkeys.stop()
    }

    func preloadTranscriptionModel() {
        Task {
            await transcriber.preloadSelectedModel()
        }
    }

    func beginMouseDictation(mode: DictationMode) {
        DebugLog.shared.add("Mouse dictation begin requested, mode=\(mode == .raw ? "raw" : "llm")")
        handlePress(mode)
    }

    func endMouseDictation(mode: DictationMode) {
        DebugLog.shared.add("Mouse dictation end requested, mode=\(mode == .raw ? "raw" : "llm")")
        handleRelease(mode)
    }

    private func handlePress(_ mode: DictationMode) {
        guard activeMode == nil, !isProcessing else {
            DebugLog.shared.add("Ignoring press; already recording or processing mode=\(String(describing: activeMode))")
            return
        }
        let sessionID = UUID()
        activeMode = mode
        currentSessionID = sessionID
        targetApp = currentTargetApp()
        selectedContext = nil
        activeStyleProfile = nil
        DebugLog.shared.add("Recording started, mode=\(mode == .raw ? "raw" : "llm")")
        if let targetApp {
            DebugLog.shared.add("Target app captured: \(targetApp.localizedName ?? targetApp.bundleIdentifier ?? "<unknown>")")
        } else {
            DebugLog.shared.add("No non-Murmur target app captured; paste will use current frontmost app")
        }

        startRecording(mode)

        if mode == .llm {
            let active = StyleProfileStore.activeCategory(for: targetApp)
            activeStyleProfile = StyleProfileStore.profile(for: active.category)
            if let activeStyleProfile {
                DebugLog.shared.add("AI mode style profile: \(activeStyleProfile.category.label) via \(active.reason) for \(active.appDescription)")
                DebugLog.shared.add("AI mode style settings: tone=\(activeStyleProfile.tone.label), length=\(activeStyleProfile.length.label), habitChars=\(activeStyleProfile.habit.count)")
            }
            SelectionReader.selectedText(in: targetApp) { [weak self] context in
                Task { @MainActor in
                    guard let self, self.currentSessionID == sessionID else { return }
                    self.selectedContext = context
                    if let context {
                        DebugLog.shared.add("AI mode captured selected context with \(context.count) character(s)")
                    } else {
                        DebugLog.shared.add("AI mode proceeding without selected context")
                    }
                }
            }
        }
    }

    private func startRecording(_ mode: DictationMode) {
        onStateChange?(.recording(mode))
        StatusBarController.shared.setRecording(true, mode: mode)
        recorder.start()
    }

    private func handleRelease(_ mode: DictationMode) {
        guard mode == activeMode else {
            DebugLog.shared.add("Ignoring release for mode=\(mode == .raw ? "raw" : "llm"); activeMode=\(String(describing: activeMode))")
            return
        }
        let sessionID = currentSessionID
        activeMode = nil
        isProcessing = true
        DebugLog.shared.add("Recording release accepted; stopping recorder")
        onStateChange?(.processing)
        StatusBarController.shared.setProcessing(true)

        recorder.stop { [weak self] audioURL in
            guard let self, let audioURL else {
                DebugLog.shared.add("Recorder returned no usable audio file")
                self?.isProcessing = false
                self?.currentSessionID = nil
                self?.selectedContext = nil
                self?.onStateChange?(.error("Recording failed"))
                StatusBarController.shared.setError("Recording failed")
                return
            }
            DebugLog.shared.add("Recorder returned audio file: \(audioURL.path)")
            Task {
                await self.process(audioURL: audioURL, mode: mode, sessionID: sessionID)
            }
        }
    }

    private func process(audioURL: URL, mode: DictationMode, sessionID: UUID?) async {
        var transcriptionCompleted = false
        do {
            DebugLog.shared.add("Transcription started")
            let transcript = try await transcriber.transcribe(audioURL: audioURL)
            DebugLog.shared.add("Transcription finished with \(transcript.count) character(s)")
            guard !transcript.isEmpty else {
                let modelLabel = await transcriber.currentModelLabel()
                FailedRecordingStore.preserve(
                    audioURL: audioURL,
                    reason: "empty_transcription",
                    mode: mode,
                    modelLabel: modelLabel,
                    targetApp: targetApp
                )
                finishSession(sessionID)
                onStateChange?(.idle)
                StatusBarController.shared.setIdle()
                return
            }
            transcriptionCompleted = true
            try? FileManager.default.removeItem(at: audioURL)

            let finalText: String
            switch mode {
            case .raw:
                finalText = transcript

            case .llm:
                let result = try await OpenAIClient.shared.polish(
                    transcript: transcript,
                    selectedContext: selectedContext,
                    styleProfile: activeStyleProfile
                )
                finalText = result.polished

            }

            ClipboardWriter.copy(finalText, autoPaste: autoPaste, targetApp: targetApp)
            finishSession(sessionID)
            DebugLog.shared.add("Copied final text; autoPaste=\(autoPaste)")
            onStateChange?(.idle)
            StatusBarController.shared.setIdle()

        } catch {
            if !transcriptionCompleted {
                let modelLabel = await transcriber.currentModelLabel()
                FailedRecordingStore.preserve(
                    audioURL: audioURL,
                    reason: "transcription_failed",
                    mode: mode,
                    modelLabel: modelLabel,
                    targetApp: targetApp
                )
            } else {
                try? FileManager.default.removeItem(at: audioURL)
            }
            DebugLog.shared.add("Pipeline error: \(error.localizedDescription)")
            onStateChange?(.error(error.localizedDescription))
            StatusBarController.shared.setError(error.localizedDescription)
            finishSession(sessionID)
            print("Pipeline error: \(error)")
        }
    }

    private func finishSession(_ sessionID: UUID?) {
        if currentSessionID == sessionID {
            currentSessionID = nil
        }
        isProcessing = false
        selectedContext = nil
        activeStyleProfile = nil
    }

    private func currentTargetApp() -> NSRunningApplication? {
        let app = NSWorkspace.shared.frontmostApplication
        let ownBundleID = Bundle.main.bundleIdentifier
        if app?.bundleIdentifier == ownBundleID { return nil }
        return app
    }
}
