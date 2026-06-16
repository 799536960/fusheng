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
}

private final class SpyTextPasteboard: TextPasteboardManaging {
    private let snapshot: [NSPasteboardItem]?
    private let canSetString: Bool
    private(set) var clearCount = 0
    private(set) var setStrings: [String] = []
    private(set) var restoredItems: [NSPasteboardItem]?

    init(snapshot: [NSPasteboardItem]? = nil, canSetString: Bool = true) {
        self.snapshot = snapshot
        self.canSetString = canSetString
    }

    func currentItems() -> [NSPasteboardItem]? {
        snapshot
    }

    func clearContents() {
        clearCount += 1
    }

    func setString(_ string: String) -> Bool {
        setStrings.append(string)
        return canSetString
    }

    func restoreItems(_ items: [NSPasteboardItem]) {
        restoredItems = items
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
