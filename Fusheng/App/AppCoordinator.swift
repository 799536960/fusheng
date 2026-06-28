import AppKit
import Combine
import Foundation
import OSLog

private let coordinatorLogger = Logger(subsystem: "com.fusheng.voiceinput", category: "Coordinator")

@MainActor
final class AppCoordinator: ObservableObject {
    @Published private(set) var state: AppWorkflowState {
        didSet {
            updateRecordingOverlayVisibility()
        }
    }
    @Published private(set) var latestPartialText = ""

    private let settings: SettingsProviding
    private let apiKeyProvider: APIKeyProviding
    private let recorder: AudioRecording?
    private let asrClient: ASRRecognizing?
    private let textPolisher: TextPolishing?
    private let focusDetector: FocusDetecting?
    private let textInserter: TextInserting?
    private let draftStore: DraftStoring?
    private let sourceAppProvider: SourceAppProviding?
    private let failedRecordingStore: FailedRecordingStoring?
    private let failedRecordingAudioStore: FailedRecordingAudioStoring?
    private let microphonePermissionProvider: MicrophonePermissionProviding
    private let systemAudioController: SystemAudioControlling

    private var activeAudioStream: AsyncThrowingStream<Data, Error>?
    private var activeAPIKey: String?
    private var activeRecognitionTask: Task<RecognitionResult, Error>?
    private var activeFocusContext: FocusInputContext?
    private var activeTextComposition: TextComposing?
    private var activeInputApplication: NSRunningApplication?
    private var activeFailedRecordingID: UUID?
    private var activeFailedRecordingAudioWriter: FailedRecordingAudioWriting?
    private var shouldResumeSystemAudioAfterRecording = false

    init(initialState: AppWorkflowState = .idle) {
        self.state = initialState
        self.settings = SettingsStore()
        self.apiKeyProvider = KeychainService()
        self.recorder = nil
        self.asrClient = nil
        self.textPolisher = nil
        self.focusDetector = nil
        self.textInserter = nil
        self.draftStore = nil
        self.sourceAppProvider = nil
        self.failedRecordingStore = nil
        self.failedRecordingAudioStore = nil
        self.microphonePermissionProvider = SystemMicrophonePermissionProvider()
        self.systemAudioController = SystemAudioController()
    }

    init(
        settings: SettingsProviding,
        apiKeyProvider: APIKeyProviding,
        recorder: AudioRecording?,
        asrClient: ASRRecognizing?,
        textPolisher: TextPolishing?,
        focusDetector: FocusDetecting?,
        textInserter: TextInserting?,
        draftStore: DraftStoring?,
        sourceAppProvider: SourceAppProviding?,
        failedRecordingStore: FailedRecordingStoring? = nil,
        failedRecordingAudioStore: FailedRecordingAudioStoring? = nil,
        microphonePermissionProvider: MicrophonePermissionProviding = SystemMicrophonePermissionProvider(),
        systemAudioController: SystemAudioControlling? = nil,
        initialState: AppWorkflowState = .idle
    ) {
        self.state = initialState
        self.settings = settings
        self.apiKeyProvider = apiKeyProvider
        self.recorder = recorder
        self.asrClient = asrClient
        self.textPolisher = textPolisher
        self.focusDetector = focusDetector
        self.textInserter = textInserter
        self.draftStore = draftStore
        self.sourceAppProvider = sourceAppProvider
        self.failedRecordingStore = failedRecordingStore
        self.failedRecordingAudioStore = failedRecordingAudioStore
        self.microphonePermissionProvider = microphonePermissionProvider
        self.systemAudioController = systemAudioController ?? SystemAudioController()
    }

    var statusText: String { state.displayText }
    var menuBarSystemImage: String { state.menuBarSystemImage }
    var canStartRecordingFromHotkey: Bool { state.canStartRecording }

    private func updateRecordingOverlayVisibility() {
        if state.showsRecordingOverlay {
            RecordingOverlayWindowController.shared.show(coordinator: self)
        } else {
            RecordingOverlayWindowController.shared.hide()
        }
    }

    func toggleRecordingForShell() {
        switch state {
        case .recording:
            state = .idle
            activeAudioStream = nil
            activeAPIKey = nil
            activeRecognitionTask?.cancel()
            clearActiveInputSession()
        case .idle, .completed, .failed:
            state = .recording(startedAt: Date())
        case .recognizing, .polishing, .delivering:
            break
        }
    }

    func startRecording() async {
        coordinatorLogger.info("startRecording requested; state=\(self.state.displayText, privacy: .public)")
        DiagnosticLog.write(category: "Coordinator", message: "startRecording requested state=\(state.displayText)")
        guard state.canStartRecording else {
            coordinatorLogger.info("startRecording ignored; state=\(self.state.displayText, privacy: .public)")
            DiagnosticLog.write(category: "Coordinator", message: "startRecording ignored state=\(state.displayText)")
            return
        }

        do {
            coordinatorLogger.info("startRecording accepted")
            DiagnosticLog.write(category: "Coordinator", message: "startRecording accepted")
            latestPartialText = ""

            guard let apiKey = try apiKeyProvider.loadAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !apiKey.isEmpty else {
                coordinatorLogger.error("startRecording blocked: missing API key")
                DiagnosticLog.write(category: "Coordinator", message: "startRecording blocked missing API key")
                state = .failed(.missingAPIKey)
                return
            }

            guard let recorder else {
                coordinatorLogger.error("startRecording blocked: recorder service missing")
                DiagnosticLog.write(category: "Coordinator", message: "startRecording blocked recorder service missing")
                state = .failed(.recorderFailed("录音服务未初始化"))
                return
            }

            guard let asrClient, textPolisher != nil else {
                coordinatorLogger.error("startRecording blocked: recognition service missing")
                DiagnosticLog.write(category: "Coordinator", message: "startRecording blocked recognition service missing")
                state = .failed(.asrFailed("识别服务未初始化"))
                return
            }

            let microphonePermission = await ensureMicrophonePermission()
            coordinatorLogger.info("startRecording microphone permission=\(microphonePermission.logName, privacy: .public)")
            DiagnosticLog.write(category: "Coordinator", message: "startRecording microphone permission=\(microphonePermission.logName)")
            guard microphonePermission == .authorized else {
                state = .failed(.microphonePermissionDenied)
                return
            }

            let focusContext = focusDetector?.focusedInputContext() ?? .noInput(appName: fallbackAppName)
            activeFocusContext = focusContext
            coordinatorLogger.info("startRecording focusContext=\(focusContext.logName, privacy: .public)")
            DiagnosticLog.write(category: "Coordinator", message: "startRecording focusContext=\(focusContext.logName)")
            prepareLiveComposition(for: focusContext)

            let failedRecordingID = UUID()
            let writer = try failedRecordingAudioStore?.makeWriter(id: failedRecordingID)
            activeFailedRecordingID = writer == nil ? nil : failedRecordingID
            activeFailedRecordingAudioWriter = writer

            shouldResumeSystemAudioAfterRecording = await systemAudioController.pauseForRecording()
            activeAudioStream = try recorder.startRecording()
            coordinatorLogger.info("audio recorder started")
            DiagnosticLog.write(category: "Coordinator", message: "audio recorder started")
            activeAPIKey = apiKey
            let recorderStream = activeAudioStream!
            let audioStream = writer.map { AudioStreamTee.tee(recorderStream, writer: $0) } ?? recorderStream
            let asrModel = settings.asrModel
            activeRecognitionTask = Task { [weak self, asrClient, audioStream, asrModel, apiKey] in
                try await asrClient.recognize(
                    audioChunks: audioStream,
                    model: asrModel,
                    apiKey: apiKey,
                    onPartialResult: { [weak self] partial in
                        await self?.handlePartialRecognition(partial)
                    }
                )
            }
            state = .recording(startedAt: Date())
            coordinatorLogger.info("state=recording")
            DiagnosticLog.write(category: "Coordinator", message: "state=recording")
        } catch let error as AppError {
            await resumeSystemAudioIfNeeded()
            discardFailedRecordingCandidateAudio()
            state = .failed(error)
            coordinatorLogger.error("startRecording failed: \(error.localizedDescription, privacy: .public)")
            DiagnosticLog.write(category: "Coordinator", message: "startRecording failed \(error.localizedDescription)")
        } catch {
            await resumeSystemAudioIfNeeded()
            discardFailedRecordingCandidateAudio()
            state = .failed(.recorderFailed(error.localizedDescription))
            coordinatorLogger.error("startRecording failed: \(error.localizedDescription, privacy: .public)")
            DiagnosticLog.write(category: "Coordinator", message: "startRecording failed \(error.localizedDescription)")
        }
    }

    private func ensureMicrophonePermission() async -> MicrophonePermissionState {
        switch microphonePermissionProvider.currentMicrophonePermission {
        case .authorized:
            return .authorized
        case .notDetermined:
            return await microphonePermissionProvider.requestMicrophonePermission()
        case .denied, .restricted, .unknown:
            return microphonePermissionProvider.currentMicrophonePermission
        }
    }

    func finishRecording() async {
        coordinatorLogger.info("finishRecording requested; state=\(self.state.displayText, privacy: .public)")
        DiagnosticLog.write(category: "Coordinator", message: "finishRecording requested state=\(state.displayText)")
        guard case .recording = state else {
            coordinatorLogger.info("finishRecording ignored; state=\(self.state.displayText, privacy: .public)")
            DiagnosticLog.write(category: "Coordinator", message: "finishRecording ignored state=\(state.displayText)")
            return
        }

        guard activeAudioStream != nil, let apiKey = activeAPIKey, let recognitionTask = activeRecognitionTask else {
            await resumeSystemAudioIfNeeded()
            discardFailedRecordingCandidateAudio()
            clearActiveInputSession()
            state = .failed(.recorderFailed("没有正在进行的录音"))
            coordinatorLogger.error("finishRecording failed: missing active recording session")
            DiagnosticLog.write(category: "Coordinator", message: "finishRecording failed missing active recording session")
            return
        }

        defer {
            activeAudioStream = nil
            activeAPIKey = nil
            if !state.showsRecordingOverlay {
                clearActiveInputSession()
            }
        }

        coordinatorLogger.info("finishRecording accepted")
        DiagnosticLog.write(category: "Coordinator", message: "finishRecording accepted")
        recorder?.stopRecording()
        await resumeSystemAudioIfNeeded()
        activeAudioStream = nil
        activeAPIKey = nil

        guard let textPolisher else {
            discardFailedRecordingCandidateAudio()
            clearActiveInputSession()
            state = .failed(.asrFailed("识别服务未初始化"))
            return
        }

        do {
            state = .recognizing
            coordinatorLogger.info("state=recognizing")
            let recognition = try await recognitionTask.value
            if latestPartialText.isEmpty {
                latestPartialText = recognition.partialText
            }
            activeRecognitionTask = nil

            let recognizedText = recognition.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !recognizedText.isEmpty else {
                discardFailedRecordingCandidateAudio()
                clearActiveInputSession()
                state = .failed(.asrFailed("未识别到语音内容，请确认麦克风权限和输入音量后重试"))
                coordinatorLogger.error("finishRecording failed: empty recognition")
                return
            }

            do {
                state = .polishing
                coordinatorLogger.info("state=polishing")
                let polishMode = settings.polishMode
                let polishedText = try await textPolisher.polish(
                    rawText: recognizedText,
                    strategy: settings.polishStrategy(for: polishMode),
                    model: settings.polishModel,
                    apiKey: apiKey
                )

                discardFailedRecordingCandidateAudio()
                state = .delivering
                coordinatorLogger.info("state=delivering")
                await deliver(polishedText: polishedText, rawText: recognizedText)
            } catch {
                saveInterfaceFailureRecording(stage: .polish, rawASRText: recognizedText, error: error)
                clearFailedRecordingCandidateReferences()
                state = .delivering
                coordinatorLogger.info("state=delivering after polish failure")
                await savePolishFailureDraft(rawText: recognizedText, errorSummary: error.localizedDescription)
            }
        } catch let error as AppError {
            saveInterfaceFailureRecording(stage: .asr, rawASRText: "", error: error)
            clearFailedRecordingCandidateReferences()
            clearActiveInputSession()
            state = .failed(error)
            coordinatorLogger.error("finishRecording failed: \(error.localizedDescription, privacy: .public)")
        } catch {
            let wrappedError = AppError.asrFailed(error.localizedDescription)
            saveInterfaceFailureRecording(stage: .asr, rawASRText: "", error: wrappedError)
            clearFailedRecordingCandidateReferences()
            clearActiveInputSession()
            state = .failed(wrappedError)
            coordinatorLogger.error("finishRecording failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func saveInterfaceFailureRecording(
        stage: FailedRecordingStage,
        rawASRText: String,
        error: Error
    ) {
        guard let failedRecordingStore,
              let id = activeFailedRecordingID,
              let writer = activeFailedRecordingAudioWriter else {
            return
        }

        try? writer.close()

        let focusContext = activeFocusContext ?? focusDetector?.focusedInputContext() ?? .noInput(appName: fallbackAppName)
        let sourceAppName = appName(from: focusContext)

        do {
            try failedRecordingStore.saveFailedRecording(
                id: id,
                createdAt: Date(),
                sourceAppName: sourceAppName,
                mode: settings.polishMode,
                asrModel: settings.asrModel,
                polishModel: settings.polishModel,
                failureStage: stage,
                errorSummary: error.localizedDescription,
                audioFilePath: writer.filePath,
                rawASRText: rawASRText
            )
        } catch {
            coordinatorLogger.error("failed to save failed recording: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func discardFailedRecordingCandidateAudio() {
        activeFailedRecordingAudioWriter?.delete()
        clearFailedRecordingCandidateReferences()
    }

    private func clearFailedRecordingCandidateReferences() {
        activeFailedRecordingAudioWriter = nil
        activeFailedRecordingID = nil
    }

    private func deliver(polishedText: String, rawText: String) async {
        let focusContext = activeFocusContext ?? focusDetector?.focusedInputContext() ?? .noInput(appName: fallbackAppName)

        switch focusContext {
        case .inputAvailable(let appName):
            guard let textInserter else {
                if saveDraft(
                    polishedText: polishedText,
                    rawText: rawText,
                    sourceAppName: appName,
                    deliveryStatus: .pasteFailed,
                    errorSummary: "粘贴服务未初始化"
                ) {
                    state = .completed(.savedDraft)
                }
                return
            }

            do {
                await reactivateCapturedInputApplication()
                if let activeTextComposition {
                    try await activeTextComposition.commit(text: polishedText, restoreClipboard: true)
                } else {
                    try await textInserter.paste(text: polishedText, restoreClipboard: true)
                }
                clearActiveInputSession()
                state = .completed(.pasted)
                coordinatorLogger.info("state=completed pasted")
            } catch {
                if saveDraft(
                    polishedText: polishedText,
                    rawText: rawText,
                    sourceAppName: appName,
                    deliveryStatus: .pasteFailed,
                    errorSummary: error.localizedDescription
                ) {
                    clearActiveInputSession()
                    state = .completed(.savedDraft)
                    coordinatorLogger.info("state=completed savedDraft after paste failure")
                }
            }
        case .noInput(let appName):
            let copyErrorSummary = copyToClipboardIfNeeded(polishedText)
            if saveDraft(
                polishedText: polishedText,
                rawText: rawText,
                sourceAppName: appName,
                deliveryStatus: .noInput(appName: appName),
                errorSummary: copyErrorSummary
            ) {
                clearActiveInputSession()
                state = .completed(.savedDraft)
                coordinatorLogger.info("state=completed savedDraft noInput")
            }
        case .accessibilityPermissionMissing(let appName):
            let copyErrorSummary = copyToClipboardIfNeeded(polishedText)
            if saveDraft(
                polishedText: polishedText,
                rawText: rawText,
                sourceAppName: appName,
                deliveryStatus: .accessibilityPermissionMissing(appName: appName),
                errorSummary: copyErrorSummary
            ) {
                clearActiveInputSession()
                state = .completed(.savedDraft)
                coordinatorLogger.info("state=completed savedDraft accessibilityMissing")
            }
        }
    }

    private func savePolishFailureDraft(rawText: String, errorSummary: String) async {
        let focusContext = activeFocusContext ?? focusDetector?.focusedInputContext() ?? .noInput(appName: fallbackAppName)
        let sourceAppName = appName(from: focusContext)

        if case .inputAvailable = focusContext, let activeTextComposition {
            await reactivateCapturedInputApplication()
            try? await activeTextComposition.commit(text: rawText, restoreClipboard: true)
        }

        if saveDraft(
            polishedText: rawText,
            rawText: rawText,
            sourceAppName: sourceAppName,
            deliveryStatus: .savedDraft,
            errorSummary: errorSummary
        ) {
            clearActiveInputSession()
            state = .completed(.savedDraft)
            coordinatorLogger.info("state=completed savedDraft polishFailure")
        }
    }

    private func prepareLiveComposition(for focusContext: FocusInputContext) {
        activeTextComposition = nil
        activeInputApplication = nil

        guard case .inputAvailable = focusContext else { return }

        activeInputApplication = NSWorkspace.shared.frontmostApplication
        activeTextComposition = textInserter?.makeComposition()
    }

    private func copyToClipboardIfNeeded(_ text: String) -> String? {
        guard settings.autoPasteEnabled else { return nil }

        do {
            guard let textInserter else {
                throw AppError.insertionFailed("剪贴板服务未初始化")
            }
            try textInserter.copyToClipboard(text: text)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func handlePartialRecognition(_ partialText: String) async {
        latestPartialText = partialText

        guard !partialText.isEmpty, let activeTextComposition else { return }

        do {
            await reactivateCapturedInputApplication()
            try await activeTextComposition.update(text: partialText)
        } catch {
            self.activeTextComposition = nil
        }
    }

    private func reactivateCapturedInputApplication() async {
        guard let activeInputApplication, !activeInputApplication.isTerminated else { return }

        if #available(macOS 14.0, *) {
            activeInputApplication.activate()
        } else {
            activeInputApplication.activate(options: [.activateIgnoringOtherApps])
        }
        try? await Task.sleep(nanoseconds: 80_000_000)
    }

    private func clearActiveInputSession() {
        activeFocusContext = nil
        activeTextComposition = nil
        activeInputApplication = nil
        activeRecognitionTask = nil
    }

    private func resumeSystemAudioIfNeeded() async {
        guard shouldResumeSystemAudioAfterRecording else { return }

        shouldResumeSystemAudioAfterRecording = false
        await systemAudioController.resumeAfterRecording()
    }

    private func appName(from focusContext: FocusInputContext) -> String {
        switch focusContext {
        case .inputAvailable(let appName),
             .noInput(let appName),
             .accessibilityPermissionMissing(let appName):
            return appName
        }
    }

    private var fallbackAppName: String {
        sourceAppProvider?.currentAppName() ?? "未知 App"
    }

    private func saveDraft(
        polishedText: String,
        rawText: String,
        sourceAppName: String,
        deliveryStatus: DraftDeliveryStatus,
        errorSummary: String?
    ) -> Bool {
        guard settings.keepDraftHistoryEnabled else {
            state = .failed(.insertionFailed("草稿历史已关闭"))
            return false
        }

        guard let draftStore else {
            state = .failed(.insertionFailed("草稿服务未初始化"))
            return false
        }

        do {
            try draftStore.saveDraft(
                polishedText: polishedText,
                rawASRText: rawText,
                sourceAppName: sourceAppName,
                mode: settings.polishMode,
                deliveryStatus: deliveryStatus,
                errorSummary: errorSummary
            )
            return true
        } catch {
            state = .failed(.insertionFailed(error.localizedDescription))
            return false
        }
    }
}

private extension AppWorkflowState {
    var showsRecordingOverlay: Bool {
        switch self {
        case .recording, .recognizing, .polishing, .delivering:
            return true
        case .idle, .completed, .failed:
            return false
        }
    }

    var canStartRecording: Bool {
        switch self {
        case .idle, .completed, .failed:
            return true
        case .recording, .recognizing, .polishing, .delivering:
            return false
        }
    }
}

private extension MicrophonePermissionState {
    var logName: String {
        switch self {
        case .authorized:
            return "authorized"
        case .notDetermined:
            return "notDetermined"
        case .denied:
            return "denied"
        case .restricted:
            return "restricted"
        case .unknown:
            return "unknown"
        }
    }
}

private extension FocusInputContext {
    var logName: String {
        switch self {
        case .inputAvailable(let appName):
            return "inputAvailable(app=\(appName))"
        case .noInput(let appName):
            return "noInput(app=\(appName))"
        case .accessibilityPermissionMissing(let appName):
            return "accessibilityPermissionMissing(app=\(appName))"
        }
    }
}
