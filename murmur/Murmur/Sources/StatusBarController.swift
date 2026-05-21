//
//  StatusBarController.swift
//  Menu bar icon with four animated states:
//    idle       — outlined waveform (neutral)
//    recording  — filled waveform, pulsing red dot
//    processing — spinning gear
//    error      — exclamation mark, red
//
//  Click the icon to open the menu (settings, quit, etc).
//

import Cocoa
import SwiftUI

@MainActor
final class StatusBarController {

    static let shared = StatusBarController()

    private var statusItem: NSStatusItem!
    private var pulseTimer: Timer?
    private var pulseUp = true

    enum State {
        case idle
        case recording(DictationMode)
        case processing
        case error(String)
    }

    private(set) var state: State = .idle {
        didSet { updateAppearance() }
    }

    private init() {}

    func install() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageOnly

        let menu = NSMenu()
        menu.addItem(.init(title: "Murmur", action: nil, keyEquivalent: ""))
        menu.items.first?.isEnabled = false
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…",
                     action: #selector(openSettings),
                     keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Edit Vocabulary…",
                     action: #selector(openVocabulary),
                     keyEquivalent: "").target = self
        menu.addItem(withTitle: "Show Debug Panel",
                     action: #selector(openDebug),
                     keyEquivalent: "").target = self
        menu.addItem(withTitle: "Show/Hide Floating Controls",
                     action: #selector(toggleFloatingControls),
                     keyEquivalent: "").target = self
        menu.addItem(.separator())
        let aboutItem = NSMenuItem(title: "Hold Fn — transcribe",
                                   action: nil, keyEquivalent: "")
        aboutItem.isEnabled = false
        menu.addItem(aboutItem)
        let llmItem = NSMenuItem(title: "Hold Fn + Control — rewrite",
                                 action: nil, keyEquivalent: "")
        llmItem.isEnabled = false
        menu.addItem(llmItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Murmur",
                     action: #selector(NSApp.terminate(_:)),
                     keyEquivalent: "q")
        statusItem.menu = menu

        updateAppearance()
    }

    // MARK: - State setters
    func setRecording(_ on: Bool, mode: DictationMode) {
        state = on ? .recording(mode) : .idle
    }

    func setProcessing(_ on: Bool) {
        state = on ? .processing : .idle
    }

    func setIdle() { state = .idle }

    func setError(_ message: String) {
        state = .error(message)
        // Auto-clear error after 3 seconds.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            if case .error = self?.state { self?.state = .idle }
        }
    }

    // MARK: - Rendering
    private func updateAppearance() {
        guard let button = statusItem.button else { return }

        pulseTimer?.invalidate()
        pulseTimer = nil
        button.alphaValue = 1.0

        switch state {
        case .idle:
            button.image = templateSymbol("waveform.circle")
            button.toolTip = "Murmur — idle (hold Fn or Fn + Control)"

        case .recording(let mode):
            let color: NSColor = (mode == .raw) ? .systemRed : .systemPurple
            button.image = symbol("waveform.circle.fill", color: color)
            button.toolTip = mode == .raw ? "Recording (raw)" : "Recording (LLM)"
            startPulsing()

        case .processing:
            button.image = symbol("ellipsis.circle", color: .systemBlue)
            button.toolTip = "Processing…"
            startSpinning()

        case .error(let message):
            button.image = symbol("exclamationmark.triangle.fill", color: .systemOrange)
            button.toolTip = "Error: \(message)"
        }
    }

    private func symbol(_ name: String, color: NSColor) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        guard let img = NSImage(systemSymbolName: name, accessibilityDescription: name)?
            .withSymbolConfiguration(config) else { return nil }

        // Apply tint by drawing into a new bitmap. Menu bar items respect
        // template images by default, but we want explicit color for state.
        let tinted = NSImage(size: img.size)
        tinted.lockFocus()
        color.set()
        let rect = NSRect(origin: .zero, size: img.size)
        img.draw(in: rect)
        rect.fill(using: .sourceIn)
        tinted.unlockFocus()
        tinted.isTemplate = false
        return tinted
    }

    private func templateSymbol(_ name: String) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: name)?
            .withSymbolConfiguration(config)
        image?.isTemplate = true
        return image
    }

    private func startPulsing() {
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.statusItem.button?.alphaValue = self.pulseUp ? 1.0 : 0.4
                self.pulseUp.toggle()
            }
        }
    }

    private func startSpinning() {
        // Cycle through ellipsis frames for a "thinking" effect.
        let frames = ["ellipsis.circle", "ellipsis.circle.fill"]
        var idx = 0
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.statusItem.button?.image = self.symbol(frames[idx % frames.count],
                                                           color: .systemBlue)
                idx += 1
            }
        }
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func openVocabulary() {
        Vocabulary.shared.openUserFileInEditor()
    }

    @objc private func openDebug() {
        DebugWindowController.shared.show()
    }

    @objc private func toggleFloatingControls() {
        NotificationCenter.default.post(name: .murmurToggleFloatingControls, object: nil)
    }
}
