import XCTest
@testable import Fusheng

@MainActor
final class HotkeyServiceTests: XCTestCase {
    func testToggleModeInvokesToggleOnlyOnKeyDown() {
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

        XCTAssertEqual(toggleCount, 1)
        XCTAssertEqual(startCount, 0)
        XCTAssertEqual(finishCount, 0)
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
