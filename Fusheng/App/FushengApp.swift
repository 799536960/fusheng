import SwiftData
import SwiftUI

@main
struct FushengApp: App {
    @StateObject private var coordinator = AppCoordinator()
    private let draftModelContainer: ModelContainer = {
        do {
            return try ModelContainer(for: DraftRecord.self)
        } catch {
            fatalError("Failed to create draft model container: \(error)")
        }
    }()

    var body: some Scene {
        MenuBarExtra("浮声", systemImage: coordinator.menuBarSystemImage) {
            RootMenuContent()
                .environmentObject(coordinator)
                .modelContainer(draftModelContainer)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environmentObject(coordinator)
                .frame(width: 520, height: 520)
        }

        Window("草稿历史", id: "draft-history") {
            DraftHistoryView()
                .modelContainer(draftModelContainer)
                .frame(width: 720, height: 520)
        }

        Window("录音状态", id: "recording-overlay") {
            RecordingOverlayView()
                .environmentObject(coordinator)
                .frame(width: 280, height: 120)
        }
    }
}
