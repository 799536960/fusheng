import XCTest
@testable import Fusheng

@MainActor
final class HotkeyServiceTests: XCTestCase {
    func testStoredToggleModeStillUsesHoldGesture() {
        let defaults = UserDefaults(suiteName: "HotkeyServiceTests.toggle")!
        defaults.removePersistentDomain(forName: "HotkeyServiceTests.toggle")
        var settings = SettingsStore(defaults: defaults)
        settings.triggerMode = .toggle
        let registerer = SpyHotkeyEventRegistering()
        var toggleCount = 0
        var startCount = 0
        var finishCount = 0

        let service = HotkeyService(
            settings: settings,
            registerer: registerer,
            onToggle: { toggleCount += 1 },
            onStart: { startCount += 1 },
            onFinish: { finishCount += 1 }
        )

        service.start()
        registerer.keyDownAction?()
        registerer.keyUpAction?()

        XCTAssertEqual(toggleCount, 0)
        XCTAssertEqual(startCount, 1)
        XCTAssertEqual(finishCount, 1)
    }

    func testHoldModeStartsOnKeyDownAndFinishesOnKeyUp() {
        let defaults = UserDefaults(suiteName: "HotkeyServiceTests.hold")!
        defaults.removePersistentDomain(forName: "HotkeyServiceTests.hold")
        var settings = SettingsStore(defaults: defaults)
        settings.triggerMode = .hold
        let registerer = SpyHotkeyEventRegistering()
        var toggleCount = 0
        var startCount = 0
        var finishCount = 0

        let service = HotkeyService(
            settings: settings,
            registerer: registerer,
            onToggle: { toggleCount += 1 },
            onStart: { startCount += 1 },
            onFinish: { finishCount += 1 }
        )

        service.start()
        registerer.keyDownAction?()
        registerer.keyUpAction?()

        XCTAssertEqual(toggleCount, 0)
        XCTAssertEqual(startCount, 1)
        XCTAssertEqual(finishCount, 1)
    }

    func testHoldModeIgnoresRepeatedKeyDownUntilKeyUp() {
        let defaults = UserDefaults(suiteName: "HotkeyServiceTests.holdRepeat")!
        defaults.removePersistentDomain(forName: "HotkeyServiceTests.holdRepeat")
        var settings = SettingsStore(defaults: defaults)
        settings.triggerMode = .hold
        let registerer = SpyHotkeyEventRegistering()
        var startCount = 0
        var finishCount = 0

        let service = HotkeyService(
            settings: settings,
            registerer: registerer,
            onToggle: {},
            onStart: { startCount += 1 },
            onFinish: { finishCount += 1 }
        )

        service.start()
        registerer.keyDownAction?()
        registerer.keyDownAction?()
        registerer.keyUpAction?()
        registerer.keyDownAction?()
        registerer.keyUpAction?()

        XCTAssertEqual(startCount, 2)
        XCTAssertEqual(finishCount, 2)
    }

    func testHoldModeRecoversWhenPreviousKeyUpWasMissedAfterWorkflowEnded() {
        let defaults = UserDefaults(suiteName: "HotkeyServiceTests.missedKeyUpRecovery")!
        defaults.removePersistentDomain(forName: "HotkeyServiceTests.missedKeyUpRecovery")
        var settings = SettingsStore(defaults: defaults)
        settings.triggerMode = .hold
        let registerer = SpyHotkeyEventRegistering()
        var canStart = true
        var now = Date(timeIntervalSince1970: 1_000)
        var startCount = 0
        var finishCount = 0

        let service = HotkeyService(
            settings: settings,
            registerer: registerer,
            canStart: { canStart },
            onToggle: {},
            onStart: {
                startCount += 1
                canStart = false
            },
            onFinish: { finishCount += 1 },
            stalePressedRecoveryInterval: 1,
            dateProvider: { now }
        )

        service.start()
        registerer.keyDownAction?()
        now = now.addingTimeInterval(2)
        canStart = true
        registerer.keyDownAction?()
        registerer.keyUpAction?()

        XCTAssertEqual(startCount, 2)
        XCTAssertEqual(finishCount, 1)
    }

    func testHoldModeDoesNotLatchPressedWhenStartIsRejected() {
        let defaults = UserDefaults(suiteName: "HotkeyServiceTests.rejectedStart")!
        defaults.removePersistentDomain(forName: "HotkeyServiceTests.rejectedStart")
        var settings = SettingsStore(defaults: defaults)
        settings.triggerMode = .hold
        let registerer = SpyHotkeyEventRegistering()
        var canStart = false
        var startCount = 0
        var finishCount = 0

        let service = HotkeyService(
            settings: settings,
            registerer: registerer,
            canStart: { canStart },
            onToggle: {},
            onStart: { startCount += 1 },
            onFinish: { finishCount += 1 }
        )

        service.start()
        registerer.keyDownAction?()
        canStart = true
        registerer.keyDownAction?()
        registerer.keyUpAction?()

        XCTAssertEqual(startCount, 1)
        XCTAssertEqual(finishCount, 1)
    }

    func testSingleKeyRegistererUsesConfiguredFunctionKey() {
        let defaults = UserDefaults(suiteName: "HotkeyServiceTests.singleKey")!
        defaults.removePersistentDomain(forName: "HotkeyServiceTests.singleKey")
        var settings = SettingsStore(defaults: defaults)
        settings.holdKey = .f12
        let registerer = SingleKeyHotkeyRegisterer(settings: settings, promptForAccessibility: false)
        var keyDownCount = 0
        var keyUpCount = 0

        registerer.onKeyDown { keyDownCount += 1 }
        registerer.onKeyUp { keyUpCount += 1 }
        registerer.handleForTesting(keyCode: SpeechHotkey.f9.keyCode, isKeyDown: true)
        registerer.handleForTesting(keyCode: SpeechHotkey.f12.keyCode, isKeyDown: true)
        registerer.handleForTesting(keyCode: SpeechHotkey.f12.keyCode, isKeyDown: false)

        XCTAssertEqual(keyDownCount, 1)
        XCTAssertEqual(keyUpCount, 1)
    }

    func testSingleKeyRegistererUsesConfiguredCustomKeyCode() {
        let defaults = UserDefaults(suiteName: "HotkeyServiceTests.customSingleKey")!
        defaults.removePersistentDomain(forName: "HotkeyServiceTests.customSingleKey")
        var settings = SettingsStore(defaults: defaults)
        settings.holdKey = SpeechHotkey(keyCode: 0, displayName: "A")
        let registerer = SingleKeyHotkeyRegisterer(settings: settings, promptForAccessibility: false)
        var keyDownCount = 0
        var keyUpCount = 0

        registerer.onKeyDown { keyDownCount += 1 }
        registerer.onKeyUp { keyUpCount += 1 }
        registerer.handleForTesting(keyCode: SpeechHotkey.f9.keyCode, isKeyDown: true)
        registerer.handleForTesting(keyCode: 0, isKeyDown: true)
        registerer.handleForTesting(keyCode: 0, isKeyDown: false)

        XCTAssertEqual(keyDownCount, 1)
        XCTAssertEqual(keyUpCount, 1)
    }

    func testSingleKeyRegistererIgnoresHotkeyWhileRecorderIsCapturing() async {
        let defaults = UserDefaults(suiteName: "HotkeyServiceTests.recorderCapture")!
        defaults.removePersistentDomain(forName: "HotkeyServiceTests.recorderCapture")
        var settings = SettingsStore(defaults: defaults)
        settings.holdKey = .f2
        let registerer = SingleKeyHotkeyRegisterer(
            settings: settings,
            accessibilityInspector: RecordingAccessibilityInspector(),
            promptForAccessibility: false,
            eventTapHealthInterval: nil
        )
        var keyDownCount = 0
        var keyUpCount = 0

        registerer.onKeyDown { keyDownCount += 1 }
        registerer.onKeyUp { keyUpCount += 1 }
        NotificationCenter.default.post(
            name: .hotkeyRecorderCaptureDidChange,
            object: nil,
            userInfo: ["isCapturing": true]
        )
        try? await Task.sleep(nanoseconds: 50_000_000)

        registerer.handleForTesting(keyCode: SpeechHotkey.f2.keyCode, isKeyDown: true)
        registerer.handleForTesting(keyCode: SpeechHotkey.f2.keyCode, isKeyDown: false)

        XCTAssertEqual(keyDownCount, 0)
        XCTAssertEqual(keyUpCount, 0)

        NotificationCenter.default.post(
            name: .hotkeyRecorderCaptureDidChange,
            object: nil,
            userInfo: ["isCapturing": false]
        )
        try? await Task.sleep(nanoseconds: 50_000_000)

        registerer.handleForTesting(keyCode: SpeechHotkey.f2.keyCode, isKeyDown: true)
        registerer.handleForTesting(keyCode: SpeechHotkey.f2.keyCode, isKeyDown: false)

        XCTAssertEqual(keyDownCount, 1)
        XCTAssertEqual(keyUpCount, 1)
    }

    func testHoldModeIgnoresLateAutorepeatKeyDownAfterRelease() {
        let defaults = UserDefaults(suiteName: "HotkeyServiceTests.lateRepeat")!
        defaults.removePersistentDomain(forName: "HotkeyServiceTests.lateRepeat")
        var settings = SettingsStore(defaults: defaults)
        settings.holdKey = .f2
        let registerer = SingleKeyHotkeyRegisterer(settings: settings, promptForAccessibility: false)
        var startCount = 0
        var finishCount = 0

        let service = HotkeyService(
            settings: settings,
            registerer: registerer,
            onToggle: {},
            onStart: { startCount += 1 },
            onFinish: { finishCount += 1 }
        )

        service.start()
        registerer.handleForTesting(keyCode: SpeechHotkey.f2.keyCode, isKeyDown: true)
        registerer.handleForTesting(keyCode: SpeechHotkey.f2.keyCode, isKeyDown: false)
        registerer.handleForTesting(keyCode: SpeechHotkey.f2.keyCode, isKeyDown: true, isRepeat: true)
        registerer.handleForTesting(keyCode: SpeechHotkey.f2.keyCode, isKeyDown: true)
        registerer.handleForTesting(keyCode: SpeechHotkey.f2.keyCode, isKeyDown: false)

        XCTAssertEqual(startCount, 2)
        XCTAssertEqual(finishCount, 2)
    }

    func testSingleKeyRegistererDoesNotPromptForAccessibilityDuringAutomaticInstall() {
        let defaults = UserDefaults(suiteName: "HotkeyServiceTests.noAccessibilityPrompt")!
        defaults.removePersistentDomain(forName: "HotkeyServiceTests.noAccessibilityPrompt")
        let settings = SettingsStore(defaults: defaults)
        let accessibilityInspector = RecordingAccessibilityInspector()
        var eventTapCreateCount = 0
        let registerer = SingleKeyHotkeyRegisterer(
            settings: settings,
            accessibilityInspector: accessibilityInspector,
            eventTapFactory: { _, _, _, _, _, _ in
                eventTapCreateCount += 1
                return nil
            }
        )

        registerer.onKeyDown {}

        XCTAssertFalse(accessibilityInspector.prompts.contains(true))
        XCTAssertGreaterThanOrEqual(accessibilityInspector.prompts.count, 1)
        XCTAssertEqual(eventTapCreateCount, 0)
    }

    func testSingleKeyRegistererCreatesEventTapAfterAccessibilityIsTrusted() {
        let defaults = UserDefaults(suiteName: "HotkeyServiceTests.accessibilityTrusted")!
        defaults.removePersistentDomain(forName: "HotkeyServiceTests.accessibilityTrusted")
        let settings = SettingsStore(defaults: defaults)
        let accessibilityInspector = RecordingAccessibilityInspector(isTrusted: true)
        var eventTapCreateCount = 0
        let registerer = SingleKeyHotkeyRegisterer(
            settings: settings,
            accessibilityInspector: accessibilityInspector,
            eventTapFactory: { _, _, _, _, _, _ in
                eventTapCreateCount += 1
                return nil
            }
        )

        registerer.onKeyDown {}

        XCTAssertFalse(accessibilityInspector.prompts.contains(true))
        XCTAssertGreaterThanOrEqual(accessibilityInspector.prompts.count, 1)
        XCTAssertEqual(eventTapCreateCount, 1)
    }

    func testInstalledEventTapIsReenabledWhenAppBecomesActive() async {
        let defaults = UserDefaults(suiteName: "HotkeyServiceTests.reenableInstalledTap")!
        defaults.removePersistentDomain(forName: "HotkeyServiceTests.reenableInstalledTap")
        let settings = SettingsStore(defaults: defaults)
        let accessibilityInspector = RecordingAccessibilityInspector(isTrusted: true)
        var context = CFMachPortContext()
        let eventTap = CFMachPortCreate(nil, { _, _, _, _ in }, &context, nil)!
        var enableCalls: [Bool] = []
        let registerer = SingleKeyHotkeyRegisterer(
            settings: settings,
            accessibilityInspector: accessibilityInspector,
            eventTapFactory: { _, _, _, _, _, _ in eventTap },
            eventTapEnabler: { _, enabled in
                enableCalls.append(enabled)
            },
            eventTapHealthInterval: nil
        )

        registerer.onKeyDown {}
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertGreaterThanOrEqual(enableCalls.count, 2)
        XCTAssertTrue(enableCalls.allSatisfy { $0 })
    }

    func testInvalidEventTapIsRebuiltWhenAppBecomesActive() async {
        let defaults = UserDefaults(suiteName: "HotkeyServiceTests.rebuildInvalidTap")!
        defaults.removePersistentDomain(forName: "HotkeyServiceTests.rebuildInvalidTap")
        let settings = SettingsStore(defaults: defaults)
        let accessibilityInspector = RecordingAccessibilityInspector(isTrusted: true)
        var firstContext = CFMachPortContext()
        var secondContext = CFMachPortContext()
        let firstTap = CFMachPortCreate(nil, { _, _, _, _ in }, &firstContext, nil)!
        let secondTap = CFMachPortCreate(nil, { _, _, _, _ in }, &secondContext, nil)!
        var eventTapCreateCount = 0
        var enableCalls: [Bool] = []
        let registerer = SingleKeyHotkeyRegisterer(
            settings: settings,
            accessibilityInspector: accessibilityInspector,
            eventTapFactory: { _, _, _, _, _, _ in
                eventTapCreateCount += 1
                return eventTapCreateCount == 1 ? firstTap : secondTap
            },
            eventTapEnabler: { _, enabled in
                enableCalls.append(enabled)
            },
            eventTapHealthInterval: nil
        )

        registerer.onKeyDown {}
        CFMachPortInvalidate(firstTap)
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(eventTapCreateCount, 2)
        XCTAssertGreaterThanOrEqual(enableCalls.count, 2)
        XCTAssertTrue(enableCalls.allSatisfy { $0 })
    }

    func testHotkeyRecorderStateRecordsSingleKeyAndStopsRecording() {
        let initialHotkey = SpeechHotkey.f2
        let recordedHotkey = SpeechHotkey(keyCode: 0, displayName: "A")
        var changes: [SpeechHotkey] = []
        let recorder = HotkeyRecorderState(initialHotkey: initialHotkey) { hotkey in
            changes.append(hotkey)
        }

        recorder.beginRecording()
        recorder.record(hotkey: recordedHotkey)

        XCTAssertEqual(recorder.hotkey, recordedHotkey)
        XCTAssertFalse(recorder.isRecording)
        XCTAssertEqual(changes, [recordedHotkey])
    }
}

@MainActor
private final class SpyHotkeyEventRegistering: HotkeyEventRegistering {
    private(set) var keyDownAction: (() -> Void)?
    private(set) var keyUpAction: (() -> Void)?

    func onKeyDown(_ action: @escaping () -> Void) {
        keyDownAction = action
    }

    func onKeyUp(_ action: @escaping () -> Void) {
        keyUpAction = action
    }
}

private final class RecordingAccessibilityInspector: AccessibilityInspecting {
    private let isTrusted: Bool
    private(set) var prompts: [Bool] = []

    init(isTrusted: Bool = false) {
        self.isTrusted = isTrusted
    }

    func isProcessTrusted(prompt: Bool) -> Bool {
        prompts.append(prompt)
        return isTrusted
    }

    func focusedElement() -> AnyObject? {
        nil
    }

    func role(of element: AnyObject) -> String? {
        nil
    }

    func hasSelectedTextRange(_ element: AnyObject) -> Bool {
        false
    }
}
