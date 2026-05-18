//
//  HotkeyManager.swift
//  Listens for fixed hold-to-record hotkeys.
//  Uses CGEventTap at HID level to catch Fn before macOS shortcuts when possible.
//

import Cocoa
import CoreGraphics

enum DictationMode {
    case raw    // ASR only -> clipboard -> paste
    case llm    // ASR -> OpenAI -> clipboard -> paste
}

final class HotkeyManager {

    // MARK: - Virtual key codes (from HIToolbox/Events.h)
    private static let fnKeyCode: Int64 = 63
    private static let controlKeyCodes: Set<Int64> = [59, 62]
    private static let fixedModifierKeyCodes: Set<Int64> = controlKeyCodes.union([fnKeyCode])

    // MARK: - Callbacks
    var onPress: ((DictationMode) -> Void)?
    var onRelease: ((DictationMode) -> Void)?

    // MARK: - State
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var globalKeyMonitor: Any?
    private var globalFlagMonitor: Any?
    private var activeTapCanConsume = false
    private var rawIsDown = false
    private var llmIsDown = false
    private var suppressRawUntilFnRelease = false
    private var pendingRawStartToken: UUID?
    private var unmatchedEventLogCount = 0

    // MARK: - Public API
    func start() -> Bool {
        let accessibilityTrusted = AXIsProcessTrusted()
        let listenAccess = CGPreflightListenEventAccess()
        DebugLog.shared.add("Hotkey permission status: listenAccess=\(listenAccess)")
        DebugLog.shared.add("Accessibility permission status: trusted=\(accessibilityTrusted)")
        DebugLog.shared.add("Fixed hotkeys: Fn=raw, Fn+Control=rewrite")

        promptForPermissionsIfNeeded()
        startGlobalMonitors()

        guard CGPreflightListenEventAccess() else {
            print("⚠️ Input Monitoring permission required.")
            DebugLog.shared.add("Input Monitoring permission not granted; CGEventTap disabled, NSEvent fallback remains installed")
            return globalKeyMonitor != nil || globalFlagMonitor != nil
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
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
        }
        if let globalFlagMonitor {
            NSEvent.removeMonitor(globalFlagMonitor)
        }
        eventTap = nil
        runLoopSource = nil
        globalKeyMonitor = nil
        globalFlagMonitor = nil
    }

    // MARK: - Permission
    private func promptForPermissionsIfNeeded() {
        _ = AXIsProcessTrustedWithOptions([
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary)

        if !CGPreflightListenEventAccess() {
            _ = CGRequestListenEventAccess()
        }
    }

    private func startGlobalMonitors() {
        if let globalKeyMonitor { NSEvent.removeMonitor(globalKeyMonitor) }
        if let globalFlagMonitor { NSEvent.removeMonitor(globalFlagMonitor) }

        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            self?.handleGlobalKeyEvent(event)
        }
        globalFlagMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handleGlobalFlagsChanged(event)
        }

        DebugLog.shared.add("NSEvent global hotkey monitors installed")
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
        // Murmur's push-to-talk shortcuts are modifier-only chords handled
        // through flagsChanged so Fn and Fn+Control can be distinguished.
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

    private func handleGlobalKeyEvent(_ event: NSEvent) {
        let keyCode = Int64(event.keyCode)
        guard let mode = mode(for: keyCode) else {
            logUnmatchedEvent(source: "NSEvent", type: event.type == .keyDown ? "down" : "up", keyCode: keyCode)
            return
        }

        let isDown = event.type == .keyDown
        let autorepeat = event.isARepeat
        logHotkeyEdge(isDown: isDown, autorepeat: autorepeat, mode: mode, keyCode: keyCode)

        switch mode {
        case .raw:
            handleEdge(isDown: isDown, autorepeat: autorepeat, current: &rawIsDown, mode: mode)
        case .llm:
            handleEdge(isDown: isDown, autorepeat: autorepeat, current: &llmIsDown, mode: mode)
        }
    }

    private func handleGlobalFlagsChanged(_ event: NSEvent) {
        let keyCode = Int64(event.keyCode)
        guard Self.fixedModifierKeyCodes.contains(keyCode) else {
            logUnmatchedEvent(source: "NSEvent flags", type: "changed", keyCode: keyCode)
            return
        }

        handleModifierState(fnPressed: event.modifierFlags.contains(.function),
                            controlPressed: event.modifierFlags.contains(.control),
                            source: "NSEvent flags",
                            keyCode: keyCode)
    }

    private func handleModifierFlagsChanged(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard Self.fixedModifierKeyCodes.contains(keyCode) else { return Unmanaged.passUnretained(event) }

        let shouldConsume = handleModifierState(fnPressed: event.flags.contains(.maskSecondaryFn),
                                                controlPressed: event.flags.contains(.maskControl),
                                                source: "CGEvent flags",
                                                keyCode: keyCode)

        return activeTapCanConsume && shouldConsume ? nil : Unmanaged.passUnretained(event)
    }

    @discardableResult
    private func handleModifierState(fnPressed: Bool,
                                     controlPressed: Bool,
                                     source: String,
                                     keyCode: Int64) -> Bool {
        var desiredMode: DictationMode?

        if fnPressed && controlPressed {
            desiredMode = .llm
        } else if fnPressed && !suppressRawUntilFnRelease {
            desiredMode = .raw
        } else if !fnPressed {
            suppressRawUntilFnRelease = false
        }

        if llmIsDown && desiredMode == .raw {
            // If Control is released before Fn, end rewrite mode but do not
            // accidentally start a new raw recording for the tail of the hold.
            suppressRawUntilFnRelease = true
            desiredMode = nil
        }

        DebugLog.shared.add("\(source) state: fn=\(fnPressed), control=\(controlPressed), desired=\(desiredMode == .raw ? "raw" : desiredMode == .llm ? "rewrite" : "none"), keyCode=\(keyCode)")

        setActiveMode(desiredMode, keyCode: keyCode)
        return fnPressed || rawIsDown || llmIsDown || keyCode == Self.fnKeyCode || Self.controlKeyCodes.contains(keyCode)
    }

    private func setActiveMode(_ desiredMode: DictationMode?, keyCode: Int64) {
        if desiredMode != .raw {
            pendingRawStartToken = nil
        }

        if desiredMode != .raw && rawIsDown {
            rawIsDown = false
            logHotkeyEdge(isDown: false, autorepeat: false, mode: .raw, keyCode: keyCode)
            DispatchQueue.main.async { self.onRelease?(.raw) }
        }

        if desiredMode != .llm && llmIsDown {
            llmIsDown = false
            logHotkeyEdge(isDown: false, autorepeat: false, mode: .llm, keyCode: keyCode)
            DispatchQueue.main.async { self.onRelease?(.llm) }
        }

        if desiredMode == .raw && !rawIsDown && pendingRawStartToken == nil {
            let token = UUID()
            pendingRawStartToken = token
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                guard let self,
                      self.pendingRawStartToken == token,
                      !self.rawIsDown,
                      !self.llmIsDown else { return }

                self.pendingRawStartToken = nil
                self.rawIsDown = true
                self.logHotkeyEdge(isDown: true, autorepeat: false, mode: .raw, keyCode: keyCode)
                self.onPress?(.raw)
            }
        }

        if desiredMode == .llm && !llmIsDown {
            llmIsDown = true
            logHotkeyEdge(isDown: true, autorepeat: false, mode: .llm, keyCode: keyCode)
            DispatchQueue.main.async { self.onPress?(.llm) }
        }
    }

    private func logHotkeyEdge(isDown: Bool, autorepeat: Bool, mode: DictationMode, keyCode: Int64) {
        guard !autorepeat || !isDown else { return }
        let edge = isDown ? "down" : "up"
        let label = mode == .raw ? "raw" : "rewrite"
        DebugLog.shared.add("Hotkey \(edge) matched mode=\(label), keyCode=\(keyCode)")
    }

    private func logUnmatchedEvent(source: String, type: String, keyCode: Int64) {
        guard unmatchedEventLogCount < 12 else { return }
        unmatchedEventLogCount += 1
        DebugLog.shared.add("Hotkey monitor saw unmatched \(source) \(type), keyCode=\(keyCode)")
    }
}
