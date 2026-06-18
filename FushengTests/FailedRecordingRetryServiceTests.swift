import Foundation
import XCTest
@testable import Fusheng

@MainActor
final class FailedRecordingRetryServiceTests: XCTestCase {
    func testASRStageRetryRunsASRAndPolishCopiesSavesDraftAndDeletesFailure() async {
        let failedStore = MemoryFailedRecordingStore(snapshot: makeSnapshot(stage: .asr, rawASRText: ""))
        let audioStore = MemoryRetryAudioStore()
        let inserter = RetryFakeInserter()
        let drafts = RetryFakeDraftStore()
        let asr = CountingASR(text: "重新识别文本")
        let polisher = RetryFakePolisher(text: "重新整理文本")
        let service = makeService(
            failedStore: failedStore,
            audioStore: audioStore,
            asrClient: asr,
            polisher: polisher,
            inserter: inserter,
            drafts: drafts
        )

        await service.retry(id: failedStore.snapshot.id)

        XCTAssertEqual(audioStore.readPaths, [failedStore.snapshot.audioFilePath])
        XCTAssertEqual(asr.callCount, 1)
        XCTAssertEqual(polisher.rawTexts, ["重新识别文本"])
        XCTAssertEqual(inserter.copiedTexts, ["重新整理文本"])
        XCTAssertEqual(drafts.savedDrafts.map(\.polishedText), ["重新整理文本"])
        XCTAssertEqual(drafts.savedDrafts.map(\.rawASRText), ["重新识别文本"])
        XCTAssertEqual(failedStore.deletedIDs, [failedStore.snapshot.id])
    }

    func testPolishStageRetrySkipsASRAndAudioRead() async {
        let failedStore = MemoryFailedRecordingStore(snapshot: makeSnapshot(stage: .polish, rawASRText: "已有识别文本"))
        let audioStore = MemoryRetryAudioStore(fileExists: false)
        let inserter = RetryFakeInserter()
        let drafts = RetryFakeDraftStore()
        let asr = CountingASR(text: "不应该调用")
        let service = makeService(
            failedStore: failedStore,
            audioStore: audioStore,
            asrClient: asr,
            polisher: RetryFakePolisher(text: "重新整理文本"),
            inserter: inserter,
            drafts: drafts
        )

        await service.retry(id: failedStore.snapshot.id)

        XCTAssertEqual(asr.callCount, 0)
        XCTAssertEqual(audioStore.readPaths, [])
        XCTAssertEqual(inserter.copiedTexts, ["重新整理文本"])
        XCTAssertEqual(drafts.savedDrafts.map(\.rawASRText), ["已有识别文本"])
        XCTAssertEqual(failedStore.deletedIDs, [failedStore.snapshot.id])
    }

    func testRetryUsesStrategyForFailedSnapshotMode() async {
        let conciseStrategy = TextPolishStrategy.default(for: .concise).with {
            $0.isCustomEnabled = true
            $0.modeInstruction = "压缩成一句话，但保留否定词。"
            $0.extraInstructions = "不要改变对象。"
        }
        let settings = RetryFakeSettings(polishMode: .professional)
        settings.savePolishStrategy(conciseStrategy, for: .concise)
        let failedStore = MemoryFailedRecordingStore(snapshot: makeSnapshot(mode: .concise, stage: .polish, rawASRText: "已有识别文本"))
        let polisher = RetryFakePolisher(text: "重新整理文本")
        let service = makeService(
            failedStore: failedStore,
            audioStore: MemoryRetryAudioStore(),
            polisher: polisher,
            settings: settings
        )

        await service.retry(id: failedStore.snapshot.id)

        XCTAssertEqual(polisher.strategies, [conciseStrategy])
    }

    func testRetryFailureKeepsRecordAndUpdatesError() async {
        let failedStore = MemoryFailedRecordingStore(snapshot: makeSnapshot(stage: .polish, rawASRText: "已有识别文本"))
        let service = makeService(
            failedStore: failedStore,
            audioStore: MemoryRetryAudioStore(),
            polisher: RetryFakePolisher(error: RetryFakeError.polishFailed)
        )

        await service.retry(id: failedStore.snapshot.id)

        XCTAssertEqual(failedStore.deletedIDs, [])
        XCTAssertEqual(failedStore.retryStates.last?.state, .failed)
        XCTAssertNotNil(failedStore.retryStates.last?.errorSummary)
    }

    func testASRRetryMissingAudioKeepsRecordAndUpdatesError() async {
        let failedStore = MemoryFailedRecordingStore(snapshot: makeSnapshot(stage: .asr, rawASRText: ""))
        let audioStore = MemoryRetryAudioStore(fileExists: false)
        let asr = CountingASR(text: "不应该调用")
        let service = makeService(
            failedStore: failedStore,
            audioStore: audioStore,
            asrClient: asr
        )

        await service.retry(id: failedStore.snapshot.id)

        XCTAssertEqual(asr.callCount, 0)
        XCTAssertEqual(failedStore.deletedIDs, [])
        XCTAssertEqual(failedStore.retryStates.last?.state, .failed)
        XCTAssertEqual(failedStore.retryStates.last?.errorSummary, "音频文件缺失")
    }

    private func makeService(
        apiKeyProvider: APIKeyProviding = RetryAPIKeyProvider(apiKey: "key"),
        failedStore: MemoryFailedRecordingStore,
        audioStore: MemoryRetryAudioStore,
        asrClient: ASRRecognizing = CountingASR(text: "重新识别文本"),
        polisher: TextPolishing = RetryFakePolisher(text: "重新整理文本"),
        inserter: TextInserting = RetryFakeInserter(),
        drafts: DraftStoring? = nil,
        settings: SettingsProviding = RetryFakeSettings()
    ) -> FailedRecordingRetryService {
        let resolvedDrafts = drafts ?? RetryFakeDraftStore()

        return FailedRecordingRetryService(
            apiKeyProvider: apiKeyProvider,
            failedRecordingStore: failedStore,
            audioStore: audioStore,
            asrClient: asrClient,
            textPolisher: polisher,
            textInserter: inserter,
            draftStore: resolvedDrafts,
            settings: settings
        )
    }
}

private final class RetryFakeSettings: SettingsProviding {
    var triggerMode: TriggerMode
    var holdKey: SpeechHotkey
    var asrModel: String
    var polishModel: String
    var polishMode: TextPolishMode
    var autoPasteEnabled: Bool
    var restoreClipboardEnabled: Bool
    var keepDraftHistoryEnabled: Bool
    private var strategies: [TextPolishMode: TextPolishStrategy]

    init(
        triggerMode: TriggerMode = .toggle,
        holdKey: SpeechHotkey = .f9,
        asrModel: String = "asr-model",
        polishModel: String = "polish-model",
        polishMode: TextPolishMode = .clean,
        autoPasteEnabled: Bool = true,
        restoreClipboardEnabled: Bool = true,
        keepDraftHistoryEnabled: Bool = true
    ) {
        self.triggerMode = triggerMode
        self.holdKey = holdKey
        self.asrModel = asrModel
        self.polishModel = polishModel
        self.polishMode = polishMode
        self.autoPasteEnabled = autoPasteEnabled
        self.restoreClipboardEnabled = restoreClipboardEnabled
        self.keepDraftHistoryEnabled = keepDraftHistoryEnabled
        self.strategies = [:]
    }

    func polishStrategy(for mode: TextPolishMode) -> TextPolishStrategy {
        strategies[mode] ?? .default(for: mode)
    }

    func savePolishStrategy(_ strategy: TextPolishStrategy, for mode: TextPolishMode) {
        strategies[mode] = strategy.normalized(for: mode)
    }

    func resetPolishStrategy(for mode: TextPolishMode) {
        strategies.removeValue(forKey: mode)
    }

    func resetAllPolishStrategies() {
        strategies.removeAll()
    }
}

private struct RetryAPIKeyProvider: APIKeyProviding {
    let apiKey: String?

    func loadAPIKey() throws -> String? {
        apiKey
    }
}

@MainActor
private final class MemoryFailedRecordingStore: FailedRecordingStoring {
    var snapshot: FailedRecordingSnapshot
    private(set) var deletedIDs: [UUID] = []
    private(set) var retryStates: [(id: UUID, state: FailedRecordingRetryState, errorSummary: String?)] = []

    init(snapshot: FailedRecordingSnapshot) {
        self.snapshot = snapshot
    }

    func saveFailedRecording(
        id: UUID,
        createdAt: Date,
        sourceAppName: String,
        mode: TextPolishMode,
        asrModel: String,
        polishModel: String,
        failureStage: FailedRecordingStage,
        errorSummary: String,
        audioFilePath: String,
        rawASRText: String
    ) throws {}

    func recentFailedRecordings(limit: Int) throws -> [FailedRecordingSnapshot] {
        [snapshot]
    }

    func failedRecording(id: UUID) throws -> FailedRecordingSnapshot? {
        id == snapshot.id ? snapshot : nil
    }

    func updateRetryState(id: UUID, state: FailedRecordingRetryState, errorSummary: String?, lastRetryAt: Date?) throws {
        retryStates.append((id, state, errorSummary))
        snapshot = FailedRecordingSnapshot(
            id: snapshot.id,
            createdAt: snapshot.createdAt,
            sourceAppName: snapshot.sourceAppName,
            mode: snapshot.mode,
            asrModel: snapshot.asrModel,
            polishModel: snapshot.polishModel,
            failureStage: snapshot.failureStage,
            errorSummary: errorSummary ?? snapshot.errorSummary,
            audioFilePath: snapshot.audioFilePath,
            rawASRText: snapshot.rawASRText,
            retryState: state,
            lastRetryAt: lastRetryAt
        )
    }

    func deleteFailedRecording(id: UUID) throws {
        deletedIDs.append(id)
    }
}

private final class MemoryRetryAudioStore: FailedRecordingAudioStoring {
    private let exists: Bool
    private(set) var readPaths: [String] = []

    init(fileExists: Bool = true) {
        self.exists = fileExists
    }

    func makeWriter(id: UUID) throws -> FailedRecordingAudioWriting {
        RetryStubAudioWriter(filePath: "/tmp/\(id.uuidString).pcm")
    }

    func fileExists(at path: String) -> Bool {
        exists
    }

    func audioChunks(from path: String) throws -> AsyncThrowingStream<Data, Error> {
        readPaths.append(path)
        return AsyncThrowingStream { continuation in
            continuation.yield(Data([1, 2, 3]))
            continuation.finish()
        }
    }

    func deleteAudio(at path: String) {}
}

private final class RetryStubAudioWriter: FailedRecordingAudioWriting {
    let filePath: String

    init(filePath: String) {
        self.filePath = filePath
    }

    func append(_ data: Data) throws {}
    func close() throws {}
    func delete() {}
}

private final class CountingASR: ASRRecognizing {
    private(set) var callCount = 0
    let text: String

    init(text: String) {
        self.text = text
    }

    func recognize(
        audioChunks: AsyncThrowingStream<Data, Error>,
        model: String,
        apiKey: String,
        onPartialResult: @escaping @Sendable (String) async -> Void
    ) async throws -> RecognitionResult {
        callCount += 1
        for try await _ in audioChunks {}
        return RecognitionResult(rawText: text, partialText: text)
    }
}

private final class RetryFakePolisher: TextPolishing {
    let text: String
    let error: Error?
    private(set) var rawTexts: [String] = []
    private(set) var strategies: [TextPolishStrategy] = []

    init(text: String = "重新整理文本", error: Error? = nil) {
        self.text = text
        self.error = error
    }

    func polish(rawText: String, strategy: TextPolishStrategy, model: String, apiKey: String) async throws -> String {
        rawTexts.append(rawText)
        strategies.append(strategy)
        if let error {
            throw error
        }
        return text
    }
}

private extension TextPolishStrategy {
    func with(_ update: (inout TextPolishStrategy) -> Void) -> TextPolishStrategy {
        var copy = self
        update(&copy)
        return copy
    }
}

private final class RetryFakeInserter: TextInserting {
    private(set) var copiedTexts: [String] = []

    func paste(text: String, restoreClipboard: Bool) async throws {}

    func copyToClipboard(text: String) throws {
        copiedTexts.append(text)
    }

    @MainActor
    func makeComposition() -> TextComposing {
        RetryFakeTextComposition()
    }
}

private final class RetryFakeTextComposition: TextComposing {
    func update(text: String) async throws {}
    func commit(text: String, restoreClipboard: Bool) async throws {}
}

@MainActor
private final class RetryFakeDraftStore: DraftStoring {
    private(set) var savedDrafts: [RetrySavedDraft] = []

    func saveDraft(
        polishedText: String,
        rawASRText: String,
        sourceAppName: String,
        mode: TextPolishMode,
        deliveryStatus: DraftDeliveryStatus,
        errorSummary: String?
    ) throws {
        savedDrafts.append(
            RetrySavedDraft(
                polishedText: polishedText,
                rawASRText: rawASRText,
                sourceAppName: sourceAppName,
                mode: mode,
                deliveryStatus: deliveryStatus,
                errorSummary: errorSummary
            )
        )
    }

    func recentDrafts(limit: Int) throws -> [DraftSnapshot] {
        []
    }

    func deleteDraft(id: UUID) throws {}
}

private struct RetrySavedDraft: Equatable {
    let polishedText: String
    let rawASRText: String
    let sourceAppName: String
    let mode: TextPolishMode
    let deliveryStatus: DraftDeliveryStatus
    let errorSummary: String?
}

private enum RetryFakeError: Error {
    case polishFailed
}

private func makeSnapshot(
    mode: TextPolishMode = .clean,
    stage: FailedRecordingStage,
    rawASRText: String
) -> FailedRecordingSnapshot {
    FailedRecordingSnapshot(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        createdAt: Date(timeIntervalSince1970: 10),
        sourceAppName: "Notes",
        mode: mode,
        asrModel: "asr-model",
        polishModel: "polish-model",
        failureStage: stage,
        errorSummary: "失败",
        audioFilePath: "/tmp/audio.pcm",
        rawASRText: rawASRText,
        retryState: .idle,
        lastRetryAt: nil
    )
}
