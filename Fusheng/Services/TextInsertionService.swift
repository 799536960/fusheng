import AppKit
import Foundation

protocol TextPasteboardManaging {
    func currentItems() -> [NSPasteboardItem]?
    func clearContents()
    func setString(_ string: String) -> Bool
    func restoreItems(_ items: [NSPasteboardItem])
}

struct SystemTextPasteboard: TextPasteboardManaging {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func currentItems() -> [NSPasteboardItem]? {
        pasteboard.pasteboardItems
    }

    func clearContents() {
        pasteboard.clearContents()
    }

    func setString(_ string: String) -> Bool {
        pasteboard.setString(string, forType: .string)
    }

    func restoreItems(_ items: [NSPasteboardItem]) {
        _ = pasteboard.writeObjects(items)
    }
}

protocol PasteEventPosting {
    func postPaste() throws
}

struct CGEventPastePoster: PasteEventPosting {
    func postPaste() throws {
        guard
            let source = CGEventSource(stateID: .hidSystemState),
            let commandDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true),
            let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
            let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false),
            let commandUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)
        else {
            throw AppError.insertionFailed("无法创建粘贴事件")
        }

        vDown.flags = .maskCommand
        vUp.flags = .maskCommand
        commandDown.post(tap: .cghidEventTap)
        vDown.post(tap: .cghidEventTap)
        vUp.post(tap: .cghidEventTap)
        commandUp.post(tap: .cghidEventTap)
    }
}

struct TextInsertionService: TextInserting {
    private let pasteboard: TextPasteboardManaging
    private let pasteEventPoster: PasteEventPosting
    private let restoreDelayNanoseconds: UInt64

    init(
        pasteboard: TextPasteboardManaging = SystemTextPasteboard(),
        pasteEventPoster: PasteEventPosting = CGEventPastePoster(),
        restoreDelayNanoseconds: UInt64 = 250_000_000
    ) {
        self.pasteboard = pasteboard
        self.pasteEventPoster = pasteEventPoster
        self.restoreDelayNanoseconds = restoreDelayNanoseconds
    }

    func paste(text: String, restoreClipboard: Bool) async throws {
        let previousItems = pasteboard.currentItems()

        pasteboard.clearContents()
        guard pasteboard.setString(text) else {
            if restoreClipboard {
                restore(previousItems)
            }
            throw AppError.insertionFailed("无法写入剪贴板")
        }

        do {
            try pasteEventPoster.postPaste()
        } catch {
            if restoreClipboard {
                restore(previousItems)
            }
            throw error
        }

        if restoreClipboard {
            try await Task.sleep(nanoseconds: restoreDelayNanoseconds)
            restore(previousItems)
        }
    }

    private func restore(_ previousItems: [NSPasteboardItem]?) {
        pasteboard.clearContents()
        if let previousItems {
            pasteboard.restoreItems(previousItems)
        }
    }
}
