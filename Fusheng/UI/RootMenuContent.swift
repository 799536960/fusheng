import AppKit
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

            Button("打开草稿历史", action: openDraftHistoryWindow)

            Button("打开失败录音", action: openFailedRecordingWindow)

            Button("打开设置") {
                SettingsWindowController.shared.show()
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

    private func openDraftHistoryWindow() {
        NotificationCenter.default.post(name: .draftHistoryDidChange, object: nil)
        openWindow(id: "draft-history")
        bringWindowToFront(matching: { $0.title.contains("草稿历史") })
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NotificationCenter.default.post(name: .draftHistoryDidChange, object: nil)
            bringWindowToFront(matching: { $0.title.contains("草稿历史") })
        }
    }

    private func openFailedRecordingWindow() {
        NotificationCenter.default.post(name: .failedRecordingQueueDidChange, object: nil)
        openWindow(id: "failed-recordings")
        bringWindowToFront(matching: { $0.title.contains("失败录音") })
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NotificationCenter.default.post(name: .failedRecordingQueueDidChange, object: nil)
            bringWindowToFront(matching: { $0.title.contains("失败录音") })
        }
    }

    private func bringWindowToFront(matching predicate: (NSWindow) -> Bool) {
        NSApp.activate()

        NSApp.windows
            .filter(predicate)
            .forEach { window in
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
    }
}
