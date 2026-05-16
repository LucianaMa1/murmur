//
//  DebugWindowController.swift
//  Lightweight live diagnostics for the recording pipeline.
//

import AppKit
import SwiftUI

final class DebugLog: ObservableObject {
    static let shared = DebugLog()

    @Published private(set) var lines: [String] = []

    private init() {}

    func add(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let line = "[\(formatter.string(from: Date()))] \(message)"

        DispatchQueue.main.async {
            self.lines.append(line)
            if self.lines.count > 300 {
                self.lines.removeFirst(self.lines.count - 300)
            }
            print(line)
        }
    }

    func clear() {
        DispatchQueue.main.async {
            self.lines.removeAll()
        }
    }
}

@MainActor
final class DebugWindowController {
    static let shared = DebugWindowController()
    private var window: NSWindow?

    private init() {}

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let host = NSHostingController(rootView: DebugView(log: DebugLog.shared))
        let win = NSWindow(contentViewController: host)
        win.title = "Murmur Debug"
        win.styleMask = [.titled, .closable, .resizable]
        win.setContentSize(NSSize(width: 680, height: 420))
        win.isReleasedWhenClosed = false
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = win
    }
}

private struct DebugView: View {
    @ObservedObject var log: DebugLog

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Murmur Debug")
                    .font(.headline)
                Spacer()
                Button("Clear") {
                    log.clear()
                }
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(log.lines.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                        }
                    }
                    .padding(8)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .border(Color.gray.opacity(0.25))
                .onChange(of: log.lines.count) { _, count in
                    guard count > 0 else { return }
                    proxy.scrollTo(count - 1, anchor: .bottom)
                }
            }
        }
        .padding(14)
        .frame(minWidth: 560, minHeight: 320)
    }
}
