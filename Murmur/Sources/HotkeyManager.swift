//
//  HotkeyManager.swift
//  Listens for F5 (raw transcribe) and F6 (LLM) hold-to-record hotkeys.
//  Uses CGEventTap at HID level to override system defaults (e.g. F5 dictation).
//

import Cocoa
import CoreGraphics

enum DictationMode {
    case raw    // ASR only -> clipboard -> paste
    case llm    // ASR -> OpenAI -> clipboard -> paste
}

final class HotkeyManager {

    // MARK: - Virtual key codes (from HIToolbox/Events.h)
    private static let kVK_F5: Int64 = 96
    private static let kVK_F6: Int64 = 97

    // MARK: - Callbacks
    var onPress: ((DictationMode) -> Void)?
    var onRelease: ((DictationMode) -> Void)?

    // MARK: - State
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var f5IsDown = false
    private var f6IsDown = false

    // MARK: - Public API
    func start() -> Bool {
        guard ensurePermission() else {
            print("⚠️ Input Monitoring permission required.")
            return false
        }

        // F-keys are NOT modifiers, so we listen to keyDown / keyUp
        // (NOT flagsChanged — that's only for modifier keys like Fn).
        let mask = (1 << CGEventType.keyDown.rawValue)
                 | (1 << CGEventType.keyUp.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,   // before any other listener
            options: .defaultTap,          // active mode -> can consume events
            eventsOfInterest: CGEventMask(mask),
            callback: HotkeyManager.callback,
            userInfo: refcon
        ) else {
            return false
        }

        self.eventTap = tap
        self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("✅ Hotkey monitor started (F5 = raw, F6 = LLM).")
        return true
    }

    func stop() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), src, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    // MARK: - Permission
    private func ensurePermission() -> Bool {
        if CGPreflightListenEventAccess() { return true }
        _ = CGRequestListenEventAccess()
        return CGPreflightListenEventAccess()
    }

    // MARK: - C callback
    private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo = userInfo else {
            return Unmanaged.passUnretained(event)
        }
        let mgr = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()

        // Re-enable tap if the system disabled it.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = mgr.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown || type == .keyUp else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == kVK_F5 || keyCode == kVK_F6 else {
            return Unmanaged.passUnretained(event)
        }

        let mode: DictationMode = (keyCode == kVK_F5) ? .raw : .llm
        let isDown = (type == .keyDown)
        // keyDown auto-repeats while held; ignore repeats.
        let autorepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

        if keyCode == kVK_F5 {
            mgr.handleEdge(isDown: isDown, autorepeat: autorepeat,
                           current: &mgr.f5IsDown, mode: mode)
        } else {
            mgr.handleEdge(isDown: isDown, autorepeat: autorepeat,
                           current: &mgr.f6IsDown, mode: mode)
        }

        // Consume the event — system never sees F5/F6, so Apple Dictation
        // (and any other app shortcut bound to those keys) won't trigger.
        return nil
    }

    private func handleEdge(isDown: Bool, autorepeat: Bool,
                            current: inout Bool, mode: DictationMode) {
        if isDown && !autorepeat && !current {
            current = true
            DispatchQueue.main.async { self.onPress?(mode) }
        } else if !isDown && current {
            current = false
            DispatchQueue.main.async { self.onRelease?(mode) }
        }
    }
}
