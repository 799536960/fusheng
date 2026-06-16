import Foundation
import XCTest
@testable import Fusheng

@MainActor
final class AppCoordinatorTests: XCTestCase {
    func testMissingAPIKeyFailsBeforeRecording() async {
        let recorder = FakeRecorder()
        let coordinator = makeCoordinator(
            apiKeyProvider: FakeAPIKeyProvider(apiKey: nil),
            recorder: recorder
        )

        await coordinator.startRecording()

        XCTAssertEqual(coordinator.state, .failed(.missingAPIKey))
        XCTAssertEqual(recorder.startCount, 0)
    }

    func testSuccessfulFlowPastesWhenInputAvailable() async {
        let inserter = FakeInserter()
        let drafts = FakeDraftStore()
        let coordinator = makeCoordinator(
            focusDetector: FakeFocus(.inputAvailable(appName: "Notes")),
            textInserter: inserter,
            draftStore: drafts
        )

        await coordinator.startRecording()
        await coordinator.finishRecording()

        XCTAssertEqual(inserter.pastedTexts, ["整理文本"])
        XCTAssertEqual(drafts.savedDrafts.count, 0)
        XCTAssertEqual(coordinator.latestPartialText, "原始文本")
        XCTAssertEqual(coordinator.state, .completed(.pasted))
    }

    func testNoInputSavesDraft() async {
        let drafts = FakeDraftStore()
        let coordinator = makeCoordinator(
            focusDetector: FakeFocus(.noInput(appName: "Preview")),
            draftStore: drafts
        )

        await coordinator.startRecording()
        await coordinator.finishRecording()

        XCTAssertEqual(drafts.savedDrafts.map(\.polishedText), ["整理文本"])
        XCTAssertEqual(drafts.savedDrafts.map(\.deliveryStatus), [.noInput(appName: "Preview")])
        XCTAssertEqual(coordinator.state, .completed(.savedDraft))
    }

    func testAutoPasteDisabledWithInputAvailableSavesDraft() async {
        let settings = FakeSettings(autoPasteEnabled: false)
        let drafts = FakeDraftStore()
        let inserter = FakeInserter()
        let coordinator = makeCoordinator(
            settings: settings,
            focusDetector: FakeFocus(.inputAvailable(appName: "Notes")),
            textInserter: inserter,
            draftStore: drafts
        )

        await coordinator.startRecording()
        await coordinator.finishRecording()

        XCTAssertEqual(inserter.pastedTexts, [])
        XCTAssertEqual(drafts.savedDrafts.map(\.deliveryStatus), [.autoPasteDisabled])
        XCTAssertEqual(drafts.savedDrafts.map(\.sourceAppName), ["Notes"])
        XCTAssertEqual(coordinator.state, .completed(.savedDraft))
    }

    func testAccessibilityPermissionMissingSavesDraft() async {
        let drafts = FakeDraftStore()
        let coordinator = makeCoordinator(
            focusDetector: FakeFocus(.accessibilityPermissionMissing(appName: "Notes")),
            draftStore: drafts
        )

        await coordinator.startRecording()
        await coordinator.finishRecording()

        XCTAssertEqual(drafts.savedDrafts.map(\.deliveryStatus), [.accessibilityPermissionMissing(appName: "Notes")])
        XCTAssertEqual(coordinator.state, .completed(.savedDraft))
    }

    func testPasteFailureSavesDraft() async {
        let drafts = FakeDraftStore()
        let coordinator = makeCoordinator(
            focusDetector: FakeFocus(.inputAvailable(appName: "Notes")),
            textInserter: FakeInserter(error: FakeError.pasteFailed),
            draftStore: drafts
        )

        await coordinator.startRecording()
        await coordinator.finishRecording()

        XCTAssertEqual(drafts.savedDrafts.map(\.deliveryStatus), [.pasteFailed])
        XCTAssertEqual(drafts.savedDrafts.map(\.polishedText), ["整理文本"])
        XCTAssertEqual(coordinator.state, .completed(.savedDraft))
    }

    func testMissingTextInserterSavesPasteFailedDraft() async {
        let drafts = FakeDraftStore()
        let coordinator = makeCoordinator(
            focusDetector: FakeFocus(.inputAvailable(appName: "Notes")),
            textInserter: nil,
            draftStore: drafts
        )

        await coordinator.startRecording()
        await coordinator.finishRecording()

        XCTAssertEqual(drafts.savedDrafts.map(\.deliveryStatus), [.pasteFailed])
        XCTAssertEqual(drafts.savedDrafts.map(\.polishedText), ["整理文本"])
        XCTAssertEqual(coordinator.state, .completed(.savedDraft))
    }

    func testPolishFailureSavesRawTextAsDraft() async {
        let drafts = FakeDraftStore()
        let coordinator = makeCoordinator(
            textPolisher: FakePolisher(error: FakeError.polishFailed),
            focusDetector: FakeFocus(.noInput(appName: "Preview")),
            draftStore: drafts
        )

        await coordinator.startRecording()
        await coordinator.finishRecording()

        XCTAssertEqual(drafts.savedDrafts.map(\.polishedText), ["原始文本"])
        XCTAssertEqual(drafts.savedDrafts.map(\.rawASRText), ["原始文本"])
        XCTAssertEqual(drafts.savedDrafts.map(\.deliveryStatus), [.savedDraft])
        XCTAssertEqual(drafts.savedDrafts.map(\.sourceAppName), ["Preview"])
        XCTAssertNotNil(drafts.savedDrafts.first?.errorSummary)
        XCTAssertEqual(coordinator.state, .completed(.savedDraft))
    }

    func testPolishFailureWithInputAvailableSavesRawTextWithoutPasting() async {
        let drafts = FakeDraftStore()
        let inserter = FakeInserter()
        let coordinator = makeCoordinator(
            textPolisher: FakePolisher(error: FakeError.polishFailed),
            focusDetector: FakeFocus(.inputAvailable(appName: "Notes")),
            textInserter: inserter,
            draftStore: drafts
        )

        await coordinator.startRecording()
        await coordinator.finishRecording()

        XCTAssertEqual(inserter.pastedTexts, [])
        XCTAssertEqual(drafts.savedDrafts.map(\.polishedText), ["原始文本"])
        XCTAssertEqual(drafts.savedDrafts.map(\.deliveryStatus), [.savedDraft])
        XCTAssertEqual(coordinator.state, .completed(.savedDraft))
    }

    func testDraftSaveFailureFailsWorkflow() async {
        let coordinator = makeCoordinator(
            focusDetector: FakeFocus(.noInput(appName: "Preview")),
            draftStore: FakeDraftStore(saveError: FakeError.draftSaveFailed)
        )

        await coordinator.startRecording()
        await coordinator.finishRecording()

        guard case .failed(.insertionFailed) = coordinator.state else {
            return XCTFail("Expected insertion failure, got \(coordinator.state)")
        }
    }

    func testDraftHistoryDisabledFailsWhenDraftIsRequired() async {
        let settings = FakeSettings(keepDraftHistoryEnabled: false)
        let drafts = FakeDraftStore()
        let coordinator = makeCoordinator(
            settings: settings,
            focusDetector: FakeFocus(.noInput(appName: "Preview")),
            draftStore: drafts
        )

        await coordinator.startRecording()
        await coordinator.finishRecording()

        XCTAssertEqual(drafts.savedDrafts.count, 0)
        guard case .failed(.insertionFailed) = coordinator.state else {
            return XCTFail("Expected insertion failure, got \(coordinator.state)")
        }
    }

    func testMissingDraftStoreFailsWhenDraftIsRequired() async {
        let coordinator = makeCoordinator(
            focusDetector: FakeFocus(.noInput(appName: "Preview")),
            installDefaultDraftStore: false
        )

        await coordinator.startRecording()
        await coordinator.finishRecording()

        guard case .failed(.insertionFailed) = coordinator.state else {
            return XCTFail("Expected insertion failure, got \(coordinator.state)")
        }
    }

    func testStartRecordingDoesNothingWhileWorkflowIsActive() async {
        let activeStates: [AppWorkflowState] = [
            .recording(startedAt: Date(timeIntervalSince1970: 0)),
            .recognizing,
            .polishing,
            .delivering,
        ]

        for activeState in activeStates {
            let recorder = FakeRecorder()
            let coordinator = makeCoordinator(recorder: recorder, initialState: activeState)

            await coordinator.startRecording()

            XCTAssertEqual(recorder.startCount, 0)
            XCTAssertEqual(coordinator.state, activeState)
        }
    }

    func testFinishRecordingDoesNothingWhileWorkflowIsAlreadyProcessing() async {
        let asr = DelayedASR()
        let coordinator = makeCoordinator(asrClient: asr)

        await coordinator.startRecording()
        let finishTask = Task {
            await coordinator.finishRecording()
        }

        await asr.waitUntilCalled()

        await coordinator.finishRecording()

        let callCount = await asr.currentCallCount()
        XCTAssertEqual(callCount, 1)
        XCTAssertEqual(coordinator.state, .recognizing)

        await asr.allowCompletion()
        await finishTask.value

        XCTAssertEqual(coordinator.state, .completed(.pasted))
    }

    private func makeCoordinator(
        settings: FakeSettings = FakeSettings(),
        apiKeyProvider: FakeAPIKeyProvider = FakeAPIKeyProvider(apiKey: "key"),
        recorder: FakeRecorder = FakeRecorder(),
        asrClient: ASRRecognizing = FakeASR(text: "原始文本"),
        textPolisher: FakePolisher = FakePolisher(text: "整理文本"),
        focusDetector: FakeFocus = FakeFocus(.inputAvailable(appName: "Notes")),
        textInserter: FakeInserter? = FakeInserter(),
        draftStore: DraftStoring? = nil,
        installDefaultDraftStore: Bool = true,
        sourceAppProvider: FakeSourceAppProvider = FakeSourceAppProvider(),
        initialState: AppWorkflowState = .idle
    ) -> AppCoordinator {
        let resolvedDraftStore = draftStore ?? (installDefaultDraftStore ? FakeDraftStore() : nil)

        return AppCoordinator(
            settings: settings,
            apiKeyProvider: apiKeyProvider,
            recorder: recorder,
            asrClient: asrClient,
            textPolisher: textPolisher,
            focusDetector: focusDetector,
            textInserter: textInserter,
            draftStore: resolvedDraftStore,
            sourceAppProvider: sourceAppProvider,
            initialState: initialState
        )
    }
}

private enum FakeError: Error {
    case pasteFailed
    case polishFailed
    case draftSaveFailed
}

private struct SavedDraft: Equatable {
    let polishedText: String
    let rawASRText: String
    let sourceAppName: String
    let mode: TextPolishMode
    let deliveryStatus: DraftDeliveryStatus
    let errorSummary: String?
}

private final class FakeSettings: SettingsProviding {
    var triggerMode: TriggerMode
    var asrModel: String
    var polishModel: String
    var polishMode: TextPolishMode
    var autoPasteEnabled: Bool
    var restoreClipboardEnabled: Bool
    var keepDraftHistoryEnabled: Bool

    init(
        triggerMode: TriggerMode = .toggle,
        asrModel: String = "asr-model",
        polishModel: String = "polish-model",
        polishMode: TextPolishMode = .clean,
        autoPasteEnabled: Bool = true,
        restoreClipboardEnabled: Bool = true,
        keepDraftHistoryEnabled: Bool = true
    ) {
        self.triggerMode = triggerMode
        self.asrModel = asrModel
        self.polishModel = polishModel
        self.polishMode = polishMode
        self.autoPasteEnabled = autoPasteEnabled
        self.restoreClipboardEnabled = restoreClipboardEnabled
        self.keepDraftHistoryEnabled = keepDraftHistoryEnabled
    }
}

private struct FakeAPIKeyProvider: APIKeyProviding {
    let apiKey: String?

    func loadAPIKey() throws -> String? {
        apiKey
    }
}

private final class FakeRecorder: AudioRecording {
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func startRecording() throws -> AsyncThrowingStream<Data, Error> {
        startCount += 1
        return AsyncThrowingStream { continuation in
            continuation.yield(Data([1, 2, 3]))
            continuation.finish()
        }
    }

    func stopRecording() {
        stopCount += 1
    }
}

private struct FakeASR: ASRRecognizing {
    let text: String

    func recognize(audioChunks: AsyncThrowingStream<Data, Error>, model: String, apiKey: String) async throws -> RecognitionResult {
        for try await _ in audioChunks {}
        return RecognitionResult(rawText: text, partialText: text)
    }
}

private actor DelayedASR: ASRRecognizing {
    private(set) var callCount = 0
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var completionContinuation: CheckedContinuation<Void, Never>?
    private var completionAllowed = false

    func currentCallCount() -> Int {
        callCount
    }

    func waitUntilCalled() async {
        guard callCount == 0 else { return }

        await withCheckedContinuation { continuation in
            startedContinuation = continuation
        }
    }

    func allowCompletion() {
        completionAllowed = true
        completionContinuation?.resume()
        completionContinuation = nil
    }

    func recognize(audioChunks: AsyncThrowingStream<Data, Error>, model: String, apiKey: String) async throws -> RecognitionResult {
        callCount += 1
        startedContinuation?.resume()
        startedContinuation = nil

        for try await _ in audioChunks {}

        if !completionAllowed {
            await withCheckedContinuation { continuation in
                completionContinuation = continuation
            }
        }

        return RecognitionResult(rawText: "原始文本", partialText: "原始文本")
    }
}

private struct FakePolisher: TextPolishing {
    let text: String
    let error: Error?

    init(text: String = "整理文本", error: Error? = nil) {
        self.text = text
        self.error = error
    }

    func polish(rawText: String, mode: TextPolishMode, model: String, apiKey: String) async throws -> String {
        if let error {
            throw error
        }
        return text
    }
}

private struct FakeFocus: FocusDetecting {
    let context: FocusInputContext

    init(_ context: FocusInputContext) {
        self.context = context
    }

    func focusedInputContext() -> FocusInputContext {
        context
    }
}

private final class FakeInserter: TextInserting {
    private(set) var pastedTexts: [String] = []
    let error: Error?

    init(error: Error? = nil) {
        self.error = error
    }

    func paste(text: String, restoreClipboard: Bool) async throws {
        if let error {
            throw error
        }
        pastedTexts.append(text)
    }
}

@MainActor
private final class FakeDraftStore: DraftStoring {
    private(set) var savedDrafts: [SavedDraft] = []
    let saveError: Error?

    init(saveError: Error? = nil) {
        self.saveError = saveError
    }

    func saveDraft(
        polishedText: String,
        rawASRText: String,
        sourceAppName: String,
        mode: TextPolishMode,
        deliveryStatus: DraftDeliveryStatus,
        errorSummary: String?
    ) throws {
        if let saveError {
            throw saveError
        }

        savedDrafts.append(
            SavedDraft(
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

private struct FakeSourceAppProvider: SourceAppProviding {
    func currentAppName() -> String {
        "SourceApp"
    }
}
