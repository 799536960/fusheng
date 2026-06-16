import SwiftUI

@main
struct FushengApp: App {
    @StateObject private var coordinator = AppCoordinator()

    var body: some Scene {
        MenuBarExtra("浮声", systemImage: coordinator.menuBarSystemImage) {
            RootMenuContent()
                .environmentObject(coordinator)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            Text("设置将在后续任务接入。")
                .frame(width: 360, height: 160)
        }
    }
}
