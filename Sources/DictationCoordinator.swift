//
//  DictationCoordinator.swift
//  Pipeline: hotkey -> record -> transcribe -> (LLM polish + learn) -> paste.
//

import Cocoa

@MainActor
final class DictationCoordinator {

    private let recorder = AudioRecorder()
    private let transcriber = Transcriber()
    private let hotkeys = HotkeyManager()
    private var activeMode: DictationMode?

    var autoPaste: Bool {
        if UserDefaults.standard.object(forKey: "auto_paste") == nil { return true }
        return UserDefaults.standard.bool(forKey: "auto_paste")
    }

    func start() {
        hotkeys.onPress = { [weak self] mode in self?.handlePress(mode) }
        hotkeys.onRelease = { [weak self] mode in self?.handleRelease(mode) }
        if !hotkeys.start() {
            StatusBarController.shared.setError("Input Monitoring permission required")
        }
    }

    func stop() { hotkeys.stop() }

    private func handlePress(_ mode: DictationMode) {
        guard activeMode == nil else { return }
        activeMode = mode
        StatusBarController.shared.setRecording(true, mode: mode)
        recorder.start()
    }

    private func handleRelease(_ mode: DictationMode) {
        guard mode == activeMode else { return }
        activeMode = nil
        StatusBarController.shared.setProcessing(true)

        recorder.stop { [weak self] audioURL in
            guard let self, let audioURL else {
                StatusBarController.shared.setError("Recording failed")
                return
            }
            Task {
                await self.process(audioURL: audioURL, mode: mode)
            }
        }
    }

    private func process(audioURL: URL, mode: DictationMode) async {
        do {
            let transcript = try await transcriber.transcribe(audioURL: audioURL)
            guard !transcript.isEmpty else {
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

            ClipboardWriter.copy(finalText, autoPaste: autoPaste)
            StatusBarController.shared.setIdle()

        } catch {
            StatusBarController.shared.setError(error.localizedDescription)
            print("Pipeline error: \(error)")
        }
    }
}
