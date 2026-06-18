import XCTest
@testable import Fusheng

final class SettingsStoreTests: XCTestCase {
    func testDefaultSettings() {
        let defaults = UserDefaults(suiteName: "SettingsStoreTests.default")!
        defaults.removePersistentDomain(forName: "SettingsStoreTests.default")

        let store = SettingsStore(defaults: defaults)

        XCTAssertEqual(store.triggerMode, .hold)
        XCTAssertEqual(store.holdKey, .f9)
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
        store.holdKey = .f12
        store.asrModel = "custom-asr"
        store.polishModel = "custom-chat"
        store.polishMode = .professional
        store.autoPasteEnabled = false
        store.restoreClipboardEnabled = false
        store.keepDraftHistoryEnabled = false

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.triggerMode, .hold)
        XCTAssertEqual(reloaded.holdKey, .f12)
        XCTAssertEqual(reloaded.asrModel, "custom-asr")
        XCTAssertEqual(reloaded.polishModel, "custom-chat")
        XCTAssertEqual(reloaded.polishMode, .professional)
        XCTAssertFalse(reloaded.autoPasteEnabled)
        XCTAssertFalse(reloaded.restoreClipboardEnabled)
        XCTAssertFalse(reloaded.keepDraftHistoryEnabled)
    }

    func testPersistsCustomSingleKeyHotkey() {
        let defaults = UserDefaults(suiteName: "SettingsStoreTests.customHotkey")!
        defaults.removePersistentDomain(forName: "SettingsStoreTests.customHotkey")

        var store = SettingsStore(defaults: defaults)
        store.holdKey = SpeechHotkey(keyCode: 0, displayName: "A")

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.holdKey, SpeechHotkey(keyCode: 0, displayName: "A"))
    }

    func testPersistsPolishStrategyPerMode() {
        let defaults = UserDefaults(suiteName: "SettingsStoreTests.polishStrategy")!
        defaults.removePersistentDomain(forName: "SettingsStoreTests.polishStrategy")

        let store = SettingsStore(defaults: defaults)
        var cleanStrategy = TextPolishStrategy.default(for: .clean)
        cleanStrategy.isCustomEnabled = true
        cleanStrategy.modeInstruction = "只清理，不改写。"
        cleanStrategy.extraInstructions = "保留命令语气。"
        cleanStrategy.allowLightPolish = false
        store.savePolishStrategy(cleanStrategy, for: .clean)

        var professionalStrategy = TextPolishStrategy.default(for: .professional)
        professionalStrategy.isCustomEnabled = true
        professionalStrategy.modeInstruction = "让断句更适合正式说明。"
        professionalStrategy.extraInstructions = "不要添加客套话。"
        professionalStrategy.allowLightPolish = true
        store.savePolishStrategy(professionalStrategy, for: .professional)

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.polishStrategy(for: .clean).modeInstruction, "只清理，不改写。")
        XCTAssertEqual(reloaded.polishStrategy(for: .clean).extraInstructions, "保留命令语气。")
        XCTAssertEqual(reloaded.polishStrategy(for: .professional).modeInstruction, "让断句更适合正式说明。")
        XCTAssertEqual(reloaded.polishStrategy(for: .professional).extraInstructions, "不要添加客套话。")
        XCTAssertEqual(reloaded.polishStrategy(for: .original), .default(for: .original))
    }

    func testResetPolishStrategyOnlyResetsSelectedMode() {
        let defaults = UserDefaults(suiteName: "SettingsStoreTests.resetOnePolishStrategy")!
        defaults.removePersistentDomain(forName: "SettingsStoreTests.resetOnePolishStrategy")

        let store = SettingsStore(defaults: defaults)
        var cleanStrategy = TextPolishStrategy.default(for: .clean)
        cleanStrategy.isCustomEnabled = true
        cleanStrategy.modeInstruction = "清理模式自定义"
        store.savePolishStrategy(cleanStrategy, for: .clean)

        var conciseStrategy = TextPolishStrategy.default(for: .concise)
        conciseStrategy.isCustomEnabled = true
        conciseStrategy.modeInstruction = "简短模式自定义"
        store.savePolishStrategy(conciseStrategy, for: .concise)

        store.resetPolishStrategy(for: .clean)

        XCTAssertEqual(store.polishStrategy(for: .clean), .default(for: .clean))
        XCTAssertEqual(store.polishStrategy(for: .concise).modeInstruction, "简短模式自定义")
    }

    func testResetAllPolishStrategiesResetsEveryMode() {
        let defaults = UserDefaults(suiteName: "SettingsStoreTests.resetAllPolishStrategies")!
        defaults.removePersistentDomain(forName: "SettingsStoreTests.resetAllPolishStrategies")

        let store = SettingsStore(defaults: defaults)
        for mode in TextPolishMode.allCases {
            var strategy = TextPolishStrategy.default(for: mode)
            strategy.isCustomEnabled = true
            strategy.modeInstruction = "自定义 \(mode.rawValue)"
            store.savePolishStrategy(strategy, for: mode)
        }

        store.resetAllPolishStrategies()

        for mode in TextPolishMode.allCases {
            XCTAssertEqual(store.polishStrategy(for: mode), .default(for: mode))
        }
    }
}
