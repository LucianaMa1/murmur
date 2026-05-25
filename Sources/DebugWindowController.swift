//
//  DebugWindowController.swift
//  Lightweight live diagnostics for the recording pipeline.
//

import AppKit
import SwiftUI

struct DebugLogEntry: Identifiable {
    let id = UUID()
    let text: String
    let linkURL: URL?
    let linkLabel: String?
}

final class DebugLog: ObservableObject {
    static let shared = DebugLog()

    @Published private(set) var entries: [DebugLogEntry] = []

    private init() {}

    func add(_ message: String) {
        append(message: message, linkURL: nil, linkLabel: nil)
    }

    func addLink(_ message: String, url: URL, label: String) {
        append(message: message, linkURL: url, linkLabel: label)
    }

    private func append(message: String, linkURL: URL?, linkLabel: String?) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let line = "[\(formatter.string(from: Date()))] \(message)"
        let entry = DebugLogEntry(text: line, linkURL: linkURL, linkLabel: linkLabel)

        DispatchQueue.main.async {
            self.entries.append(entry)
            if self.entries.count > 300 {
                self.entries.removeFirst(self.entries.count - 300)
            }
            print(line)
        }
    }

    func clear() {
        DispatchQueue.main.async {
            self.entries.removeAll()
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
                        ForEach(Array(log.entries.enumerated()), id: \.element.id) { index, entry in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(entry.text)
                                    .font(.system(size: 11, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if let linkURL = entry.linkURL, let linkLabel = entry.linkLabel {
                                    Link(linkLabel, destination: linkURL)
                                        .font(.system(size: 11, weight: .medium))
                                }
                            }
                            .id(index)
                        }
                    }
                    .padding(8)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .border(Color.gray.opacity(0.25))
                .onChange(of: log.entries.count) { _, count in
                    guard count > 0 else { return }
                    proxy.scrollTo(count - 1, anchor: .bottom)
                }
            }
        }
        .padding(14)
        .frame(minWidth: 560, minHeight: 320)
    }
}
