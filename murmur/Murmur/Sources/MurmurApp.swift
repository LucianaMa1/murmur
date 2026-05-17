//
//  MurmurApp.swift
//  Entry point. Menu-bar-only app (no Dock icon, no main window).
//

import SwiftUI
import AppKit

@main
struct MurmurApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        Settings {  // empty Scene so SwiftUI is happy
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let coordinator = DictationCoordinator()
    private var floatingRecordButton: FloatingRecordButtonController?
    private var observerTokens: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from Dock — pure menu-bar app.
        NSApp.setActivationPolicy(.accessory)

        StatusBarController.shared.install()
        coordinator.start()
        let floatingRecordButton = FloatingRecordButtonController(coordinator: coordinator)
        floatingRecordButton.show()
        self.floatingRecordButton = floatingRecordButton
        installFloatingControlObservers()
        DebugLog.shared.add("App launched")
        DebugLog.shared.add("Floating hold-to-speak button shown")
        if ClipboardWriter.ensureAccessibilityPermission() {
            DebugLog.shared.add("Accessibility permission is trusted")
        } else {
            DebugLog.shared.add("Accessibility permission is not trusted; enable Murmur in System Settings")
        }

        // First launch: show settings if no API key yet (so F6 actually works).
        if Keychain.read() == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                SettingsWindowController.shared.show()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        for token in observerTokens {
            NotificationCenter.default.removeObserver(token)
        }
        coordinator.stop()
    }

    private func installFloatingControlObservers() {
        let toggle = NotificationCenter.default.addObserver(
            forName: .murmurToggleFloatingControls,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.floatingRecordButton?.toggle()
            }
        }

        let preference = NotificationCenter.default.addObserver(
            forName: .murmurFloatingControlsPreferenceChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                if FloatingControlsPreferences.isEnabled {
                    self?.floatingRecordButton?.show()
                } else {
                    self?.floatingRecordButton?.hide()
                }
            }
        }

        observerTokens.append(contentsOf: [toggle, preference])
    }
}
