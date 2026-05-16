//
//  HotkeyManager.swift
//  Listens for configurable hold-to-record hotkeys.
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
    private static let defaultRawKeyCode: Int64 = 96
    private static let defaultLLMKeyCode: Int64 = 97
    private static let fnKeyCode: Int64 = 63
    private static let modifierKeyCodes: Set<Int64> = [54, 55, 56, 58, 59, 60, 61, 62, fnKeyCode]
    static let rawHotkeyDefaultsKey = "raw_hotkey_code"
    static let llmHotkeyDefaultsKey = "llm_hotkey_code"

    // MARK: - Callbacks
    var onPress: ((DictationMode) -> Void)?
    var onRelease: ((DictationMode) -> Void)?

    // MARK: - State
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var activeTapCanConsume = false
    private var rawIsDown = false
    private var llmIsDown = false

    // MARK: - Public API
    func start() -> Bool {
        DebugLog.shared.add("Hotkey permission status: listenAccess=\(CGPreflightListenEventAccess())")
        DebugLog.shared.add("Configured hotkeys: raw=\(configuredRawKeyCode()), rewrite=\(configuredLLMKeyCode())")

        guard ensurePermission() else {
            print("⚠️ Input Monitoring permission required.")
            DebugLog.shared.add("Input Monitoring permission not granted; hotkeys cannot start")
            return false
        }

        // Regular keys arrive as keyDown/keyUp. Modifier-only push-to-talk
        // keys like Fn, Control, Option, Shift, and Command arrive as flagsChanged.
        let mask = (1 << CGEventType.keyDown.rawValue)
                 | (1 << CGEventType.keyUp.rawValue)
                 | (1 << CGEventType.flagsChanged.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        let activeTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: HotkeyManager.callback,
            userInfo: refcon
        )

        let listenTap = activeTap ?? CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: HotkeyManager.callback,
            userInfo: refcon
        )

        guard let tap = listenTap else {
            DebugLog.shared.add("CGEvent tapCreate failed even after Input Monitoring grant")
            return false
        }

        self.eventTap = tap
        self.activeTapCanConsume = activeTap != nil
        self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("✅ Hotkey monitor started.")
        DebugLog.shared.add(activeTapCanConsume
            ? "Hotkey monitor started at HID level; configured hotkeys will be consumed before macOS shortcuts"
            : "Hotkey monitor started in listen-only fallback; macOS may still catch Fn/Globe first")
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

        if type == .flagsChanged {
            return mgr.handleModifierFlagsChanged(event)
        }

        guard type == .keyDown || type == .keyUp else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard let mode = mgr.mode(for: keyCode) else {
            return Unmanaged.passUnretained(event)
        }

        let isDown = (type == .keyDown)
        // keyDown auto-repeats while held; ignore repeats.
        let autorepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

        switch mode {
        case .raw:
            mgr.logHotkeyEdge(isDown: isDown, autorepeat: autorepeat, mode: mode, keyCode: keyCode)
            mgr.handleEdge(isDown: isDown, autorepeat: autorepeat,
                           current: &mgr.rawIsDown, mode: mode)
        case .llm:
            mgr.logHotkeyEdge(isDown: isDown, autorepeat: autorepeat, mode: mode, keyCode: keyCode)
            mgr.handleEdge(isDown: isDown, autorepeat: autorepeat,
                           current: &mgr.llmIsDown, mode: mode)
        }

        return mgr.activeTapCanConsume ? nil : Unmanaged.passUnretained(event)
    }

    private func mode(for keyCode: Int64) -> DictationMode? {
        if keyCode == Int64(configuredRawKeyCode()) { return .raw }
        if keyCode == Int64(configuredLLMKeyCode()) { return .llm }
        return nil
    }

    private func modeForModifierKeyCode(_ keyCode: Int64) -> DictationMode? {
        guard Self.modifierKeyCodes.contains(keyCode) else { return nil }
        if configuredRawKeyCode() == Int(keyCode) { return .raw }
        if configuredLLMKeyCode() == Int(keyCode) { return .llm }
        return nil
    }

    private func configuredRawKeyCode() -> Int {
        let defaults = UserDefaults.standard
        return defaults.object(forKey: Self.rawHotkeyDefaultsKey) as? Int
            ?? Int(Self.defaultRawKeyCode)
    }

    private func configuredLLMKeyCode() -> Int {
        let defaults = UserDefaults.standard
        return defaults.object(forKey: Self.llmHotkeyDefaultsKey) as? Int
            ?? Int(Self.defaultLLMKeyCode)
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

    private func handleModifierFlagsChanged(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard let mode = modeForModifierKeyCode(keyCode) else { return Unmanaged.passUnretained(event) }

        let isDown = isModifierPressed(keyCode: keyCode, flags: event.flags)
        switch mode {
        case .raw:
            logHotkeyEdge(isDown: isDown, autorepeat: false, mode: mode, keyCode: keyCode)
            handleEdge(isDown: isDown, autorepeat: false, current: &rawIsDown, mode: mode)
        case .llm:
            logHotkeyEdge(isDown: isDown, autorepeat: false, mode: mode, keyCode: keyCode)
            handleEdge(isDown: isDown, autorepeat: false, current: &llmIsDown, mode: mode)
        }

        return activeTapCanConsume ? nil : Unmanaged.passUnretained(event)
    }

    private func isModifierPressed(keyCode: Int64, flags: CGEventFlags) -> Bool {
        switch keyCode {
        case 54, 55:
            return flags.contains(.maskCommand)
        case 56, 60:
            return flags.contains(.maskShift)
        case 58, 61:
            return flags.contains(.maskAlternate)
        case 59, 62:
            return flags.contains(.maskControl)
        case Self.fnKeyCode:
            return flags.contains(.maskSecondaryFn)
        default:
            return false
        }
    }

    private func logHotkeyEdge(isDown: Bool, autorepeat: Bool, mode: DictationMode, keyCode: Int64) {
        guard !autorepeat || !isDown else { return }
        let edge = isDown ? "down" : "up"
        let label = mode == .raw ? "raw" : "rewrite"
        DebugLog.shared.add("Hotkey \(edge) matched mode=\(label), keyCode=\(keyCode)")
    }
}
