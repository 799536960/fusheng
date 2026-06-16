import XCTest
@testable import Fusheng

final class SanityTests: XCTestCase {
    @MainActor
    func testShellCoordinatorTogglesStatus() {
        let coordinator = AppCoordinator()

        XCTAssertEqual(coordinator.statusText, "空闲")
        coordinator.toggleRecordingForShell()
        XCTAssertEqual(coordinator.statusText, "录音中")
        coordinator.toggleRecordingForShell()
        XCTAssertEqual(coordinator.statusText, "空闲")
    }
}
