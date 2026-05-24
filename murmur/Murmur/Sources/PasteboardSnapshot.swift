//
//  PasteboardSnapshot.swift
//  Preserves the user's clipboard across temporary copy/paste operations.
//

import AppKit

struct PasteboardSnapshot {
    private let items: [NSPasteboardItem]

    init(_ pasteboard: NSPasteboard = .general) {
        items = pasteboard.pasteboardItems?.map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        } ?? []
    }

    func restore(to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        pasteboard.writeObjects(items)
    }
}
