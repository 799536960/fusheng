import Foundation

@MainActor
final class AppCoordinator: ObservableObject {
    @Published private(set) var statusText = "空闲"

    var menuBarSystemImage: String {
        statusText == "录音中" ? "waveform.circle.fill" : "waveform.circle"
    }

    func toggleRecordingForShell() {
        statusText = statusText == "录音中" ? "空闲" : "录音中"
    }
}
