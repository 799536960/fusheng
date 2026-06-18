import Combine
import Foundation

@MainActor
final class FailedRecordingRetryService: ObservableObject {
    private let apiKeyProvider: APIKeyProviding
    private let failedRecordingStore: FailedRecordingStoring
    private let audioStore: FailedRecordingAudioStoring
    private let asrClient: ASRRecognizing
    private let textPolisher: TextPolishing
    private let textInserter: TextInserting
    private let draftStore: DraftStoring
    private let settings: SettingsProviding

    init(
        apiKeyProvider: APIKeyProviding,
        failedRecordingStore: FailedRecordingStoring,
        audioStore: FailedRecordingAudioStoring,
        asrClient: ASRRecognizing,
        textPolisher: TextPolishing,
        textInserter: TextInserting,
        draftStore: DraftStoring,
        settings: SettingsProviding = SettingsStore()
    ) {
        self.apiKeyProvider = apiKeyProvider
        self.failedRecordingStore = failedRecordingStore
        self.audioStore = audioStore
        self.asrClient = asrClient
        self.textPolisher = textPolisher
        self.textInserter = textInserter
        self.draftStore = draftStore
        self.settings = settings
    }

    func retry(id: UUID) async {
        do {
            guard let snapshot = try failedRecordingStore.failedRecording(id: id) else { return }
            guard let apiKey = try apiKeyProvider.loadAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines), !apiKey.isEmpty else {
                try failedRecordingStore.updateRetryState(
                    id: id,
                    state: .failed,
                    errorSummary: AppError.missingAPIKey.localizedDescription,
                    lastRetryAt: Date()
                )
                return
            }

            try failedRecordingStore.updateRetryState(
                id: id,
                state: .retrying,
                errorSummary: nil,
                lastRetryAt: Date()
            )

            let rawText = try await rawTextForRetry(snapshot: snapshot, apiKey: apiKey)
            let polishedText = try await textPolisher.polish(
                rawText: rawText,
                strategy: settings.polishStrategy(for: snapshot.mode),
                model: snapshot.polishModel,
                apiKey: apiKey
            )

            do {
                try textInserter.copyToClipboard(text: polishedText)
            } catch {
                let errorSummary = "文本已生成但复制失败：\(error.localizedDescription)"
                try draftStore.saveDraft(
                    polishedText: polishedText,
                    rawASRText: rawText,
                    sourceAppName: snapshot.sourceAppName,
                    mode: snapshot.mode,
                    deliveryStatus: .savedDraft,
                    errorSummary: errorSummary
                )
                try failedRecordingStore.updateRetryState(
                    id: id,
                    state: .failed,
                    errorSummary: errorSummary,
                    lastRetryAt: Date()
                )
                return
            }

            try draftStore.saveDraft(
                polishedText: polishedText,
                rawASRText: rawText,
                sourceAppName: snapshot.sourceAppName,
                mode: snapshot.mode,
                deliveryStatus: .savedDraft,
                errorSummary: nil
            )
            try failedRecordingStore.deleteFailedRecording(id: id)
        } catch {
            try? failedRecordingStore.updateRetryState(
                id: id,
                state: .failed,
                errorSummary: error.localizedDescription,
                lastRetryAt: Date()
            )
        }
    }

    private func rawTextForRetry(snapshot: FailedRecordingSnapshot, apiKey: String) async throws -> String {
        let rawText: String

        switch snapshot.failureStage {
        case .asr:
            guard audioStore.fileExists(at: snapshot.audioFilePath) else {
                throw FailedRecordingRetryError.message("音频文件缺失")
            }
            let recognition = try await asrClient.recognize(
                audioChunks: try audioStore.audioChunks(from: snapshot.audioFilePath),
                model: snapshot.asrModel,
                apiKey: apiKey
            )
            rawText = recognition.rawText
        case .polish:
            rawText = snapshot.rawASRText
        }

        let trimmedText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw AppError.asrFailed("未识别到语音内容，请确认麦克风权限和输入音量后重试")
        }
        return trimmedText
    }
}

private enum FailedRecordingRetryError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message):
            return message
        }
    }
}
