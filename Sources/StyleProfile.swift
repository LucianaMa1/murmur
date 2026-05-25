//
//  StyleProfile.swift
//  App-aware writing style preferences for AI rewrite mode.
//

import AppKit
import Foundation

enum StyleProfileCategory: String, CaseIterable, Identifiable {
    case email
    case work
    case casual
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .email: return "Email"
        case .work: return "Work"
        case .casual: return "Casual"
        case .other: return "Other"
        }
    }

    var defaultTone: StyleTone {
        switch self {
        case .email, .work: return .formal
        case .casual: return .casual
        case .other: return .warm
        }
    }

    var defaultLength: StyleLength { .natural }
}

enum StyleTone: String, CaseIterable, Identifiable {
    case formal
    case warm
    case casual
    case excited

    var id: String { rawValue }

    var label: String {
        switch self {
        case .formal: return "Formal"
        case .warm: return "Warm"
        case .casual: return "Casual"
        case .excited: return "Excited"
        }
    }

    var promptInstruction: String {
        switch self {
        case .formal:
            return "Rewrite into a polished, professional tone. Use complete sentences, clear structure, and no slang."
        case .warm:
            return "Rewrite into a warm, natural tone. Sound human and considerate without becoming wordy."
        case .casual:
            return "Rewrite into a relaxed, conversational tone. Use contractions, simple phrasing, and light punctuation."
        case .excited:
            return "Rewrite into an upbeat tone with a little more energy. A tasteful exclamation mark is okay."
        }
    }
}

enum StyleLength: String, CaseIterable, Identifiable {
    case direct
    case natural
    case thorough

    var id: String { rawValue }

    var label: String {
        switch self {
        case .direct: return "Direct"
        case .natural: return "Natural"
        case .thorough: return "Thorough"
        }
    }

    var promptInstruction: String {
        switch self {
        case .direct:
            return "Make it short and direct. Prefer one or two concise sentences unless the user asks for more."
        case .natural:
            return "Use a standard length for the situation. Include enough context to feel complete."
        case .thorough:
            return "Make it more complete. Add useful context and structure when it helps the reader understand or act."
        }
    }
}

struct StyleProfile {
    let category: StyleProfileCategory
    let tone: StyleTone
    let length: StyleLength
    let habit: String

    var promptInstructions: String {
        var lines = [
            "Writing style profile: \(category.label)",
            "Apply this profile visibly in the final rewritten output whenever AI rewrite mode is used.",
            "Tone: \(tone.promptInstruction)",
            "Length: \(length.promptInstruction)"
        ]

        let trimmedHabit = habit.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedHabit.isEmpty {
            lines.append("Personal habit: \(trimmedHabit)")
        }

        return lines.joined(separator: "\n")
    }
}

enum StyleProfileStore {
    static let overrideKey = "style_profile_override"

    static func profile(for category: StyleProfileCategory) -> StyleProfile {
        let defaults = UserDefaults.standard
        let toneRaw = defaults.string(forKey: key("tone", category: category))
        let lengthRaw = defaults.string(forKey: key("length", category: category))
        let habit = defaults.string(forKey: key("habit", category: category)) ?? ""

        return StyleProfile(
            category: category,
            tone: toneRaw.flatMap(StyleTone.init(rawValue:)) ?? category.defaultTone,
            length: lengthRaw.flatMap(StyleLength.init(rawValue:)) ?? category.defaultLength,
            habit: habit
        )
    }

    static func activeCategory(for app: NSRunningApplication?) -> (category: StyleProfileCategory, reason: String, appDescription: String) {
        if let override = overrideCategory {
            return (
                override,
                "manual override",
                appDescription(for: app)
            )
        }

        return (
            category(for: app),
            "auto app match",
            appDescription(for: app)
        )
    }

    static func save(profile: StyleProfile) {
        let defaults = UserDefaults.standard
        defaults.set(profile.tone.rawValue, forKey: key("tone", category: profile.category))
        defaults.set(profile.length.rawValue, forKey: key("length", category: profile.category))
        defaults.set(profile.habit, forKey: key("habit", category: profile.category))
    }

    static func category(for app: NSRunningApplication?) -> StyleProfileCategory {
        let source = [
            app?.bundleIdentifier,
            app?.localizedName
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")

        guard !source.isEmpty else { return .other }

        if containsAny(source, ["mail", "outlook", "spark", "gmail", "superhuman"]) {
            return .email
        }
        if containsAny(source, ["slack", "teams", "linear", "notion", "cursor", "code", "windsurf", "replit", "github"]) {
            return .work
        }
        if containsAny(source, ["messages", "whatsapp", "telegram", "discord", "wechat", "signal"]) {
            return .casual
        }
        return .other
    }

    static var overrideCategory: StyleProfileCategory? {
        let raw = UserDefaults.standard.string(forKey: overrideKey) ?? "auto"
        guard raw != "auto" else { return nil }
        return StyleProfileCategory(rawValue: raw)
    }

    static func appDescription(for app: NSRunningApplication?) -> String {
        let name = app?.localizedName ?? "<unknown>"
        let bundleID = app?.bundleIdentifier ?? "<unknown>"
        return "\(name) (\(bundleID))"
    }

    private static func key(_ field: String, category: StyleProfileCategory) -> String {
        "style_profile_\(category.rawValue)_\(field)"
    }

    private static func containsAny(_ source: String, _ needles: [String]) -> Bool {
        needles.contains { source.contains($0) }
    }
}
