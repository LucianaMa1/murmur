//
//  SelectionReader.swift
//  Reads highlighted text from the target app using macOS Accessibility.
//

import ApplicationServices
import AppKit

enum SelectionReader {
    static func selectedText(in app: NSRunningApplication?) -> String? {
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
            DebugLog.shared.add("Selection context captured with \(normalized.count) character(s)")
            return normalized
        }

        DebugLog.shared.add("Selection context skipped: focused element has no selected text")
        return nil
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

    private enum Attribute: String {
        case focusedUIElement = "AXFocusedUIElement"
        case selectedText = "AXSelectedText"
    }
}
