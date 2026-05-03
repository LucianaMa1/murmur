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
    static func copy(_ text: String, autoPaste: Bool) {
        let pasteboard = NSPasteboard.general

        // Snapshot existing clipboard so we can restore.
        let previous = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        guard autoPaste else { return }

        // Small delay to ensure pasteboard is updated before Cmd+V fires.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
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
}
