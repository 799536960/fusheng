import SwiftUI

struct RootMenuContent: View {
    @EnvironmentObject private var coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading) {
            Text("状态：\(coordinator.statusText)")

            Button("开始/停止录音") {
                coordinator.toggleRecordingForShell()
            }

            Divider()

            Button("打开设置") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }

            Button("退出") {
                NSApp.terminate(nil)
            }
        }
        .padding(.vertical, 6)
    }
}
