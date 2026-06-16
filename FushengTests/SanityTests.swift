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

    @MainActor
    func testShellCoordinatorStartsRecordingFromRestingStates() {
        let coordinators = [
            AppCoordinator(initialState: .idle),
            AppCoordinator(initialState: .completed(.pasted)),
            AppCoordinator(initialState: .failed(.missingAPIKey)),
        ]

        for coordinator in coordinators {
            coordinator.toggleRecordingForShell()

            guard case .recording = coordinator.state else {
                return XCTFail("Expected recording state, got \(coordinator.state)")
            }
        }
    }

    @MainActor
    func testShellCoordinatorDoesNotRestartRecordingFromActiveWorkflowStates() {
        let activeStates: [AppWorkflowState] = [
            .recognizing,
            .polishing,
            .delivering,
        ]

        for state in activeStates {
            let coordinator = AppCoordinator(initialState: state)

            coordinator.toggleRecordingForShell()

            XCTAssertEqual(coordinator.state, state)
        }
    }
}
