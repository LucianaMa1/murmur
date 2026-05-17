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
    @AppStorage(HotkeyManager.rawHotkeyDefaultsKey) private var rawHotkeyCode: Int = 96
    @AppStorage(HotkeyManager.llmHotkeyDefaultsKey) private var llmHotkeyCode: Int = 97
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
                        HotkeySettingRow(title: "Raw transcription", keyCode: $rawHotkeyCode)
                        HotkeySettingRow(title: "Polished transcription", keyCode: $llmHotkeyCode)

                        if rawHotkeyCode == llmHotkeyCode {
                            Text("Choose two different keys so Murmur knows which mode to use.")
                                .font(.caption)
                                .foregroundColor(.red)
                        }

                        Text("Click a field, then press any push-to-talk key: Fn, Control, Option, Shift, Command, F-keys, letters, Space, or arrows.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Button("Reset Hotkeys") {
                            rawHotkeyCode = 96
                            llmHotkeyCode = 97
                        }
                        .font(.caption)
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
        .onChange(of: floatingControlsEnabled) { _ in
            NotificationCenter.default.post(name: .murmurFloatingControlsPreferenceChanged, object: nil)
        }
        .onChange(of: floatingControlsAccent) { _ in
            NotificationCenter.default.post(name: .murmurFloatingControlsPreferenceChanged, object: nil)
        }
        .onChange(of: floatingControlsStyle) { _ in
            NotificationCenter.default.post(name: .murmurFloatingControlsPreferenceChanged, object: nil)
        }
    }
}

private struct HotkeySettingRow: View {
    let title: String
    @Binding var keyCode: Int

    var body: some View {
        HStack {
            Text(title).frame(width: 150, alignment: .leading)
            HotkeyRecorder(keyCode: $keyCode)
                .frame(width: 170, height: 28)
            Text("Hold to record")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
    }
}

private struct HotkeyRecorder: NSViewRepresentable {
    @Binding var keyCode: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(keyCode: $keyCode)
    }

    func makeNSView(context: Context) -> HotkeyCaptureButton {
        let button = HotkeyCaptureButton()
        button.bezelStyle = .rounded
        button.setButtonType(.momentaryPushIn)
        button.target = context.coordinator
        button.action = #selector(Coordinator.startRecording(_:))
        button.coordinator = context.coordinator
        context.coordinator.button = button
        context.coordinator.update(keyCode: keyCode)
        return button
    }

    func updateNSView(_ nsView: HotkeyCaptureButton, context: Context) {
        context.coordinator.keyCode = $keyCode
        context.coordinator.button = nsView
        nsView.coordinator = context.coordinator
        context.coordinator.update(keyCode: keyCode)
    }

    final class Coordinator: NSObject {
        var keyCode: Binding<Int>
        weak var button: HotkeyCaptureButton?
        private var isRecording = false

        init(keyCode: Binding<Int>) {
            self.keyCode = keyCode
        }

        @objc func startRecording(_ sender: HotkeyCaptureButton) {
            isRecording = true
            sender.isRecording = true
            sender.title = "Press a key..."
            sender.window?.makeFirstResponder(sender)
        }

        func capture(event: NSEvent) {
            guard isRecording else { return }

            if event.keyCode != 53 {
                keyCode.wrappedValue = Int(event.keyCode)
            }

            isRecording = false
            button?.isRecording = false
            button?.title = HotkeyNames.displayName(for: keyCode.wrappedValue)
        }

        func update(keyCode: Int) {
            guard !isRecording else { return }
            button?.title = HotkeyNames.displayName(for: keyCode)
        }

        func captureModifier(event: NSEvent) {
            guard isRecording else { return }

            let captured = Int(event.keyCode)
            guard HotkeyNames.isSupportedModifier(captured) else { return }

            keyCode.wrappedValue = captured
            isRecording = false
            button?.isRecording = false
            button?.title = HotkeyNames.displayName(for: keyCode.wrappedValue)
        }
    }
}

private final class HotkeyCaptureButton: NSButton {
    weak var coordinator: HotkeyRecorder.Coordinator?
    var isRecording = false

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if isRecording {
            coordinator?.capture(event: event)
        } else {
            super.keyDown(with: event)
        }
    }

    override func flagsChanged(with event: NSEvent) {
        if isRecording {
            coordinator?.captureModifier(event: event)
        } else {
            super.flagsChanged(with: event)
        }
    }
}

private enum HotkeyNames {
    static func isSupportedModifier(_ keyCode: Int) -> Bool {
        supportedModifiers.contains(keyCode)
    }

    static func displayName(for keyCode: Int) -> String {
        names[keyCode] ?? "Key \(keyCode)"
    }

    private static let supportedModifiers: Set<Int> = [54, 55, 56, 58, 59, 60, 61, 62, 63]

    private static let names: [Int: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "Return",
        37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
        44: "/", 45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space",
        50: "`", 51: "Delete", 53: "Esc", 54: "Right Command", 55: "Command",
        56: "Shift", 58: "Option", 59: "Control", 60: "Right Shift",
        61: "Right Option", 62: "Right Control", 63: "Fn", 96: "F5", 97: "F6", 98: "F7",
        99: "F3", 100: "F8", 101: "F9", 103: "F11", 105: "F13",
        107: "F14", 109: "F10", 111: "F12", 113: "F15", 114: "Help",
        115: "Home", 116: "Page Up", 117: "Forward Delete", 118: "F4",
        119: "End", 120: "F2", 121: "Page Down", 122: "F1", 123: "Left",
        124: "Right", 125: "Down", 126: "Up"
    ]
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
