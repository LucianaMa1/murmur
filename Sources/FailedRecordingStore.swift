//
//  FailedRecordingStore.swift
//  Preserves audio only when transcription fails, so the spoken input is not lost.
//

import AppKit
import Foundation

enum FailedRecordingStore {
    private static let maxRecordings = 10
    private static let maxAge: TimeInterval = 7 * 24 * 60 * 60
    private static let sampleRate = 16_000.0
    private static let bytesPerSample = 2.0

    @discardableResult
    static func preserve(
        audioURL: URL,
        reason: String,
        mode: DictationMode,
        modelLabel: String,
        targetApp: NSRunningApplication?
    ) -> URL? {
        do {
            let directory = try failedRecordingsDirectory()
            let timestamp = filenameTimestamp()
            let fileName = "\(timestamp)_\(safe(modelLabel))_\(safe(reason)).wav"
            let destination = uniqueURL(in: directory, preferredName: fileName)

            try FileManager.default.copyItem(at: audioURL, to: destination)
            try? FileManager.default.removeItem(at: audioURL)
            try writeMetadata(
                for: destination,
                reason: reason,
                mode: mode,
                modelLabel: modelLabel,
                targetApp: targetApp
            )
            cleanup(in: directory)

            DebugLog.shared.addLink(
                "Saved failed recording: \(destination.path)",
                url: directory,
                label: "Open folder"
            )
            return destination
        } catch {
            DebugLog.shared.add("Failed to save failed recording: \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: audioURL)
            return nil
        }
    }

    private static func failedRecordingsDirectory() throws -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)

        let directory = appSupport
            .appendingPathComponent("Murmur", isDirectory: true)
            .appendingPathComponent("Failed Recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func writeMetadata(
        for audioURL: URL,
        reason: String,
        mode: DictationMode,
        modelLabel: String,
        targetApp: NSRunningApplication?
    ) throws {
        let attrs = try? FileManager.default.attributesOfItem(atPath: audioURL.path)
        let fileSize = attrs?[.size] as? Int ?? 0
        let duration = Double(max(fileSize - 44, 0)) / (sampleRate * bytesPerSample)
        let metadata: [String: Any] = [
            "reason": reason,
            "model": modelLabel,
            "mode": mode == .raw ? "raw" : "rewrite",
            "targetApp": targetApp?.localizedName ?? targetApp?.bundleIdentifier ?? "",
            "audioDurationSeconds": duration,
            "fileSizeBytes": fileSize,
            "createdAt": isoTimestamp()
        ]
        let data = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
        let metadataURL = audioURL.deletingPathExtension().appendingPathExtension("json")
        try data.write(to: metadataURL, options: .atomic)
    }

    private static func cleanup(in directory: URL) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let wavFiles = files.filter { $0.pathExtension.lowercased() == "wav" }
        let cutoff = Date().addingTimeInterval(-maxAge)
        for file in wavFiles {
            if creationDate(for: file) < cutoff {
                removePair(for: file)
            }
        }

        let remaining = wavFiles
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .sorted { creationDate(for: $0) > creationDate(for: $1) }
        for file in remaining.dropFirst(maxRecordings) {
            removePair(for: file)
        }
    }

    private static func removePair(for audioURL: URL) {
        try? FileManager.default.removeItem(at: audioURL)
        try? FileManager.default.removeItem(
            at: audioURL.deletingPathExtension().appendingPathExtension("json")
        )
    }

    private static func creationDate(for url: URL) -> Date {
        let values = try? url.resourceValues(forKeys: [.creationDateKey])
        return values?.creationDate ?? .distantPast
    }

    private static func uniqueURL(in directory: URL, preferredName: String) -> URL {
        var candidate = directory.appendingPathComponent(preferredName)
        guard FileManager.default.fileExists(atPath: candidate.path) else { return candidate }

        let base = candidate.deletingPathExtension().lastPathComponent
        for index in 2...99 {
            candidate = directory.appendingPathComponent("\(base)-\(index).wav")
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return directory.appendingPathComponent("\(base)-\(UUID().uuidString).wav")
    }

    private static func safe(_ value: String) -> String {
        let lowercased = value.lowercased()
        let replaced = lowercased.replacingOccurrences(
            of: "[^a-z0-9]+",
            with: "-",
            options: .regularExpression
        )
        return replaced.trimmingCharacters(in: CharacterSet(charactersIn: "-")).isEmpty
            ? "unknown"
            : replaced.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static func filenameTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.string(from: Date())
    }

    private static func isoTimestamp() -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: Date())
    }
}
