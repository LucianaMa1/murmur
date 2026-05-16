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
        let permission = AVCaptureDevice.authorizationStatus(for: .audio)
        DebugLog.shared.add("Microphone permission status: \(permission.debugName)")
        switch permission {
        case .notDetermined:
            DebugLog.shared.add("Requesting microphone permission")
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DebugLog.shared.add("Microphone permission response: \(granted ? "granted" : "denied")")
                guard granted else { return }
                DispatchQueue.main.async {
                    self?.start()
                }
            }
            return

        case .denied, .restricted:
            DebugLog.shared.add("Microphone permission is not granted; recorder will not start")
            return

        case .authorized:
            break

        @unknown default:
            DebugLog.shared.add("Unknown microphone permission status; attempting to record")
        }

        // Reset any previous session.
        if engine.isRunning { engine.stop() }
        engine.reset()

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        DebugLog.shared.add("Input format: \(inputFormat.sampleRate) Hz, \(inputFormat.channelCount) channel(s)")

        // Target format: 16kHz, 16-bit, mono PCM.
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: true
        ) else {
            DebugLog.shared.add("Failed to create target audio format")
            print("❌ Failed to create target audio format.")
            return
        }

        // Resampler: input device's native rate -> 16kHz mono.
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            DebugLog.shared.add("Failed to create audio converter")
            print("❌ Failed to create audio converter.")
            return
        }

        // Output file in temp dir.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wf-\(UUID().uuidString).wav")
        self.outputURL = url

        let fileSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: targetSampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        do {
            outputFile = try AVAudioFile(forWriting: url,
                                         settings: fileSettings,
                                         commonFormat: .pcmFormatInt16,
                                         interleaved: true)
            DebugLog.shared.add("Opened audio output file: \(url.path)")
        } catch {
            DebugLog.shared.add("Failed to open output file: \(error.localizedDescription)")
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
                DebugLog.shared.add("Audio conversion error: \(error.localizedDescription)")
                print("Conversion error: \(error)")
                return
            }

            do {
                try outFile.write(from: convertedBuffer)
            } catch {
                DebugLog.shared.add("Audio write error: \(error.localizedDescription)")
                print("Write error: \(error)")
            }
        }
        DebugLog.shared.add("Microphone tap installed")

        do {
            try engine.start()
            DebugLog.shared.add("Audio engine started")
        } catch {
            DebugLog.shared.add("Failed to start audio engine: \(error.localizedDescription)")
            print("❌ Failed to start engine: \(error)")
        }
    }

    func stop(_ completion: @escaping (URL?) -> Void) {
        DebugLog.shared.add("Audio recorder stop requested")
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
                DebugLog.shared.add("Audio file size: \(size) bytes")
                completion(url)
            } else {
                let path = url?.path ?? "<nil>"
                DebugLog.shared.add("Audio file missing or too small: \(path)")
                completion(nil)
            }
        }
    }
}

private extension AVAuthorizationStatus {
    var debugName: String {
        switch self {
        case .notDetermined: return "notDetermined"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .authorized: return "authorized"
        @unknown default: return "unknown"
        }
    }
}
