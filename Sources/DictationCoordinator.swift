//
//  DictationCoordinator.swift
//  Pipeline: hotkey -> record -> transcribe -> (LLM polish + learn) -> paste.
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
    private var targetApp: NSRunningApplication?

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

    func beginMouseDictation(mode: DictationMode) {
        DebugLog.shared.add("Mouse dictation begin requested, mode=\(mode == .raw ? "raw" : "llm")")
        handlePress(mode)
    }

    func endMouseDictation(mode: DictationMode) {
        DebugLog.shared.add("Mouse dictation end requested, mode=\(mode == .raw ? "raw" : "llm")")
        handleRelease(mode)
    }

    private func handlePress(_ mode: DictationMode) {
        guard activeMode == nil else {
            DebugLog.shared.add("Ignoring press; already recording/processing mode=\(String(describing: activeMode))")
            return
        }
        activeMode = mode
        targetApp = currentTargetApp()
        DebugLog.shared.add("Recording started, mode=\(mode == .raw ? "raw" : "llm")")
        if let targetApp {
            DebugLog.shared.add("Target app captured: \(targetApp.localizedName ?? targetApp.bundleIdentifier ?? "<unknown>")")
        } else {
            DebugLog.shared.add("No non-Murmur target app captured; paste will use current frontmost app")
        }
        onStateChange?(.recording(mode))
        StatusBarController.shared.setRecording(true, mode: mode)
        recorder.start()
    }

    private func handleRelease(_ mode: DictationMode) {
        guard mode == activeMode else {
            DebugLog.shared.add("Ignoring release for mode=\(mode == .raw ? "raw" : "llm"); activeMode=\(String(describing: activeMode))")
            return
        }
        activeMode = nil
        DebugLog.shared.add("Recording release accepted; stopping recorder")
        onStateChange?(.processing)
        StatusBarController.shared.setProcessing(true)

        recorder.stop { [weak self] audioURL in
            guard let self, let audioURL else {
                DebugLog.shared.add("Recorder returned no usable audio file")
                self?.onStateChange?(.error("Recording failed"))
                StatusBarController.shared.setError("Recording failed")
                return
            }
            DebugLog.shared.add("Recorder returned audio file: \(audioURL.path)")
            Task {
                await self.process(audioURL: audioURL, mode: mode)
            }
        }
    }

    private func process(audioURL: URL, mode: DictationMode) async {
        do {
            DebugLog.shared.add("Transcription started")
            let transcript = try await transcriber.transcribe(audioURL: audioURL)
            DebugLog.shared.add("Transcription finished: \(transcript.isEmpty ? "<empty>" : transcript)")
            guard !transcript.isEmpty else {
                onStateChange?(.idle)
                StatusBarController.shared.setIdle()
                return
            }

            let finalText: String
            switch mode {
            case .raw:
                finalText = transcript

            case .llm:
                let result = try await OpenAIClient.shared.polish(transcript: transcript)
                finalText = result.polished

                // Feed any non-trivial corrections back into the vocabulary.
                // No-op when "Learn from corrections" is disabled in settings.
                for fix in result.corrections {
                    Vocabulary.shared.recordLearned(
                        mishearing: fix.from,
                        correction: fix.to
                    )
                }
            }

            ClipboardWriter.copy(finalText, autoPaste: autoPaste, targetApp: targetApp)
            DebugLog.shared.add("Copied final text; autoPaste=\(autoPaste)")
            onStateChange?(.idle)
            StatusBarController.shared.setIdle()

        } catch {
            DebugLog.shared.add("Pipeline error: \(error.localizedDescription)")
            onStateChange?(.error(error.localizedDescription))
            StatusBarController.shared.setError(error.localizedDescription)
            print("Pipeline error: \(error)")
        }
    }

    private func currentTargetApp() -> NSRunningApplication? {
        let app = NSWorkspace.shared.frontmostApplication
        let ownBundleID = Bundle.main.bundleIdentifier
        if app?.bundleIdentifier == ownBundleID { return nil }
        return app
    }
}
