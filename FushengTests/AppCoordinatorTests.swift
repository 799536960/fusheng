import AppKit
import Foundation
import XCTest
@testable import Fusheng

@MainActor
final class AppCoordinatorTests: XCTestCase {
    override func tearDown() async throws {
        await MainActor.run {
            NSApp.windows
                .filter { $0.title == "录音状态" }
                .forEach { $0.close() }
        }
        try await super.tearDown()
    }

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

    func testStartRecordingRequestsMicrophonePermissionWhenNotDetermined() async {
        let recorder = FakeRecorder()
        let microphonePermission = FakeMicrophonePermissionProvider(initialState: .notDetermined, requestResult: .authorized)
        let coordinator = makeCoordinator(
            recorder: recorder,
            microphonePermissionProvider: microphonePermission
        )

        await coordinator.startRecording()

        XCTAssertEqual(microphonePermission.requestCount, 1)
        XCTAssertEqual(recorder.startCount, 1)
        guard case .recording = coordinator.state else {
            return XCTFail("Expected recording, got \(coordinator.state)")
        }
    }

    func testStartRecordingFailsWhenMicrophonePermissionRequestIsDenied() async {
        let recorder = FakeRecorder()
        let microphonePermission = FakeMicrophonePermissionProvider(initialState: .notDetermined, requestResult: .denied)
        let coordinator = makeCoordinator(
            recorder: recorder,
            microphonePermissionProvider: microphonePermission
        )

        await coordinator.startRecording()

        XCTAssertEqual(microphonePermission.requestCount, 1)
        XCTAssertEqual(recorder.startCount, 0)
        XCTAssertEqual(coordinator.state, .failed(.microphonePermissionDenied))
    }

    func testStartRecordingFailsWhenMicrophonePermissionAlreadyDenied() async {
        let recorder = FakeRecorder()
        let microphonePermission = FakeMicrophonePermissionProvider(initialState: .denied)
        let coordinator = makeCoordinator(
            recorder: recorder,
            microphonePermissionProvider: microphonePermission
        )

        await coordinator.startRecording()

        XCTAssertEqual(microphonePermission.requestCount, 0)
        XCTAssertEqual(recorder.startCount, 0)
        XCTAssertEqual(coordinator.state, .failed(.microphonePermissionDenied))
    }

    func testStartRecordingPausesSystemAudioBeforeRecorderStarts() async {
        let systemAudio = FakeSystemAudioController(pauseResult: true)
        let recorder = FakeRecorder(onStart: {
            XCTAssertEqual(systemAudio.pauseCount, 1)
            XCTAssertEqual(systemAudio.resumeCount, 0)
        })
        let coordinator = makeCoordinator(
            recorder: recorder,
            systemAudioController: systemAudio
        )

        await coordinator.startRecording()

        XCTAssertEqual(systemAudio.pauseCount, 1)
        XCTAssertEqual(systemAudio.resumeCount, 0)
        XCTAssertEqual(recorder.startCount, 1)
    }

    func testFinishRecordingResumesOnlyWhenStartPausedSystemAudio() async {
        let systemAudio = FakeSystemAudioController(pauseResult: true)
        let coordinator = makeCoordinator(systemAudioController: systemAudio)

        await coordinator.startRecording()
        await coordinator.finishRecording()

        XCTAssertEqual(systemAudio.pauseCount, 1)
        XCTAssertEqual(systemAudio.resumeCount, 1)
    }

    func testFinishRecordingDoesNotResumeWhenStartDidNotPauseSystemAudio() async {
        let systemAudio = FakeSystemAudioController(pauseResult: false)
        let coordinator = makeCoordinator(systemAudioController: systemAudio)

        await coordinator.startRecording()
        await coordinator.finishRecording()

        XCTAssertEqual(systemAudio.pauseCount, 1)
        XCTAssertEqual(systemAudio.resumeCount, 0)
    }

    func testStartRecordingResumesSystemAudioWhenRecorderStartFailsAfterPause() async {
        let systemAudio = FakeSystemAudioController(pauseResult: true)
        let recorder = FakeRecorder(startError: FakeError.recorderFailed)
        let coordinator = makeCoordinator(
            recorder: recorder,
            systemAudioController: systemAudio
        )

        await coordinator.startRecording()

        XCTAssertEqual(systemAudio.pauseCount, 1)
        XCTAssertEqual(systemAudio.resumeCount, 1)
        XCTAssertEqual(recorder.startCount, 1)
        XCTAssertEqual(coordinator.state, .failed(.recorderFailed("recorderFailed")))
    }

    func testSystemAudioPauseSendsDefensivePauseWhenPlaybackStateIsUnavailable() async {
        let mediaRemote = FakeMediaRemotePlaybackController(playbackState: nil)
        let controller = SystemAudioController(mediaRemote: mediaRemote)

        let shouldResume = await controller.pauseForRecording()

        XCTAssertEqual(mediaRemote.sentCommands, [.pause])
        XCTAssertFalse(shouldResume)
    }

    func testSystemAudioPauseSendsPauseWhenPlaybackStateReportsPaused() async {
        let mediaRemote = FakeMediaRemotePlaybackController(playbackState: .paused)
        let controller = SystemAudioController(mediaRemote: mediaRemote)

        let shouldResume = await controller.pauseForRecording()

        XCTAssertEqual(mediaRemote.sentCommands, [.pause])
        XCTAssertFalse(shouldResume)
    }

    func testSystemAudioPauseUsesPlaybackRateWhenPlaybackStateReportsPaused() async {
        let mediaRemote = FakeMediaRemotePlaybackController(playbackState: .paused, playbackRate: 1)
        let controller = SystemAudioController(mediaRemote: mediaRemote)

        let shouldResume = await controller.pauseForRecording()

        XCTAssertEqual(mediaRemote.sentCommands, [.pause])
        XCTAssertTrue(shouldResume)
    }

    func testSystemAudioPauseUsesNowPlayingIsPlayingWhenPlaybackStateReportsPaused() async {
        let mediaRemote = FakeMediaRemotePlaybackController(playbackState: .paused, isPlaying: true)
        let controller = SystemAudioController(mediaRemote: mediaRemote)

        let shouldResume = await controller.pauseForRecording()

        XCTAssertEqual(mediaRemote.sentCommands, [.pause])
        XCTAssertTrue(shouldResume)
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

        XCTAssertEqual(inserter.composer.updatedTexts, ["原始文本"])
        XCTAssertEqual(inserter.composer.committedTexts, ["整理文本"])
        XCTAssertEqual(inserter.pastedTexts, [])
        XCTAssertEqual(drafts.savedDrafts.count, 0)
        XCTAssertEqual(coordinator.latestPartialText, "原始文本")
        XCTAssertEqual(coordinator.state, .completed(.pasted))
    }

    func testFinishRecordingUsesEffectiveCustomStrategyForCurrentPolishMode() async {
        let strategy = TextPolishStrategy.default(for: .concise).with {
            $0.isCustomEnabled = true
            $0.modeInstruction = "用最短句子保留关键动作。"
            $0.extraInstructions = "不要添加新信息。"
        }
        let settings = FakeSettings(polishMode: .concise)
        settings.savePolishStrategy(strategy, for: .concise)
        let polisher = FakePolisher()
        let coordinator = makeCoordinator(
            settings: settings,
            textPolisher: polisher,
            focusDetector: FakeFocus(.inputAvailable(appName: "Notes"))
        )

        await coordinator.startRecording()
        await coordinator.finishRecording()

        XCTAssertEqual(polisher.strategies, [strategy])
    }

    func testInputAvailableStreamsPartialTextThenCommitsPolishedText() async {
        let inserter = FakeInserter()
        let coordinator = makeCoordinator(
            asrClient: FakeASR(text: "原始文本", partials: ["我", "我要输入"]),
            focusDetector: FakeFocus(.inputAvailable(appName: "Notes")),
            textInserter: inserter
        )

        await coordinator.startRecording()
        await coordinator.finishRecording()

        XCTAssertEqual(inserter.composer.updatedTexts, ["我", "我要输入"])
        XCTAssertEqual(inserter.composer.committedTexts, ["整理文本"])
        XCTAssertEqual(coordinator.latestPartialText, "我要输入")
        XCTAssertEqual(coordinator.state, .completed(.pasted))
    }

    func testSuccessfulFlowCanRunTwiceFromCompletedState() async {
        let recorder = FakeRecorder()
        let asr = SequencedASR([
            .init(rawText: "第一句话", partials: ["第一句", "第一句话"]),
            .init(rawText: "第二句话", partials: ["第二句", "第二句话"])
        ])
        let polisher = SequencedPolisher(["第一句整理", "第二句整理"])
        let inserter = FreshCompositionInserter()
        let coordinator = makeCoordinator(
            recorder: recorder,
            asrClient: asr,
            textPolisher: polisher,
            focusDetector: FakeFocus(.inputAvailable(appName: "Notes")),
            textInserter: inserter
        )

        await coordinator.startRecording()
        await coordinator.finishRecording()
        await coordinator.startRecording()
        await coordinator.finishRecording()

        XCTAssertEqual(recorder.startCount, 2)
        XCTAssertEqual(recorder.stopCount, 2)
        XCTAssertEqual(asr.callCount, 2)
        XCTAssertEqual(polisher.rawTexts, ["第一句话", "第二句话"])
        XCTAssertEqual(inserter.compositions.map(\.updatedTexts), [["第一句", "第一句话"], ["第二句", "第二句话"]])
        XCTAssertEqual(inserter.compositions.map(\.committedTexts), [["第一句整理"], ["第二句整理"]])
        XCTAssertEqual(coordinator.latestPartialText, "第二句话")
        XCTAssertEqual(coordinator.state, .completed(.pasted))
    }

    func testRecordingOverlayHideDestroysWindowForNextRound() async {
        let coordinator = makeCoordinator()

        RecordingOverlayWindowController.shared.show(coordinator: coordinator)
        XCTAssertTrue(NSApp.windows.contains { $0.title == "录音状态" })

        RecordingOverlayWindowController.shared.hide()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertFalse(NSApp.windows.contains { $0.title == "录音状态" })
    }

    func testInputAvailableAlwaysCommitsToFocusedInputRegardlessOfClipboardSwitch() async {
        let settings = FakeSettings(autoPasteEnabled: false)
        let inserter = FakeInserter()
        let drafts = FakeDraftStore()
        let coordinator = makeCoordinator(
            settings: settings,
            focusDetector: FakeFocus(.inputAvailable(appName: "Notes")),
            textInserter: inserter,
            draftStore: drafts
        )

        await coordinator.startRecording()
        await coordinator.finishRecording()

        XCTAssertEqual(inserter.composer.updatedTexts, ["原始文本"])
        XCTAssertEqual(inserter.composer.committedTexts, ["整理文本"])
        XCTAssertEqual(inserter.copiedTexts, [])
        XCTAssertEqual(inserter.pastedTexts, [])
        XCTAssertEqual(drafts.savedDrafts.count, 0)
        XCTAssertEqual(coordinator.state, .completed(.pasted))
    }

    func testNoInputCopiesPolishedTextToClipboardWhenOutputSwitchEnabled() async {
        let settings = FakeSettings(autoPasteEnabled: true)
        let inserter = FakeInserter()
        let drafts = FakeDraftStore()
        let coordinator = makeCoordinator(
            settings: settings,
            focusDetector: FakeFocus(.noInput(appName: "Preview")),
            textInserter: inserter,
            draftStore: drafts
        )

        await coordinator.startRecording()
        await coordinator.finishRecording()

        XCTAssertEqual(inserter.copiedTexts, ["整理文本"])
        XCTAssertEqual(inserter.pastedTexts, [])
        XCTAssertEqual(drafts.savedDrafts.map(\.deliveryStatus), [.noInput(appName: "Preview")])
        XCTAssertEqual(coordinator.state, .completed(.savedDraft))
    }

    func testNoInputDoesNotCopyPolishedTextWhenOutputSwitchDisabled() async {
        let settings = FakeSettings(autoPasteEnabled: false)
        let inserter = FakeInserter()
        let drafts = FakeDraftStore()
        let coordinator = makeCoordinator(
            settings: settings,
            focusDetector: FakeFocus(.noInput(appName: "Preview")),
            textInserter: inserter,
            draftStore: drafts
        )

        await coordinator.startRecording()
        await coordinator.finishRecording()

        XCTAssertEqual(inserter.copiedTexts, [])
        XCTAssertEqual(inserter.pastedTexts, [])
        XCTAssertEqual(drafts.savedDrafts.map(\.deliveryStatus), [.noInput(appName: "Preview")])
        XCTAssertEqual(coordinator.state, .completed(.savedDraft))
    }

    func testNoInputFlowCanBeFollowedByInputAvailableFlow() async {
        let recorder = FakeRecorder()
        let asr = SequencedASR([
            .init(rawText: "无输入框语音", partials: ["无输入框语音"]),
            .init(rawText: "输入框语音", partials: ["输入框语音"])
        ])
        let polisher = SequencedPolisher(["无输入框整理", "输入框整理"])
        let inserter = FreshCompositionInserter()
        let drafts = FakeDraftStore()
        let focusDetector = SequencedFocus([
            .noInput(appName: "Preview"),
            .inputAvailable(appName: "Notes")
        ])
        let coordinator = makeCoordinator(
            recorder: recorder,
            asrClient: asr,
            textPolisher: polisher,
            focusDetector: focusDetector,
            textInserter: inserter,
            draftStore: drafts
        )

        await coordinator.startRecording()
        await coordinator.finishRecording()
        await coordinator.startRecording()
        await coordinator.finishRecording()

        XCTAssertEqual(recorder.startCount, 2)
        XCTAssertEqual(recorder.stopCount, 2)
        XCTAssertEqual(asr.callCount, 2)
        XCTAssertEqual(polisher.rawTexts, ["无输入框语音", "输入框语音"])
        XCTAssertEqual(inserter.copiedTexts, ["无输入框整理"])
        XCTAssertEqual(inserter.compositions.map(\.updatedTexts), [["输入框语音"]])
        XCTAssertEqual(inserter.compositions.map(\.committedTexts), [["输入框整理"]])
        XCTAssertEqual(drafts.savedDrafts.map(\.deliveryStatus), [.noInput(appName: "Preview")])
        XCTAssertEqual(coordinator.state, .completed(.pasted))
    }

    func testStartRecordingClearsPreviousPartialTextForNextRun() async {
        let asr = DelayedASR()
        let coordinator = makeCoordinator(asrClient: asr)

        await coordinator.startRecording()
        let finishTask = Task {
            await coordinator.finishRecording()
        }
        await asr.waitUntilCalled()
        await asr.allowCompletion()
        await finishTask.value

        XCTAssertEqual(coordinator.latestPartialText, "原始文本")

        await coordinator.startRecording()

        XCTAssertEqual(coordinator.latestPartialText, "")
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
        XCTAssertEqual(inserter.composer.updatedTexts, ["原始文本"])
        XCTAssertEqual(inserter.composer.committedTexts, ["原始文本"])
        XCTAssertEqual(drafts.savedDrafts.map(\.polishedText), ["原始文本"])
        XCTAssertEqual(drafts.savedDrafts.map(\.deliveryStatus), [.savedDraft])
        XCTAssertEqual(coordinator.state, .completed(.savedDraft))
    }

    func testEmptyRecognitionFailsWithoutPolishingOrSavingPlaceholderDraft() async {
        let drafts = FakeDraftStore()
        let inserter = FakeInserter()
        let polisher = FakePolisher(text: "请提供需要清理的语音转文字内容，我将为您处理。")
        let coordinator = makeCoordinator(
            asrClient: FakeASR(text: "  \n", partials: []),
            textPolisher: polisher,
            focusDetector: FakeFocus(.inputAvailable(appName: "Notes")),
            textInserter: inserter,
            draftStore: drafts
        )

        await coordinator.startRecording()
        await coordinator.finishRecording()

        XCTAssertEqual(polisher.rawTexts, [])
        XCTAssertEqual(drafts.savedDrafts.count, 0)
        XCTAssertEqual(inserter.composer.updatedTexts, [])
        XCTAssertEqual(inserter.composer.committedTexts, [])
        guard case .failed(.asrFailed(let message)) = coordinator.state else {
            return XCTFail("Expected ASR failure, got \(coordinator.state)")
        }
        XCTAssertTrue(message.contains("未识别到语音内容"))
    }

    func testASRFailureSavesFailedRecordingWithAudioPath() async {
        let failedStore = FakeFailedRecordingStore()
        let audioStore = FakeFailedRecordingAudioStore()
        let coordinator = makeCoordinator(
            asrClient: ThrowingASR(error: AppError.asrFailed("等待 task-finished 超时")),
            failedRecordingStore: failedStore,
            failedRecordingAudioStore: audioStore
        )

        await coordinator.startRecording()
        await coordinator.finishRecording()

        XCTAssertEqual(failedStore.saved.map(\.failureStage), [.asr])
        XCTAssertEqual(failedStore.saved.map(\.errorSummary), ["识别失败：等待 task-finished 超时"])
        XCTAssertEqual(failedStore.saved.first?.rawASRText, "")
        XCTAssertEqual(audioStore.writers.first?.deleted, false)
        guard case .failed(.asrFailed) = coordinator.state else {
            return XCTFail("Expected ASR failure, got \(coordinator.state)")
        }
    }

    func testASRFailureDoesNotBlockNextRecordingRound() async {
        let recorder = FakeRecorder()
        let asr = SequencedOutcomeASR([
            .failure(AppError.asrFailed("等待 task-finished 超时")),
            .success(.init(rawText: "第二次语音", partials: ["第二次语音"]))
        ])
        let inserter = FreshCompositionInserter()
        let coordinator = makeCoordinator(
            recorder: recorder,
            asrClient: asr,
            focusDetector: FakeFocus(.inputAvailable(appName: "Notes")),
            textInserter: inserter
        )

        await coordinator.startRecording()
        await coordinator.finishRecording()
        guard case .failed(.asrFailed) = coordinator.state else {
            return XCTFail("Expected ASR failure, got \(coordinator.state)")
        }

        await coordinator.startRecording()
        await coordinator.finishRecording()

        XCTAssertEqual(recorder.startCount, 2)
        XCTAssertEqual(recorder.stopCount, 2)
        XCTAssertEqual(asr.callCount, 2)
        XCTAssertEqual(inserter.compositions.map(\.updatedTexts).last, ["第二次语音"])
        XCTAssertEqual(inserter.compositions.map(\.committedTexts).last, ["整理文本"])
        XCTAssertEqual(coordinator.state, .completed(.pasted))
    }

    func testPolishFailureSavesFailedRecordingAndRawText() async {
        let failedStore = FakeFailedRecordingStore()
        let audioStore = FakeFailedRecordingAudioStore()
        let coordinator = makeCoordinator(
            textPolisher: FakePolisher(error: FakeError.polishFailed),
            focusDetector: FakeFocus(.noInput(appName: "Preview")),
            failedRecordingStore: failedStore,
            failedRecordingAudioStore: audioStore
        )

        await coordinator.startRecording()
        await coordinator.finishRecording()

        XCTAssertEqual(failedStore.saved.map(\.failureStage), [.polish])
        XCTAssertEqual(failedStore.saved.first?.rawASRText, "原始文本")
        XCTAssertEqual(failedStore.saved.first?.sourceAppName, "Preview")
        XCTAssertEqual(audioStore.writers.first?.deleted, false)
        XCTAssertEqual(coordinator.state, .completed(.savedDraft))
    }

    func testSuccessfulFlowDeletesFailedRecordingCandidateAudio() async {
        let audioStore = FakeFailedRecordingAudioStore()
        let coordinator = makeCoordinator(failedRecordingAudioStore: audioStore)

        await coordinator.startRecording()
        await coordinator.finishRecording()

        XCTAssertEqual(audioStore.writers.first?.deleted, true)
        XCTAssertEqual(coordinator.state, .completed(.pasted))
    }

    func testEmptyRecognitionDeletesAudioAndDoesNotSaveFailedRecording() async {
        let failedStore = FakeFailedRecordingStore()
        let audioStore = FakeFailedRecordingAudioStore()
        let coordinator = makeCoordinator(
            asrClient: FakeASR(text: "   "),
            failedRecordingStore: failedStore,
            failedRecordingAudioStore: audioStore
        )

        await coordinator.startRecording()
        await coordinator.finishRecording()

        XCTAssertEqual(failedStore.saved.count, 0)
        XCTAssertEqual(audioStore.writers.first?.deleted, true)
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
        textPolisher: TextPolishing = FakePolisher(text: "整理文本"),
        focusDetector: FocusDetecting = FakeFocus(.inputAvailable(appName: "Notes")),
        textInserter: TextInserting? = FakeInserter(),
        draftStore: DraftStoring? = nil,
        installDefaultDraftStore: Bool = true,
        failedRecordingStore: FailedRecordingStoring? = nil,
        failedRecordingAudioStore: FailedRecordingAudioStoring? = nil,
        sourceAppProvider: FakeSourceAppProvider = FakeSourceAppProvider(),
        microphonePermissionProvider: MicrophonePermissionProviding = FakeMicrophonePermissionProvider(initialState: .authorized),
        systemAudioController: SystemAudioControlling? = nil,
        initialState: AppWorkflowState = .idle
    ) -> AppCoordinator {
        let resolvedDraftStore = draftStore ?? (installDefaultDraftStore ? FakeDraftStore() : nil)
        let resolvedSystemAudioController = systemAudioController ?? FakeSystemAudioController()

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
            failedRecordingStore: failedRecordingStore,
            failedRecordingAudioStore: failedRecordingAudioStore,
            microphonePermissionProvider: microphonePermissionProvider,
            systemAudioController: resolvedSystemAudioController,
            initialState: initialState
        )
    }
}

private enum FakeError: Error {
    case pasteFailed
    case polishFailed
    case draftSaveFailed
    case recorderFailed
}

extension FakeError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .pasteFailed:
            return "pasteFailed"
        case .polishFailed:
            return "polishFailed"
        case .draftSaveFailed:
            return "draftSaveFailed"
        case .recorderFailed:
            return "recorderFailed"
        }
    }
}

private struct SavedDraft: Equatable {
    let polishedText: String
    let rawASRText: String
    let sourceAppName: String
    let mode: TextPolishMode
    let deliveryStatus: DraftDeliveryStatus
    let errorSummary: String?
}

private struct SavedFailedRecording: Equatable {
    let id: UUID
    let sourceAppName: String
    let mode: TextPolishMode
    let asrModel: String
    let polishModel: String
    let failureStage: FailedRecordingStage
    let errorSummary: String
    let audioFilePath: String
    let rawASRText: String
}

@MainActor
private final class FakeFailedRecordingStore: FailedRecordingStoring {
    private(set) var saved: [SavedFailedRecording] = []

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
    ) throws {
        saved.append(SavedFailedRecording(
            id: id,
            sourceAppName: sourceAppName,
            mode: mode,
            asrModel: asrModel,
            polishModel: polishModel,
            failureStage: failureStage,
            errorSummary: errorSummary,
            audioFilePath: audioFilePath,
            rawASRText: rawASRText
        ))
    }

    func recentFailedRecordings(limit: Int) throws -> [FailedRecordingSnapshot] { [] }
    func failedRecording(id: UUID) throws -> FailedRecordingSnapshot? { nil }
    func updateRetryState(id: UUID, state: FailedRecordingRetryState, errorSummary: String?, lastRetryAt: Date?) throws {}
    func deleteFailedRecording(id: UUID) throws {}
}

private final class FakeFailedRecordingAudioStore: FailedRecordingAudioStoring {
    private(set) var writers: [FakeFailedRecordingAudioWriter] = []

    func makeWriter(id: UUID) throws -> FailedRecordingAudioWriting {
        let writer = FakeFailedRecordingAudioWriter(filePath: "/tmp/\(id.uuidString).pcm")
        writers.append(writer)
        return writer
    }

    func fileExists(at path: String) -> Bool {
        true
    }

    func audioChunks(from path: String) throws -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(Data([1, 2, 3]))
            continuation.finish()
        }
    }

    func deleteAudio(at path: String) {}
}

private final class FakeFailedRecordingAudioWriter: FailedRecordingAudioWriting {
    let filePath: String
    private(set) var deleted = false

    init(filePath: String) {
        self.filePath = filePath
    }

    func append(_ data: Data) throws {}
    func close() throws {}
    func delete() { deleted = true }
}

private final class FakeSettings: SettingsProviding {
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

private struct FakeAPIKeyProvider: APIKeyProviding {
    let apiKey: String?

    func loadAPIKey() throws -> String? {
        apiKey
    }
}

private final class FakeMicrophonePermissionProvider: MicrophonePermissionProviding {
    private(set) var state: MicrophonePermissionState
    private let requestResult: MicrophonePermissionState
    private(set) var requestCount = 0

    init(initialState: MicrophonePermissionState, requestResult: MicrophonePermissionState = .authorized) {
        self.state = initialState
        self.requestResult = requestResult
    }

    var currentMicrophonePermission: MicrophonePermissionState {
        state
    }

    func requestMicrophonePermission() async -> MicrophonePermissionState {
        requestCount += 1
        state = requestResult
        return state
    }
}

private final class FakeRecorder: AudioRecording {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private let startError: Error?
    private let onStart: (() -> Void)?

    init(startError: Error? = nil, onStart: (() -> Void)? = nil) {
        self.startError = startError
        self.onStart = onStart
    }

    func startRecording() throws -> AsyncThrowingStream<Data, Error> {
        startCount += 1
        onStart?()
        if let startError {
            throw startError
        }
        return AsyncThrowingStream { continuation in
            continuation.yield(Data([1, 2, 3]))
            continuation.finish()
        }
    }

    func stopRecording() {
        stopCount += 1
    }
}

private final class FakeSystemAudioController: SystemAudioControlling {
    private(set) var pauseCount = 0
    private(set) var resumeCount = 0
    private let pauseResult: Bool

    init(pauseResult: Bool = false) {
        self.pauseResult = pauseResult
    }

    func pauseForRecording() async -> Bool {
        pauseCount += 1
        return pauseResult
    }

    func resumeAfterRecording() async {
        resumeCount += 1
    }
}

private final class FakeMediaRemotePlaybackController: MediaRemotePlaybackControlling {
    private(set) var sentCommands: [MediaRemoteCommand] = []
    private let playbackState: MediaRemotePlaybackState?
    private let isPlaying: Bool?
    private let playbackRate: Double?

    init(playbackState: MediaRemotePlaybackState?, isPlaying: Bool? = nil, playbackRate: Double? = nil) {
        self.playbackState = playbackState
        self.isPlaying = isPlaying
        self.playbackRate = playbackRate
    }

    func currentPlaybackState() async -> MediaRemotePlaybackState? {
        playbackState
    }

    func currentNowPlayingApplicationIsPlaying() async -> Bool? {
        isPlaying
    }

    func currentPlaybackRate() async -> Double? {
        playbackRate
    }

    func send(command: MediaRemoteCommand) -> Bool {
        sentCommands.append(command)
        return true
    }
}

private struct FakeASR: ASRRecognizing {
    let text: String
    let partials: [String]

    init(text: String, partials: [String]? = nil) {
        self.text = text
        self.partials = partials ?? [text]
    }

    func recognize(
        audioChunks: AsyncThrowingStream<Data, Error>,
        model: String,
        apiKey: String,
        onPartialResult: @escaping @Sendable (String) async -> Void
    ) async throws -> RecognitionResult {
        for try await _ in audioChunks {}
        for partial in partials {
            await onPartialResult(partial)
        }
        return RecognitionResult(rawText: text, partialText: text)
    }
}

private struct ThrowingASR: ASRRecognizing {
    let error: Error

    func recognize(
        audioChunks: AsyncThrowingStream<Data, Error>,
        model: String,
        apiKey: String,
        onPartialResult: @escaping @Sendable (String) async -> Void
    ) async throws -> RecognitionResult {
        for try await _ in audioChunks {}
        throw error
    }
}

private final class SequencedASR: ASRRecognizing {
    struct Response {
        let rawText: String
        let partials: [String]
    }

    private var responses: [Response]
    private(set) var callCount = 0

    init(_ responses: [Response]) {
        self.responses = responses
    }

    func recognize(
        audioChunks: AsyncThrowingStream<Data, Error>,
        model: String,
        apiKey: String,
        onPartialResult: @escaping @Sendable (String) async -> Void
    ) async throws -> RecognitionResult {
        callCount += 1
        for try await _ in audioChunks {}
        let response = responses.removeFirst()
        for partial in response.partials {
            await onPartialResult(partial)
        }
        return RecognitionResult(rawText: response.rawText, partialText: response.partials.last ?? response.rawText)
    }
}

private final class SequencedOutcomeASR: ASRRecognizing {
    enum Outcome {
        case success(SequencedASR.Response)
        case failure(Error)
    }

    private var outcomes: [Outcome]
    private(set) var callCount = 0

    init(_ outcomes: [Outcome]) {
        self.outcomes = outcomes
    }

    func recognize(
        audioChunks: AsyncThrowingStream<Data, Error>,
        model: String,
        apiKey: String,
        onPartialResult: @escaping @Sendable (String) async -> Void
    ) async throws -> RecognitionResult {
        callCount += 1
        for try await _ in audioChunks {}
        switch outcomes.removeFirst() {
        case .success(let response):
            for partial in response.partials {
                await onPartialResult(partial)
            }
            return RecognitionResult(rawText: response.rawText, partialText: response.partials.last ?? response.rawText)
        case .failure(let error):
            throw error
        }
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

    func recognize(
        audioChunks: AsyncThrowingStream<Data, Error>,
        model: String,
        apiKey: String,
        onPartialResult: @escaping @Sendable (String) async -> Void
    ) async throws -> RecognitionResult {
        callCount += 1
        startedContinuation?.resume()
        startedContinuation = nil

        for try await _ in audioChunks {}
        await onPartialResult("原始文本")

        if !completionAllowed {
            await withCheckedContinuation { continuation in
                completionContinuation = continuation
            }
        }

        return RecognitionResult(rawText: "原始文本", partialText: "原始文本")
    }
}

private final class FakePolisher: TextPolishing {
    let text: String
    let error: Error?
    private(set) var rawTexts: [String] = []
    private(set) var strategies: [TextPolishStrategy] = []

    init(text: String = "整理文本", error: Error? = nil) {
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

private final class SequencedPolisher: TextPolishing {
    private var texts: [String]
    private(set) var rawTexts: [String] = []
    private(set) var strategies: [TextPolishStrategy] = []

    init(_ texts: [String]) {
        self.texts = texts
    }

    func polish(rawText: String, strategy: TextPolishStrategy, model: String, apiKey: String) async throws -> String {
        rawTexts.append(rawText)
        strategies.append(strategy)
        return texts.removeFirst()
    }
}

private extension TextPolishStrategy {
    func with(_ update: (inout TextPolishStrategy) -> Void) -> TextPolishStrategy {
        var copy = self
        update(&copy)
        return copy
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

private final class SequencedFocus: FocusDetecting {
    private var contexts: [FocusInputContext]
    private var lastContext: FocusInputContext

    init(_ contexts: [FocusInputContext]) {
        self.contexts = contexts
        self.lastContext = contexts.last ?? .noInput(appName: "SourceApp")
    }

    func focusedInputContext() -> FocusInputContext {
        guard !contexts.isEmpty else { return lastContext }
        lastContext = contexts.removeFirst()
        return lastContext
    }
}

private final class FakeInserter: TextInserting {
    private(set) var pastedTexts: [String] = []
    private(set) var copiedTexts: [String] = []
    @MainActor private(set) lazy var composer = FakeTextComposition(commitError: error)
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

    func copyToClipboard(text: String) throws {
        copiedTexts.append(text)
    }

    @MainActor func makeComposition() -> TextComposing {
        composer
    }
}

@MainActor
private final class FreshCompositionInserter: TextInserting {
    private(set) var pastedTexts: [String] = []
    private(set) var copiedTexts: [String] = []
    private(set) var compositions: [FakeTextComposition] = []

    func paste(text: String, restoreClipboard: Bool) async throws {
        pastedTexts.append(text)
    }

    func copyToClipboard(text: String) throws {
        copiedTexts.append(text)
    }

    func makeComposition() -> TextComposing {
        let composition = FakeTextComposition()
        compositions.append(composition)
        return composition
    }
}

private final class FakeTextComposition: TextComposing {
    private(set) var updatedTexts: [String] = []
    private(set) var committedTexts: [String] = []
    let commitError: Error?

    init(commitError: Error? = nil) {
        self.commitError = commitError
    }

    func update(text: String) async throws {
        updatedTexts.append(text)
    }

    func commit(text: String, restoreClipboard: Bool) async throws {
        if let commitError {
            throw commitError
        }
        committedTexts.append(text)
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
