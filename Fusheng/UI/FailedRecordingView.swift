import SwiftUI

struct FailedRecordingView: View {
    @State private var records: [FailedRecordingSnapshot] = []
    @State private var errorMessage: String?

    let store: FailedRecordingStoring
    let audioStore: FailedRecordingAudioStoring
    let retryService: FailedRecordingRetryService

    var body: some View {
        VStack {
            if records.isEmpty {
                ContentUnavailableView("暂无失败录音", systemImage: "waveform.badge.exclamationmark")
            } else {
                List {
                    ForEach(records) { record in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 10) {
                                Text(record.failureStage.displayText)
                                    .font(.headline)

                                Text(record.retryState.displayText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Text(record.errorSummary)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 8) {
                                Text(record.createdAt.formatted())
                                Text(record.sourceAppName)
                                Text(record.mode.displayName)
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)

                            if !record.rawASRText.isEmpty {
                                Text(record.rawASRText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }

                            if record.failureStage == .asr, !audioStore.fileExists(at: record.audioFilePath) {
                                Text("音频文件缺失")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }

                            HStack {
                                Button("重新请求") {
                                    Task {
                                        await retryService.retry(id: record.id)
                                        reload()
                                    }
                                }
                                .disabled(isRetryDisabled(record))

                                Button("删除", role: .destructive) {
                                    delete(record)
                                }
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }
        .padding()
        .alert("失败录音操作失败", isPresented: errorBinding) {
            Button("好", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: .failedRecordingQueueDidChange)) { _ in
            reload()
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    errorMessage = nil
                }
            }
        )
    }

    private func isRetryDisabled(_ record: FailedRecordingSnapshot) -> Bool {
        record.retryState == .retrying
            || (record.failureStage == .asr && !audioStore.fileExists(at: record.audioFilePath))
    }

    private func reload() {
        do {
            records = try store.recentFailedRecordings(limit: 100)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ record: FailedRecordingSnapshot) {
        do {
            try store.deleteFailedRecording(id: record.id)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
