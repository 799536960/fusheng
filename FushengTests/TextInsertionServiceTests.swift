import AppKit
import XCTest
@testable import Fusheng

final class TextInsertionServiceTests: XCTestCase {
    func testPasteWritesTextPostsShortcutAndRestoresClipboard() async throws {
        let previousItem = NSPasteboardItem()
        previousItem.setString("previous", forType: .string)
        let pasteboard = SpyTextPasteboard(snapshot: [previousItem])
        let poster = SpyPasteEventPoster()
        let service = TextInsertionService(pasteboard: pasteboard, pasteEventPoster: poster, restoreDelayNanoseconds: 0)

        try await service.paste(text: "hello", restoreClipboard: true)

        XCTAssertEqual(pasteboard.clearCount, 2)
        XCTAssertEqual(pasteboard.setStrings, ["hello"])
        XCTAssertEqual(poster.postCount, 1)
        XCTAssertEqual(pasteboard.restoredItems?.first?.string(forType: .string), "previous")
    }

    func testPasteDoesNotRestoreClipboardWhenRestoreIsDisabled() async throws {
        let previousItem = NSPasteboardItem()
        previousItem.setString("previous", forType: .string)
        let pasteboard = SpyTextPasteboard(snapshot: [previousItem])
        let poster = SpyPasteEventPoster()
        let service = TextInsertionService(pasteboard: pasteboard, pasteEventPoster: poster, restoreDelayNanoseconds: 0)

        try await service.paste(text: "hello", restoreClipboard: false)

        XCTAssertEqual(pasteboard.clearCount, 1)
        XCTAssertNil(pasteboard.restoredItems)
        XCTAssertEqual(poster.postCount, 1)
    }

    func testPasteThrowsWhenClipboardWriteFails() async {
        let previousItem = NSPasteboardItem()
        previousItem.setString("previous", forType: .string)
        let pasteboard = SpyTextPasteboard(snapshot: [previousItem], canSetString: false)
        let poster = SpyPasteEventPoster()
        let service = TextInsertionService(pasteboard: pasteboard, pasteEventPoster: poster, restoreDelayNanoseconds: 0)

        do {
            try await service.paste(text: "hello", restoreClipboard: true)
            XCTFail("Expected paste to throw")
        } catch {
            XCTAssertEqual(error as? AppError, .insertionFailed("无法写入剪贴板"))
            XCTAssertEqual(pasteboard.clearCount, 2)
            XCTAssertEqual(pasteboard.restoredItems?.first?.string(forType: .string), "previous")
            XCTAssertEqual(poster.postCount, 0)
        }
    }

    func testPasteThrowsWhenPasteEventPostingFails() async {
        let pasteboard = SpyTextPasteboard()
        let poster = SpyPasteEventPoster(error: AppError.insertionFailed("无法创建粘贴事件"))
        let service = TextInsertionService(pasteboard: pasteboard, pasteEventPoster: poster, restoreDelayNanoseconds: 0)

        do {
            try await service.paste(text: "hello", restoreClipboard: true)
            XCTFail("Expected paste to throw")
        } catch {
            XCTAssertEqual(error as? AppError, .insertionFailed("无法创建粘贴事件"))
            XCTAssertEqual(pasteboard.clearCount, 2)
            XCTAssertEqual(poster.postCount, 1)
        }
    }

    func testCopyToClipboardWritesTextWithoutPostingPasteShortcut() throws {
        let pasteboard = SpyTextPasteboard()
        let poster = SpyPasteEventPoster()
        let service = TextInsertionService(pasteboard: pasteboard, pasteEventPoster: poster, restoreDelayNanoseconds: 0)

        try service.copyToClipboard(text: "hello")

        XCTAssertEqual(pasteboard.clearCount, 1)
        XCTAssertEqual(pasteboard.setStrings, ["hello"])
        XCTAssertEqual(pasteboard.currentString, "hello")
        XCTAssertEqual(poster.postCount, 0)
    }

    func testCopyToClipboardThrowsWhenClipboardWriteFails() {
        let pasteboard = SpyTextPasteboard(canSetString: false)
        let service = TextInsertionService(pasteboard: pasteboard, restoreDelayNanoseconds: 0)

        do {
            try service.copyToClipboard(text: "hello")
            XCTFail("Expected copy to throw")
        } catch {
            XCTAssertEqual(error as? AppError, .insertionFailed("无法写入剪贴板"))
            XCTAssertEqual(pasteboard.clearCount, 1)
        }
    }

    func testCompositionUpdatesReplacePreviousPartialAndCommitRestoresOriginalClipboard() async throws {
        let previousItem = NSPasteboardItem()
        previousItem.setString("previous", forType: .string)
        let pasteboard = SpyTextPasteboard(snapshot: [previousItem])
        let poster = SpyPasteEventPoster()
        let selectionPoster = SpyTextSelectionPoster()
        let service = TextInsertionService(
            pasteboard: pasteboard,
            pasteEventPoster: poster,
            textSelectionPoster: selectionPoster,
            restoreDelayNanoseconds: 0
        )
        let composition = await service.makeComposition()

        try await composition.update(text: "你好")
        try await composition.update(text: "你好世界")
        try await composition.commit(text: "整理后的完整文本", restoreClipboard: true)

        XCTAssertEqual(selectionPoster.selectedCounts, [4])
        XCTAssertEqual(pasteboard.setStrings, ["你好", "世界", "整理后的完整文本"])
        XCTAssertEqual(poster.postCount, 3)
        XCTAssertEqual(pasteboard.restoredItems?.first?.string(forType: .string), "previous")
    }

    func testCompositionCommitReturnsBeforeDelayedClipboardRestore() async throws {
        let previousItem = NSPasteboardItem()
        previousItem.setString("previous", forType: .string)
        let pasteboard = SpyTextPasteboard(snapshot: [previousItem])
        let poster = SpyPasteEventPoster()
        let service = TextInsertionService(
            pasteboard: pasteboard,
            pasteEventPoster: poster,
            restoreDelayNanoseconds: 300_000_000
        )
        let composition = await service.makeComposition()

        let start = ContinuousClock.now
        try await composition.commit(text: "最终文本", restoreClipboard: true)
        let elapsed = start.duration(to: .now)

        XCTAssertLessThan(elapsed, .milliseconds(150))
        XCTAssertNil(pasteboard.restoredItems)

        try await Task.sleep(nanoseconds: 350_000_000)

        XCTAssertEqual(pasteboard.restoredItems?.first?.string(forType: .string), "previous")
    }

    func testCompositionAppendsOnlyNewSuffixWhenSelectionReplacementIsIgnored() async throws {
        let pasteboard = SpyTextPasteboard()
        let simulatedField = SimulatedTextField()
        let poster = AppendingPasteEventPoster(pasteboard: pasteboard, field: simulatedField)
        let selectionPoster = SpyTextSelectionPoster()
        let service = TextInsertionService(
            pasteboard: pasteboard,
            pasteEventPoster: poster,
            textSelectionPoster: selectionPoster,
            restoreDelayNanoseconds: 0
        )
        let composition = await service.makeComposition()

        try await composition.update(text: "你能听到")
        try await composition.update(text: "你能听到我说话吗?")
        try await composition.commit(text: "你能听到我说话吗? 你知道我在说什么吗?", restoreClipboard: false)

        XCTAssertEqual(simulatedField.text, "你能听到我说话吗? 你知道我在说什么吗?")
        XCTAssertEqual(selectionPoster.selectedCounts, [])
    }
}

private final class SpyTextPasteboard: TextPasteboardManaging {
    private let snapshot: [NSPasteboardItem]?
    private let canSetString: Bool
    private(set) var clearCount = 0
    private(set) var setStrings: [String] = []
    private(set) var restoredItems: [NSPasteboardItem]?
    private(set) var currentString: String?

    init(snapshot: [NSPasteboardItem]? = nil, canSetString: Bool = true) {
        self.snapshot = snapshot
        self.canSetString = canSetString
    }

    func currentItems() -> [NSPasteboardItem]? {
        snapshot
    }

    func clearContents() {
        clearCount += 1
        currentString = nil
    }

    func setString(_ string: String) -> Bool {
        setStrings.append(string)
        currentString = string
        return canSetString
    }

    func restoreItems(_ items: [NSPasteboardItem]) {
        restoredItems = items
        currentString = items.first?.string(forType: .string)
    }
}

private final class SpyPasteEventPoster: PasteEventPosting {
    private(set) var postCount = 0
    private let error: Error?

    init(error: Error? = nil) {
        self.error = error
    }

    func postPaste() throws {
        postCount += 1
        if let error {
            throw error
        }
    }
}

private final class SpyTextSelectionPoster: TextSelectionPosting {
    private(set) var selectedCounts: [Int] = []
    private let error: Error?

    init(error: Error? = nil) {
        self.error = error
    }

    func selectPreviousCharacters(_ count: Int) throws {
        selectedCounts.append(count)
        if let error {
            throw error
        }
    }
}

private final class SimulatedTextField {
    var text = ""
}

private final class AppendingPasteEventPoster: PasteEventPosting {
    private let pasteboard: SpyTextPasteboard
    private let field: SimulatedTextField

    init(pasteboard: SpyTextPasteboard, field: SimulatedTextField) {
        self.pasteboard = pasteboard
        self.field = field
    }

    func postPaste() throws {
        field.text += pasteboard.currentString ?? ""
    }
}
