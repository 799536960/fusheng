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

protocol TextSelectionPosting {
    func selectPreviousCharacters(_ count: Int) throws
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

struct CGEventTextSelectionPoster: TextSelectionPosting {
    func selectPreviousCharacters(_ count: Int) throws {
        guard count > 0 else { return }

        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw AppError.insertionFailed("无法创建文本选择事件")
        }

        for _ in 0..<count {
            guard
                let leftDown = CGEvent(keyboardEventSource: source, virtualKey: 0x7B, keyDown: true),
                let leftUp = CGEvent(keyboardEventSource: source, virtualKey: 0x7B, keyDown: false)
            else {
                throw AppError.insertionFailed("无法创建文本选择事件")
            }

            leftDown.flags = .maskShift
            leftUp.flags = .maskShift
            leftDown.post(tap: .cghidEventTap)
            leftUp.post(tap: .cghidEventTap)
        }
    }
}

struct TextInsertionService: TextInserting {
    private let pasteboard: TextPasteboardManaging
    private let pasteEventPoster: PasteEventPosting
    private let textSelectionPoster: TextSelectionPosting
    private let restoreDelayNanoseconds: UInt64

    init(
        pasteboard: TextPasteboardManaging = SystemTextPasteboard(),
        pasteEventPoster: PasteEventPosting = CGEventPastePoster(),
        textSelectionPoster: TextSelectionPosting = CGEventTextSelectionPoster(),
        restoreDelayNanoseconds: UInt64 = 250_000_000
    ) {
        self.pasteboard = pasteboard
        self.pasteEventPoster = pasteEventPoster
        self.textSelectionPoster = textSelectionPoster
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

    func copyToClipboard(text: String) throws {
        pasteboard.clearContents()
        guard pasteboard.setString(text) else {
            throw AppError.insertionFailed("无法写入剪贴板")
        }
    }

    @MainActor
    func makeComposition() -> TextComposing {
        LiveTextComposition(
            pasteboard: pasteboard,
            pasteEventPoster: pasteEventPoster,
            textSelectionPoster: textSelectionPoster,
            restoreDelayNanoseconds: restoreDelayNanoseconds
        )
    }

    private func restore(_ previousItems: [NSPasteboardItem]?) {
        pasteboard.clearContents()
        if let previousItems {
            pasteboard.restoreItems(previousItems)
        }
    }
}

@MainActor
private final class LiveTextComposition: TextComposing {
    private let pasteboard: TextPasteboardManaging
    private let pasteEventPoster: PasteEventPosting
    private let textSelectionPoster: TextSelectionPosting
    private let restoreDelayNanoseconds: UInt64
    private let originalItems: [NSPasteboardItem]?
    private var composedText = ""

    init(
        pasteboard: TextPasteboardManaging,
        pasteEventPoster: PasteEventPosting,
        textSelectionPoster: TextSelectionPosting,
        restoreDelayNanoseconds: UInt64
    ) {
        self.pasteboard = pasteboard
        self.pasteEventPoster = pasteEventPoster
        self.textSelectionPoster = textSelectionPoster
        self.restoreDelayNanoseconds = restoreDelayNanoseconds
        self.originalItems = pasteboard.currentItems()
    }

    func update(text: String) async throws {
        try replaceComposedText(with: text, shouldRestoreOriginalClipboard: false)
    }

    func commit(text: String, restoreClipboard: Bool) async throws {
        try replaceComposedText(with: text, shouldRestoreOriginalClipboard: restoreClipboard)

        if restoreClipboard {
            restoreOriginalClipboardAfterDelay()
        }
    }

    private func replaceComposedText(with text: String, shouldRestoreOriginalClipboard: Bool) throws {
        if text.hasPrefix(composedText) {
            let suffix = String(text.dropFirst(composedText.count))
            guard !suffix.isEmpty else {
                composedText = text
                return
            }

            try pasteText(suffix, shouldRestoreOriginalClipboard: shouldRestoreOriginalClipboard)
            composedText = text
            return
        }

        if !composedText.isEmpty {
            try textSelectionPoster.selectPreviousCharacters(composedText.count)
        }

        try pasteText(text, shouldRestoreOriginalClipboard: shouldRestoreOriginalClipboard)
        composedText = text
    }

    private func pasteText(_ text: String, shouldRestoreOriginalClipboard: Bool) throws {
        pasteboard.clearContents()
        guard pasteboard.setString(text) else {
            if shouldRestoreOriginalClipboard {
                restoreOriginalClipboard()
            }
            throw AppError.insertionFailed("无法写入剪贴板")
        }

        do {
            try pasteEventPoster.postPaste()
        } catch {
            if shouldRestoreOriginalClipboard {
                restoreOriginalClipboard()
            }
            throw error
        }
    }

    private func restoreOriginalClipboard() {
        pasteboard.clearContents()
        if let originalItems {
            pasteboard.restoreItems(originalItems)
        }
    }

    private func restoreOriginalClipboardAfterDelay() {
        guard restoreDelayNanoseconds > 0 else {
            restoreOriginalClipboard()
            return
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: restoreDelayNanoseconds)
            restoreOriginalClipboard()
        }
    }
}
