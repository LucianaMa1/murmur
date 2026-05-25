//
//  SettingsWindowController.swift
//  Settings: API key (Keychain), model, auto-paste, polish prompt, vocabulary.
//

import SwiftUI
import AppKit
import Security

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = SettingsView()
        let host = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: host)
        win.title = "Murmur Settings"
        win.styleMask = [.titled, .closable]
        win.setContentSize(NSSize(width: 560, height: 780))
        win.isReleasedWhenClosed = false
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = win
    }
}

struct SettingsView: View {
    @AppStorage("openai_model") private var model: String = "gpt-4o-mini"
    @AppStorage(WhisperModelOption.storageKey) private var whisperModel: String = WhisperModelOption.fast.rawValue
    @AppStorage("auto_paste") private var autoPaste: Bool = true
    @AppStorage("llm_system_prompt") private var prompt: String = OpenAIClient.defaultSystemPrompt
    @AppStorage(FloatingControlsPreferences.enabledKey) private var floatingControlsEnabled: Bool = true
    @AppStorage(FloatingControlsPreferences.accentKey) private var floatingControlsAccent: String = "mint"
    @AppStorage(FloatingControlsPreferences.styleKey) private var floatingControlsStyle: String = "glass"
    @AppStorage(StyleProfileStore.overrideKey) private var styleProfileOverride: String = "auto"
    @State private var apiKey: String = Keychain.read() ?? ""
    @State private var saved: Bool = false
    @State private var selectedStyleCategory: StyleProfileCategory = .email
    @State private var selectedTone: StyleTone = .formal
    @State private var selectedLength: StyleLength = .natural
    @State private var styleHabit: String = ""
    @State private var dictionaryEntries: [VocabularyEntry] = []
    @State private var dictionarySearch: String = ""
    @State private var dictionaryTerm: String = ""
    @State private var dictionaryMishearing: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Murmur").font(.title2).bold()

                GroupBox("OpenAI") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("API Key").frame(width: 80, alignment: .leading)
                            SecureField("sk-…", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                        }
                        HStack {
                            Text("Model").frame(width: 80, alignment: .leading)
                            Picker("", selection: $model) {
                                Text("gpt-4o-mini (fast, cheap)").tag("gpt-4o-mini")
                                Text("gpt-4o").tag("gpt-4o")
                                Text("gpt-4-turbo").tag("gpt-4-turbo")
                            }.labelsHidden()
                        }
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("Behavior") {
                    Toggle("Auto-paste after transcription", isOn: $autoPaste)
                        .padding(.vertical, 4)
                }

                GroupBox("Speed vs Quality") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Optimize local transcription for speed, or trade a little latency for better recognition in noisier environments.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack {
                            Text("Optimize").frame(width: 80, alignment: .leading)
                            Picker("Optimize", selection: $whisperModel) {
                                ForEach(WhisperModelOption.allCases) { option in
                                    Text(option.label).tag(option.rawValue)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                        }

                        Text(selectedWhisperModel.detail)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("When you change this, Murmur prepares the selected model in the background so your next dictation does not wait for the download.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("If the selected model is not ready during dictation, Murmur uses the best available fallback and logs the reason in Debug.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack {
                            Text("Faster")
                            Spacer()
                            Text("More accurate")
                        }
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("Style Profiles") {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Use profile")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Picker("Use profile", selection: $styleProfileOverride) {
                                Text("Auto").tag("auto")
                                ForEach(StyleProfileCategory.allCases) { category in
                                    Text(category.label).tag(category.rawValue)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                        }

                        Divider()

                        Text("Edit profile")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Picker("Applies to", selection: $selectedStyleCategory) {
                            ForEach(StyleProfileCategory.allCases) { category in
                                Text(category.label).tag(category)
                            }
                        }
                        .pickerStyle(.segmented)

                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Tone")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Picker("Tone", selection: $selectedTone) {
                                    ForEach(StyleTone.allCases) { tone in
                                        Text(tone.label).tag(tone)
                                    }
                                }
                                .labelsHidden()
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Length")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Picker("Length", selection: $selectedLength) {
                                    ForEach(StyleLength.allCases) { length in
                                        Text(length.label).tag(length)
                                    }
                                }
                                .labelsHidden()
                            }
                        }

                        TextField("Small habit, e.g. no exclamation marks or always sign off with Luciana", text: $styleHabit)
                            .textFieldStyle(.roundedBorder)

                        Text("Style only affects Fn + Control AI rewrite. Auto picks from the current app; choose a specific profile above to force it everywhere.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("Floating Controls") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Show floating mouse controls", isOn: $floatingControlsEnabled)

                        HStack {
                            Text("Accent").frame(width: 80, alignment: .leading)
                            Picker("", selection: $floatingControlsAccent) {
                                Text("Mint").tag("mint")
                                Text("Blue").tag("blue")
                                Text("Pink").tag("pink")
                                Text("Amber").tag("amber")
                                Text("Violet").tag("violet")
                                Text("Graphite").tag("graphite")
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                        }

                        HStack {
                            Text("Style").frame(width: 80, alignment: .leading)
                            Picker("", selection: $floatingControlsStyle) {
                                Text("Glass").tag("glass")
                                Text("Dark").tag("dark")
                                Text("Light").tag("light")
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                        }

                        Text("Use the small x on the floating panel to hide it. Bring it back here or from the menu bar.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("Hotkeys") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Transcribe").frame(width: 120, alignment: .leading)
                            Text("Hold Fn")
                                .font(.body.weight(.semibold))
                        }

                        HStack {
                            Text("Rewrite").frame(width: 120, alignment: .leading)
                            Text("Hold Fn + Control")
                                .font(.body.weight(.semibold))
                        }

                        Text("Murmur uses fixed push-to-talk keys so the two modes stay predictable across apps. If Fn is intercepted by macOS, keep the floating Transcribe and Rewrite buttons enabled.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("Dictionary") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Add names, tools, commands, and mishearing fixes for AI rewrite mode.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 8) {
                            TextField("Correct spelling, e.g. kubectl", text: $dictionaryTerm)
                                .textFieldStyle(.roundedBorder)
                            TextField("Misheard as, optional", text: $dictionaryMishearing)
                                .textFieldStyle(.roundedBorder)
                            Button("Add") {
                                addDictionaryEntry()
                            }
                            .disabled(dictionaryTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }

                        TextField("Search dictionary", text: $dictionarySearch)
                            .textFieldStyle(.roundedBorder)

                        if filteredDictionaryEntries.isEmpty {
                            Text("No matching terms yet.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            VStack(spacing: 6) {
                                ForEach(Array(filteredDictionaryEntries.prefix(8))) { entry in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(entry.term)
                                                .font(.body.weight(.medium))
                                            if let mishearing = entry.mishearing {
                                                Text("Misheard as: \(mishearing)")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        Spacer()
                                        Button("Remove") {
                                            Vocabulary.shared.delete(entry)
                                            loadDictionary()
                                        }
                                        .font(.caption)
                                    }
                                    .padding(8)
                                    .background(Color(NSColor.controlBackgroundColor))
                                    .cornerRadius(8)
                                }
                            }
                        }

                        HStack {
                            Button("Open File") {
                                Vocabulary.shared.openUserFileInEditor()
                            }
                            Button("Refresh") {
                                loadDictionary()
                            }
                            Spacer()
                        }
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("LLM Prompt") {
                    TextEditor(text: $prompt)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(height: 110)
                        .border(Color.gray.opacity(0.3))
                }

                HStack {
                    Button("Reset Prompt") {
                        prompt = OpenAIClient.defaultSystemPrompt
                    }
                    Spacer()
                    if saved {
                        Text("✓ Saved").foregroundColor(.green).font(.caption)
                    }
                    Button("Save") {
                        Keychain.write(apiKey)
                        saved = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            saved = false
                        }
                    }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
        }
        .frame(width: 560, height: 780)
        .onAppear {
            loadStyleProfile()
            loadDictionary()
        }
        .onChange(of: selectedStyleCategory) { _, _ in
            loadStyleProfile()
        }
        .onChange(of: selectedTone) { _, _ in
            saveStyleProfile()
        }
        .onChange(of: selectedLength) { _, _ in
            saveStyleProfile()
        }
        .onChange(of: styleHabit) { _, _ in
            saveStyleProfile()
        }
        .onChange(of: floatingControlsEnabled) { _, _ in
            NotificationCenter.default.post(name: .murmurFloatingControlsPreferenceChanged, object: nil)
        }
        .onChange(of: whisperModel) { _, _ in
            NotificationCenter.default.post(name: .murmurTranscriptionModelPreferenceChanged, object: nil)
        }
        .onChange(of: floatingControlsAccent) { _, _ in
            NotificationCenter.default.post(name: .murmurFloatingControlsPreferenceChanged, object: nil)
        }
        .onChange(of: floatingControlsStyle) { _, _ in
            NotificationCenter.default.post(name: .murmurFloatingControlsPreferenceChanged, object: nil)
        }
    }

    private var filteredDictionaryEntries: [VocabularyEntry] {
        let query = dictionarySearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return dictionaryEntries }
        return dictionaryEntries.filter { entry in
            entry.term.lowercased().contains(query)
            || entry.mishearing?.lowercased().contains(query) == true
        }
    }

    private var selectedWhisperModel: WhisperModelOption {
        WhisperModelOption(rawValue: whisperModel) ?? .fast
    }

    private func loadStyleProfile() {
        let profile = StyleProfileStore.profile(for: selectedStyleCategory)
        selectedTone = profile.tone
        selectedLength = profile.length
        styleHabit = profile.habit
    }

    private func saveStyleProfile() {
        StyleProfileStore.save(profile: StyleProfile(
            category: selectedStyleCategory,
            tone: selectedTone,
            length: selectedLength,
            habit: styleHabit
        ))
    }

    private func loadDictionary() {
        dictionaryEntries = Vocabulary.shared.userEntries()
    }

    private func addDictionaryEntry() {
        Vocabulary.shared.add(term: dictionaryTerm, mishearing: dictionaryMishearing)
        dictionaryTerm = ""
        dictionaryMishearing = ""
        loadDictionary()
    }
}

// MARK: - Keychain wrapper
enum Keychain {
    private static let service = "com.lucianama.murmur.openai"
    private static let account = "api_key"

    static func read() -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let s = String(data: data, encoding: .utf8) else { return nil }
        return s
    }

    static func write(_ value: String) {
        let data = value.data(using: .utf8) ?? Data()
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(q as CFDictionary)
        let attrs = q.merging([kSecValueData as String: data]) { _, new in new }
        SecItemAdd(attrs as CFDictionary, nil)
    }
}
