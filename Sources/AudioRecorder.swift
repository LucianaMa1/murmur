//
//  AudioRecorder.swift
//  Records microphone audio at 16kHz mono — the format Whisper expects.
//

import AVFoundation

final class AudioRecorder {

    private let engine = AVAudioEngine()
    private var outputFile: AVAudioFile?
    private var outputURL: URL?

    /// Whisper expects 16kHz mono. We'll write to a temporary WAV file.
    private let targetSampleRate: Double = 16_000

    func start() {
        // Reset any previous session.
        if engine.isRunning { engine.stop() }
        engine.reset()

        // Request mic permission if needed (will silently no-op if granted).
        AVCaptureDevice.requestAccess(for: .audio) { _ in }

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)

        // Target format: 16kHz, 16-bit, mono PCM.
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: true
        ) else {
            print("❌ Failed to create target audio format.")
            return
        }

        // Resampler: input device's native rate -> 16kHz mono.
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            print("❌ Failed to create audio converter.")
            return
        }

        // Output file in temp dir.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wf-\(UUID().uuidString).wav")
        self.outputURL = url

        do {
            outputFile = try AVAudioFile(forWriting: url,
                                         settings: outputFormat.settings,
                                         commonFormat: .pcmFormatInt16,
                                         interleaved: true)
        } catch {
            print("❌ Failed to open output file: \(error)")
            return
        }

        // Tap the mic, convert each buffer, write it.
        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self, let outFile = self.outputFile else { return }

            let frameCapacity = AVAudioFrameCount(
                Double(buffer.frameLength) * self.targetSampleRate / inputFormat.sampleRate
            )
            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: frameCapacity
            ) else { return }

            var error: NSError?
            var inputProvided = false
            converter.convert(to: convertedBuffer, error: &error) { _, status in
                if inputProvided {
                    status.pointee = .noDataNow
                    return nil
                }
                inputProvided = true
                status.pointee = .haveData
                return buffer
            }

            if let error = error {
                print("Conversion error: \(error)")
                return
            }

            do {
                try outFile.write(from: convertedBuffer)
            } catch {
                print("Write error: \(error)")
            }
        }

        do {
            try engine.start()
        } catch {
            print("❌ Failed to start engine: \(error)")
        }
    }

    func stop(_ completion: @escaping (URL?) -> Void) {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        // Close the file by releasing it (AVAudioFile flushes on dealloc).
        outputFile = nil

        let url = outputURL
        outputURL = nil

        // Brief delay to ensure file is fully flushed to disk.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            // Sanity check: file exists and isn't empty.
            if let url = url,
               let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? Int, size > 1024 {
                completion(url)
            } else {
                completion(nil)
            }
        }
    }
}
