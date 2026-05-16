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

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from Dock — pure menu-bar app.
        NSApp.setActivationPolicy(.accessory)

        StatusBarController.shared.install()
        coordinator.start()
        let floatingRecordButton = FloatingRecordButtonController(coordinator: coordinator)
        floatingRecordButton.show()
        self.floatingRecordButton = floatingRecordButton
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
        coordinator.stop()
    }
}
