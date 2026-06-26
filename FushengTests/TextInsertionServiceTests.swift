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

    func testPasteRestoresClipboardWithDetachedPasteboardItems() async throws {
        let previousItem = NSPasteboardItem()
        previousItem.setString("previous", forType: .string)
        let pasteboard = SpyTextPasteboard(snapshot: [previousItem])
        let poster = SpyPasteEventPoster()
        let service = TextInsertionService(pasteboard: pasteboard, pasteEventPoster: poster, restoreDelayNanoseconds: 0)

        try await service.paste(text: "hello", restoreClipboard: true)

        let restoredItem = try XCTUnwrap(pasteboard.restoredItems?.first)
        XCTAssertEqual(restoredItem.string(forType: .string), "previous")
        XCTAssertFalse(restoredItem === previousItem)
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
            textSelectionReader: nil,
            restoreDelayNanoseconds: 0,
            textSelectionDelayNanoseconds: 0
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

    func testCompositionCommitReplacesLivePartialEvenWhenFinalTextExtendsIt() async throws {
        let pasteboard = SpyTextPasteboard()
        let poster = SpyPasteEventPoster()
        let selectionPoster = SpyTextSelectionPoster()
        let service = TextInsertionService(
            pasteboard: pasteboard,
            pasteEventPoster: poster,
            textSelectionPoster: selectionPoster,
            textSelectionReader: nil,
            restoreDelayNanoseconds: 0,
            textSelectionDelayNanoseconds: 0
        )
        let composition = await service.makeComposition()

        try await composition.update(text: "你好")
        try await composition.commit(text: "你好世界", restoreClipboard: false)

        XCTAssertEqual(selectionPoster.selectedCounts, [2])
        XCTAssertEqual(pasteboard.setStrings, ["你好", "你好世界"])
        XCTAssertEqual(poster.postCount, 2)
    }

    func testCompositionWaitsForSelectionBeforeCommittingFinalText() async throws {
        let pasteboard = SpyTextPasteboard()
        let simulatedField = SimulatedTextField()
        let poster = ReplacingPasteEventPoster(pasteboard: pasteboard, field: simulatedField)
        let selectionPoster = DeferredTextSelectionPoster(
            field: simulatedField,
            delayNanoseconds: 50_000_000
        )
        let service = TextInsertionService(
            pasteboard: pasteboard,
            pasteEventPoster: poster,
            textSelectionPoster: selectionPoster,
            textSelectionReader: nil,
            restoreDelayNanoseconds: 0,
            textSelectionDelayNanoseconds: 80_000_000
        )
        let composition = await service.makeComposition()
        let livePartial = "还是有重复语音的问题。问题感觉没有解决"
        let finalText = "还是有重复语音的问题。问题感觉没有解决，好像不是。之前说的那些问题，你再解看一下。"

        try await composition.update(text: livePartial)
        try await composition.commit(text: finalText, restoreClipboard: false)
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(simulatedField.text, finalText)
        XCTAssertEqual(selectionPoster.selectedCounts, [livePartial.count])
    }

    func testCompositionWaitsUntilSelectionReaderConfirmsFullLivePartialIsSelected() async throws {
        let pasteboard = SpyTextPasteboard()
        let simulatedField = SimulatedTextField()
        let selectionController = ProgressiveTextSelectionController(
            field: simulatedField,
            unselectedPrefixCount: 8,
            partialDelayNanoseconds: 50_000_000,
            completeDelayNanoseconds: 500_000_000
        )
        let poster = ReplacingPasteEventPoster(pasteboard: pasteboard, field: simulatedField)
        let service = TextInsertionService(
            pasteboard: pasteboard,
            pasteEventPoster: poster,
            textSelectionPoster: selectionController,
            textSelectionReader: selectionController,
            restoreDelayNanoseconds: 0,
            textSelectionDelayNanoseconds: 80_000_000
        )
        let composition = await service.makeComposition()
        let finalText = "呃，当我的语音如果文字比较长的话。是在输入框里面的话，还是会出现重复的问题，好像。但是他不是。嗯，马上会出现，它是偶尔会出现，是一个偶现的问题。嗯。要不要再测一下？还是怎么说？这个测的话要怎么测呢？因为它不是每次都出现，它有的时候出现，有的时候不出现。那怎么办呢？那怎么测试呢？"
        let livePartial = "呃，当我的语音如" + finalText

        try await composition.update(text: livePartial)
        try await composition.commit(text: finalText, restoreClipboard: false)

        XCTAssertEqual(simulatedField.text, finalText)
        XCTAssertEqual(selectionController.selectedCounts, [livePartial.count])
        XCTAssertGreaterThanOrEqual(selectionController.readCount, 2)
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

    func testCompositionAppendsOnlyNewSuffixForCumulativePartialUpdates() async throws {
        let pasteboard = SpyTextPasteboard()
        let simulatedField = SimulatedTextField()
        let poster = AppendingPasteEventPoster(pasteboard: pasteboard, field: simulatedField)
        let selectionPoster = SpyTextSelectionPoster()
        let service = TextInsertionService(
            pasteboard: pasteboard,
            pasteEventPoster: poster,
            textSelectionPoster: selectionPoster,
            textSelectionReader: nil,
            restoreDelayNanoseconds: 0,
            textSelectionDelayNanoseconds: 0
        )
        let composition = await service.makeComposition()

        try await composition.update(text: "你能听到")
        try await composition.update(text: "你能听到我说话吗?")

        XCTAssertEqual(simulatedField.text, "你能听到我说话吗?")
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
    private var selectedSuffixCount = 0
    var selectedCharacterCount: Int { selectedSuffixCount }

    func selectPreviousCharacters(_ count: Int) {
        selectedSuffixCount = min(count, text.count)
    }

    func paste(_ string: String) {
        guard selectedSuffixCount > 0 else {
            text += string
            return
        }

        text = String(text.dropLast(selectedSuffixCount)) + string
        selectedSuffixCount = 0
    }
}

private final class AppendingPasteEventPoster: PasteEventPosting {
    private let pasteboard: SpyTextPasteboard
    private let field: SimulatedTextField

    init(pasteboard: SpyTextPasteboard, field: SimulatedTextField) {
        self.pasteboard = pasteboard
        self.field = field
    }

    func postPaste() throws {
        field.paste(pasteboard.currentString ?? "")
    }
}

private final class ReplacingPasteEventPoster: PasteEventPosting {
    private let pasteboard: SpyTextPasteboard
    private let field: SimulatedTextField

    init(pasteboard: SpyTextPasteboard, field: SimulatedTextField) {
        self.pasteboard = pasteboard
        self.field = field
    }

    func postPaste() throws {
        field.paste(pasteboard.currentString ?? "")
    }
}

private final class DeferredTextSelectionPoster: TextSelectionPosting {
    private let field: SimulatedTextField
    private let delayNanoseconds: UInt64
    private(set) var selectedCounts: [Int] = []

    init(field: SimulatedTextField, delayNanoseconds: UInt64) {
        self.field = field
        self.delayNanoseconds = delayNanoseconds
    }

    func selectPreviousCharacters(_ count: Int) throws {
        selectedCounts.append(count)

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            field.selectPreviousCharacters(count)
        }
    }
}

private final class ProgressiveTextSelectionController: TextSelectionPosting, TextSelectionReading {
    private let field: SimulatedTextField
    private let unselectedPrefixCount: Int
    private let partialDelayNanoseconds: UInt64
    private let completeDelayNanoseconds: UInt64
    private(set) var selectedCounts: [Int] = []
    private(set) var readCount = 0

    init(
        field: SimulatedTextField,
        unselectedPrefixCount: Int,
        partialDelayNanoseconds: UInt64,
        completeDelayNanoseconds: UInt64
    ) {
        self.field = field
        self.unselectedPrefixCount = unselectedPrefixCount
        self.partialDelayNanoseconds = partialDelayNanoseconds
        self.completeDelayNanoseconds = completeDelayNanoseconds
    }

    func selectPreviousCharacters(_ count: Int) throws {
        selectedCounts.append(count)

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: partialDelayNanoseconds)
            field.selectPreviousCharacters(max(count - unselectedPrefixCount, 0))
            try? await Task.sleep(nanoseconds: completeDelayNanoseconds - partialDelayNanoseconds)
            field.selectPreviousCharacters(count)
        }
    }

    func selectedCharacterCount() -> Int? {
        readCount += 1
        return field.selectedCharacterCount
    }
}
