import SwiftData
import SwiftUI

struct RootMenuContent: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.openWindow) private var openWindow
    @Query(sort: \DraftRecord.createdAt, order: .reverse) private var drafts: [DraftRecord]

    var body: some View {
        VStack(alignment: .leading) {
            Text("状态：\(coordinator.statusText)")

            Button("开始/停止录音") {
                Task {
                    if case .recording = coordinator.state {
                        await coordinator.finishRecording()
                    } else {
                        await coordinator.startRecording()
                    }
                }
            }

            Divider()

            if drafts.isEmpty {
                Text("暂无草稿")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(drafts.prefix(5)), id: \.id) { draft in
                    Button(String(draft.polishedText.prefix(24))) {
                        copyToPasteboard(draft.polishedText)
                    }
                }
            }

            Divider()

            Button("打开草稿历史") {
                openWindow(id: "draft-history")
            }

            SettingsLink {
                Text("打开设置")
            }

            Button("退出") {
                NSApp.terminate(nil)
            }
        }
        .padding(.vertical, 6)
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
