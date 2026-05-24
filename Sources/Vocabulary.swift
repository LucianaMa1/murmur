//
//  Vocabulary.swift
//  User vocabulary lives in ~/.murmur/vocabulary.txt.
//  It is plain text: one term per line, with optional `=>` corrections.
//      kubectl
//      k8s
//      gpt-4o-mini
//      cubicle => kubectl
//      cassandra => Casandra
//

import AppKit
import Foundation

struct VocabularyEntry: Identifiable, Hashable {
    let term: String              // canonical form
    let mishearing: String?       // optional: what Whisper might mishear it as

    var id: String {
        "\(mishearing ?? "")=>\(term)"
    }

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

    private init() {
        // ~/.murmur/
        dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".murmur", isDirectory: true)
        userFile = dir.appendingPathComponent("vocabulary.txt")
        ensureScaffold()
    }

    // MARK: - Public surface

    /// All user-defined entries, de-duplicated by canonical term.
    /// Used by OpenAIClient when building the polish-mode prompt.
    func allEntries() -> [VocabularyEntry] {
        var seen = Set<String>()
        var result: [VocabularyEntry] = []

        for entry in load(userFile) {
            let key = entry.term.lowercased()
            if seen.insert(key).inserted {
                result.append(entry)
            }
        }
        return result
    }

    func userEntries() -> [VocabularyEntry] {
        load(userFile)
    }

    func add(term: String, mishearing: String?) {
        let normalizedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedMishearing = mishearing?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTerm.isEmpty else { return }

        let entry = VocabularyEntry(
            term: normalizedTerm,
            mishearing: normalizedMishearing?.isEmpty == false ? normalizedMishearing : nil
        )
        var entries = userEntries()
        entries.removeAll { $0.id.lowercased() == entry.id.lowercased() }
        entries.append(entry)
        save(entries)
    }

    func delete(_ entry: VocabularyEntry) {
        save(userEntries().filter { $0.id != entry.id })
    }

    /// Open the user's vocabulary file in their default editor.
    func openUserFileInEditor() {
        NSWorkspace.shared.open(userFile)
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
    }

    private func load(_ url: URL) -> [VocabularyEntry] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { VocabularyEntry.parse(String($0)) }
    }

    private func save(_ entries: [VocabularyEntry]) {
        let header = """
        # Murmur vocabulary
        # One term per line. Lines starting with # are ignored.
        # Use "misheard phrase => correct spelling" for correction pairs.

        """
        let body = entries.map { entry in
            if let mishearing = entry.mishearing, !mishearing.isEmpty {
                return "\(mishearing) => \(entry.term)"
            }
            return entry.term
        }
        .joined(separator: "\n")

        let text = header + body + (body.isEmpty ? "" : "\n")
        try? text.write(to: userFile, atomically: true, encoding: .utf8)
    }
}
