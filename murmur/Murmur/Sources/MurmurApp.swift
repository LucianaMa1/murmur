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

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from Dock — pure menu-bar app.
        NSApp.setActivationPolicy(.accessory)

        StatusBarController.shared.install()
        coordinator.start()

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
