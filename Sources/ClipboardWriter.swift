//
//  ClipboardWriter.swift
//  Writes text to clipboard, optionally auto-pastes via Cmd+V.
//

import Cocoa
import CoreGraphics

enum ClipboardWriter {

    /// Copy text to the system clipboard.
    /// If `autoPaste` is true, simulates Cmd+V into the frontmost app.
    /// Restores the previous clipboard contents after pasting (so the user's
    /// existing clipboard isn't clobbered) — this is how Raycast / Superwhisper do it.
    static func copy(_ text: String, autoPaste: Bool, targetApp: NSRunningApplication?) {
        let pasteboard = NSPasteboard.general

        // Snapshot existing clipboard so we can restore.
        let previous = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        DebugLog.shared.add("Clipboard updated with \(text.count) character(s)")

        guard autoPaste else {
            DebugLog.shared.add("Auto-paste disabled; leaving text on clipboard")
            return
        }

        let accessibilityTrusted = Self.ensureAccessibilityPermission()
        if !accessibilityTrusted {
            DebugLog.shared.add("Accessibility permission is not trusted; leaving text on clipboard instead of auto-pasting")
            return
        }

        let pasteDelay: TimeInterval
        if let targetApp {
            DebugLog.shared.add("Activating target app before paste: \(targetApp.localizedName ?? targetApp.bundleIdentifier ?? "<unknown>")")
            targetApp.activate(options: [.activateIgnoringOtherApps])
            pasteDelay = 0.18
        } else {
            pasteDelay = 0.05
        }

        // Small delay to ensure pasteboard and focus are updated before Cmd+V fires.
        DispatchQueue.main.asyncAfter(deadline: .now() + pasteDelay) {
            DebugLog.shared.add("Posting Cmd+V")
            simulateCmdV()

            // Restore the previous clipboard after paste completes.
            if let previous = previous {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    pasteboard.clearContents()
                    pasteboard.setString(previous, forType: .string)
                }
            }
        }
    }

    /// Posts a synthetic Cmd+V keypress to the frontmost app.
    /// Requires Accessibility permission.
    private static func simulateCmdV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKeyCode: CGKeyCode = 0x09  // kVK_ANSI_V

        let down = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        up?.flags = .maskCommand

        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }

    @discardableResult
    static func ensureAccessibilityPermission(prompt: Bool = true) -> Bool {
        guard prompt else { return AXIsProcessTrusted() }
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
