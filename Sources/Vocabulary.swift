//
//  Vocabulary.swift
//  Two-layer vocabulary system:
//
//   1. User vocabulary  (~/.murmur/vocabulary.txt)
//      Explicitly curated by the user. They own this file. One term per line.
//      Optional `=>` syntax to map a misheard form to the correct one:
//          kubectl
//          k8s
//          gpt-4o-mini
//          cubicle => kubectl
//          cassandra => Casandra (proper noun spelling)
//
//   2. Learned vocabulary  (~/.murmur/learned.txt)
//      Auto-populated when "Learn from corrections" is enabled.
//      Format: same as above. Murmur appends entries when the LLM makes a
//      non-trivial correction during rewrite polishing.
//      The user can open this file at any time to inspect, edit, or wipe it.
//
//  Both files are plain text. No database, no opaque format. The user can
//  `cat`, `grep`, version-control, or sync them however they like.
//

import AppKit
import Foundation

struct VocabularyEntry {
    let term: String              // canonical form
    let mishearing: String?       // optional: what Whisper might mishear it as

    /// Parses a single line. Returns nil for blanks/comments.
    /// Supported forms:
    ///   "kubectl"                 → term=kubectl, mishearing=nil
    ///   "cubicle => kubectl"      → term=kubectl, mishearing=cubicle
    ///   "# comment line"          → nil
    static func parse(_ line: String) -> VocabularyEntry? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }

        if let arrow = trimmed.range(of: "=>") {
            let lhs = trimmed[..<arrow.lowerBound].trimmingCharacters(in: .whitespaces)
            let rhs = trimmed[arrow.upperBound...].trimmingCharacters(in: .whitespaces)
            guard !lhs.isEmpty, !rhs.isEmpty else { return nil }
            return VocabularyEntry(term: rhs, mishearing: lhs)
        }
        return VocabularyEntry(term: trimmed, mishearing: nil)
    }
}

final class Vocabulary {

    static let shared = Vocabulary()

    // MARK: - File paths
    private let dir: URL
    private let userFile: URL
    private let learnedFile: URL

    private init() {
        // ~/.murmur/
        dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".murmur", isDirectory: true)
        userFile = dir.appendingPathComponent("vocabulary.txt")
        learnedFile = dir.appendingPathComponent("learned.txt")
        ensureScaffold()
    }

    // MARK: - Public surface

    /// All entries (user + learned), de-duplicated by canonical term.
    /// Used by OpenAIClient when building the polish-mode prompt.
    func allEntries() -> [VocabularyEntry] {
        var seen = Set<String>()
        var result: [VocabularyEntry] = []

        for entry in load(userFile) + (learnEnabled ? load(learnedFile) : []) {
            let key = entry.term.lowercased()
            if seen.insert(key).inserted {
                result.append(entry)
            }
        }
        return result
    }

    /// Append a learned entry. No-op if "learn from corrections" is disabled,
    /// or if this term is already known (in either file).
    func recordLearned(mishearing: String, correction: String) {
        guard learnEnabled else { return }
        guard !isKnown(term: correction) else { return }
        guard mishearing.lowercased() != correction.lowercased() else { return }
        // Skip trivial things (single-char, pure punctuation differences).
        guard correction.count >= 3 else { return }

        let line = "\(mishearing) => \(correction)\n"
        if let data = line.data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: learnedFile) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            }
        }
    }

    /// Open the user's vocabulary file in their default editor.
    func openUserFileInEditor() {
        NSWorkspace.shared.open(userFile)
    }

    func openLearnedFileInEditor() {
        NSWorkspace.shared.open(learnedFile)
    }

    /// Clear the learned file (user said "forget what you've learned").
    func resetLearned() {
        try? "".write(to: learnedFile, atomically: true, encoding: .utf8)
    }

    // MARK: - Settings

    /// Whether rewrite mode should record automatic corrections to learned.txt.
    /// Defaults to FALSE — auto-learning is opt-in. (Privacy default.)
    var learnEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "vocab_learn_enabled") }
        set { UserDefaults.standard.set(newValue, forKey: "vocab_learn_enabled") }
    }

    // MARK: - Internal

    private func ensureScaffold() {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: userFile.path) {
            let template = """
            # Murmur vocabulary
            # One term per line. Lines starting with # are ignored.
            #
            # Plain term — Murmur will preserve its spelling/casing:
            #   kubectl
            #   GraphQL
            #   k8s
            #
            # Mishearing fix — replace 'cubicle' with 'kubectl' when polishing:
            #   cubicle => kubectl
            #
            # Add your own jargon below.

            """
            try? template.write(to: userFile, atomically: true, encoding: .utf8)
        }
        if !FileManager.default.fileExists(atPath: learnedFile.path) {
            let template = """
            # Murmur learned vocabulary
            # Auto-populated when "Learn from corrections" is enabled.
            # Safe to edit or empty this file at any time.

            """
            try? template.write(to: learnedFile, atomically: true, encoding: .utf8)
        }
    }

    private func load(_ url: URL) -> [VocabularyEntry] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { VocabularyEntry.parse(String($0)) }
    }

    private func isKnown(term: String) -> Bool {
        let key = term.lowercased()
        return (load(userFile) + load(learnedFile))
            .contains { $0.term.lowercased() == key }
    }
}
