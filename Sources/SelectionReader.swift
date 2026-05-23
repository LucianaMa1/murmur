//
//  SelectionReader.swift
//  Reads highlighted text from the target app using macOS Accessibility.
//

import ApplicationServices
import AppKit

enum SelectionReader {
    static func selectedText(in app: NSRunningApplication?, completion: @escaping (String?) -> Void) {
        if let selected = selectedTextFromAccessibility(in: app) {
            completion(selected)
            return
        }

        selectedTextFromClipboardFallback(in: app, completion: completion)
    }

    private static func selectedTextFromAccessibility(in app: NSRunningApplication?) -> String? {
        guard ClipboardWriter.ensureAccessibilityPermission(prompt: false) else {
            DebugLog.shared.add("Selection context skipped: Accessibility permission is not trusted")
            return nil
        }

        guard let app else {
            DebugLog.shared.add("Selection context skipped: no target app")
            return nil
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let focused = copyAttribute(.focusedUIElement, from: appElement) else {
            DebugLog.shared.add("Selection context skipped: no focused accessibility element")
            return nil
        }

        if let selected = stringAttribute(.selectedText, from: focused), !selected.isEmpty {
            let normalized = selected.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { return nil }
            DebugLog.shared.add("Selection context captured via Accessibility with \(normalized.count) character(s)")
            return normalized
        }

        if let selected = selectedTextFromChildren(of: focused) {
            return selected
        }

        DebugLog.shared.add("Selection context skipped: focused element has no selected text")
        return nil
    }

    private static func selectedTextFromChildren(of element: AXUIElement) -> String? {
        guard let children = arrayAttribute(.selectedChildren, from: element) else { return nil }

        let text = children.compactMap { child -> String? in
            if let selected = stringAttribute(.selectedText, from: child) {
                return selected
            }
            if let value = stringAttribute(.value, from: child) {
                return value
            }
            return nil
        }
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else { return nil }
        DebugLog.shared.add("Selection context captured via selected children with \(text.count) character(s)")
        return text
    }

    private static func selectedTextFromClipboardFallback(in app: NSRunningApplication?,
                                                          completion: @escaping (String?) -> Void) {
        guard ClipboardWriter.ensureAccessibilityPermission(prompt: false) else {
            completion(nil)
            return
        }

        let pasteboard = NSPasteboard.general
        let previousString = pasteboard.string(forType: .string)
        let marker = "murmur-selection-marker-\(UUID().uuidString)"

        pasteboard.clearContents()
        pasteboard.setString(marker, forType: .string)

        if let app {
            DebugLog.shared.add("Selection context fallback: activating \(app.localizedName ?? app.bundleIdentifier ?? "<unknown>") before Cmd+C")
            app.activate(options: [])
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            simulateCmdC()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                let copied = pasteboard.string(forType: .string)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if let previousString {
                    pasteboard.clearContents()
                    pasteboard.setString(previousString, forType: .string)
                } else {
                    pasteboard.clearContents()
                }

                guard let copied,
                      !copied.isEmpty,
                      copied != marker
                else {
                    DebugLog.shared.add("Selection context fallback skipped: Cmd+C did not copy selected text")
                    completion(nil)
                    return
                }

                DebugLog.shared.add("Selection context captured via Cmd+C fallback with \(copied.count) character(s)")
                completion(copied)
            }
        }
    }

    private static func simulateCmdC() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let cKeyCode: CGKeyCode = 0x08

        let down = CGEvent(keyboardEventSource: source, virtualKey: cKeyCode, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: cKeyCode, keyDown: false)
        up?.flags = .maskCommand

        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }

    private static func copyAttribute(_ attribute: Attribute, from element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute.rawValue as CFString, &value)
        guard result == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    private static func stringAttribute(_ attribute: Attribute, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute.rawValue as CFString, &value)
        guard result == .success else { return nil }
        return value as? String
    }

    private static func arrayAttribute(_ attribute: Attribute, from element: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute.rawValue as CFString, &value)
        guard result == .success,
              let array = value as? [Any]
        else { return nil }

        return array.compactMap { item in
            let ref = item as CFTypeRef
            guard CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
            return (ref as! AXUIElement)
        }
    }

    private enum Attribute: String {
        case focusedUIElement = "AXFocusedUIElement"
        case selectedChildren = "AXSelectedChildren"
        case selectedText = "AXSelectedText"
        case value = "AXValue"
    }
}
