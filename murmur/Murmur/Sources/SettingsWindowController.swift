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
        win.setContentSize(NSSize(width: 520, height: 600))
        win.isReleasedWhenClosed = false
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = win
    }
}

struct SettingsView: View {
    @AppStorage("openai_model") private var model: String = "gpt-4o-mini"
    @AppStorage("auto_paste") private var autoPaste: Bool = true
    @AppStorage("vocab_learn_enabled") private var learnEnabled: Bool = false
    @AppStorage("llm_system_prompt") private var prompt: String = OpenAIClient.defaultSystemPrompt
    @AppStorage(FloatingControlsPreferences.enabledKey) private var floatingControlsEnabled: Bool = true
    @AppStorage(FloatingControlsPreferences.accentKey) private var floatingControlsAccent: String = "mint"
    @AppStorage(FloatingControlsPreferences.styleKey) private var floatingControlsStyle: String = "glass"
    @State private var apiKey: String = Keychain.read() ?? ""
    @State private var saved: Bool = false

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

                GroupBox("Vocabulary") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Murmur uses your vocabulary list to fix mishearings of jargon and proper nouns when using polished transcription.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack {
                            Button("Edit Vocabulary…") {
                                Vocabulary.shared.openUserFileInEditor()
                            }
                            Button("Open Learned File") {
                                Vocabulary.shared.openLearnedFileInEditor()
                            }
                            Spacer()
                        }

                        Toggle("Learn from corrections", isOn: $learnEnabled)

                        Text("When enabled, Murmur will record any non-trivial corrections the LLM makes (e.g. \"cubicle\" → \"kubectl\") into ~/.murmur/learned.txt. You can review or wipe this file at any time.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if learnEnabled {
                            Button("Forget what Murmur has learned") {
                                Vocabulary.shared.resetLearned()
                            }
                            .font(.caption)
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
        .frame(width: 520, height: 600)
        .onChange(of: floatingControlsEnabled) { _, _ in
            NotificationCenter.default.post(name: .murmurFloatingControlsPreferenceChanged, object: nil)
        }
        .onChange(of: floatingControlsAccent) { _, _ in
            NotificationCenter.default.post(name: .murmurFloatingControlsPreferenceChanged, object: nil)
        }
        .onChange(of: floatingControlsStyle) { _, _ in
            NotificationCenter.default.post(name: .murmurFloatingControlsPreferenceChanged, object: nil)
        }
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
