import XCTest
@testable import Fusheng

final class SettingsStoreTests: XCTestCase {
    func testDefaultSettings() {
        let defaults = UserDefaults(suiteName: "SettingsStoreTests.default")!
        defaults.removePersistentDomain(forName: "SettingsStoreTests.default")

        let store = SettingsStore(defaults: defaults)

        XCTAssertEqual(store.triggerMode, .toggle)
        XCTAssertEqual(store.asrModel, "fun-asr-realtime")
        XCTAssertEqual(store.polishModel, "qwen-plus")
        XCTAssertEqual(store.polishMode, .clean)
        XCTAssertTrue(store.autoPasteEnabled)
        XCTAssertTrue(store.restoreClipboardEnabled)
        XCTAssertTrue(store.keepDraftHistoryEnabled)
    }

    func testPersistsSettings() {
        let defaults = UserDefaults(suiteName: "SettingsStoreTests.persist")!
        defaults.removePersistentDomain(forName: "SettingsStoreTests.persist")

        var store = SettingsStore(defaults: defaults)
        store.triggerMode = .hold
        store.asrModel = "custom-asr"
        store.polishModel = "custom-chat"
        store.polishMode = .professional
        store.autoPasteEnabled = false
        store.restoreClipboardEnabled = false
        store.keepDraftHistoryEnabled = false

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.triggerMode, .hold)
        XCTAssertEqual(reloaded.asrModel, "custom-asr")
        XCTAssertEqual(reloaded.polishModel, "custom-chat")
        XCTAssertEqual(reloaded.polishMode, .professional)
        XCTAssertFalse(reloaded.autoPasteEnabled)
        XCTAssertFalse(reloaded.restoreClipboardEnabled)
        XCTAssertFalse(reloaded.keepDraftHistoryEnabled)
    }
}
