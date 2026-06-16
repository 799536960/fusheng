import Foundation

@MainActor
final class AppCoordinator: ObservableObject {
    @Published private(set) var state: AppWorkflowState = .idle

    init(initialState: AppWorkflowState = .idle) {
        state = initialState
    }

    var statusText: String { state.displayText }
    var menuBarSystemImage: String { state.menuBarSystemImage }

    func toggleRecordingForShell() {
        switch state {
        case .recording:
            state = .idle
        case .idle, .completed, .failed:
            state = .recording(startedAt: Date())
        case .recognizing, .polishing, .delivering:
            break
        }
    }
}
