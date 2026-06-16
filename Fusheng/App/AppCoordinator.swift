import Combine
import Foundation

@MainActor
final class AppCoordinator: ObservableObject {
    @Published private(set) var state: AppWorkflowState
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

    private var activeAudioStream: AsyncThrowingStream<Data, Error>?
    private var activeAPIKey: String?

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
    }

    var statusText: String { state.displayText }
    var menuBarSystemImage: String { state.menuBarSystemImage }

    func toggleRecordingForShell() {
        switch state {
        case .recording:
            state = .idle
            activeAudioStream = nil
            activeAPIKey = nil
        case .idle, .completed, .failed:
            state = .recording(startedAt: Date())
        case .recognizing, .polishing, .delivering:
            break
        }
    }

    func startRecording() async {
        guard !state.isRecording else { return }

        do {
            guard let apiKey = try apiKeyProvider.loadAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !apiKey.isEmpty else {
                state = .failed(.missingAPIKey)
                return
            }

            guard let recorder else {
                state = .failed(.recorderFailed("录音服务未初始化"))
                return
            }

            activeAudioStream = try recorder.startRecording()
            activeAPIKey = apiKey
            state = .recording(startedAt: Date())
        } catch let error as AppError {
            state = .failed(error)
        } catch {
            state = .failed(.recorderFailed(error.localizedDescription))
        }
    }

    func finishRecording() async {
        guard let audioStream = activeAudioStream, let apiKey = activeAPIKey else {
            state = .failed(.recorderFailed("没有正在进行的录音"))
            return
        }

        recorder?.stopRecording()
        activeAudioStream = nil
        activeAPIKey = nil

        guard let asrClient, let textPolisher else {
            state = .failed(.asrFailed("识别服务未初始化"))
            return
        }

        do {
            state = .recognizing
            let recognition = try await asrClient.recognize(
                audioChunks: audioStream,
                model: settings.asrModel,
                apiKey: apiKey
            )
            latestPartialText = recognition.partialText

            do {
                state = .polishing
                let polishedText = try await textPolisher.polish(
                    rawText: recognition.rawText,
                    mode: settings.polishMode,
                    model: settings.polishModel,
                    apiKey: apiKey
                )

                state = .delivering
                await deliver(polishedText: polishedText, rawText: recognition.rawText)
            } catch {
                state = .delivering
                await deliver(polishedText: recognition.rawText, rawText: recognition.rawText)
            }
        } catch let error as AppError {
            state = .failed(error)
        } catch {
            state = .failed(.asrFailed(error.localizedDescription))
        }
    }

    private func deliver(polishedText: String, rawText: String) async {
        let focusContext = focusDetector?.focusedInputContext() ?? .noInput(appName: fallbackAppName)

        switch focusContext {
        case .inputAvailable(let appName):
            if settings.autoPasteEnabled {
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
                    try await textInserter.paste(text: polishedText, restoreClipboard: settings.restoreClipboardEnabled)
                    state = .completed(.pasted)
                } catch {
                    if saveDraft(
                        polishedText: polishedText,
                        rawText: rawText,
                        sourceAppName: appName,
                        deliveryStatus: .pasteFailed,
                        errorSummary: error.localizedDescription
                    ) {
                        state = .completed(.savedDraft)
                    }
                }
            } else {
                if saveDraft(
                    polishedText: polishedText,
                    rawText: rawText,
                    sourceAppName: appName,
                    deliveryStatus: .autoPasteDisabled,
                    errorSummary: nil
                ) {
                    state = .completed(.savedDraft)
                }
            }
        case .noInput(let appName):
            if saveDraft(
                polishedText: polishedText,
                rawText: rawText,
                sourceAppName: appName,
                deliveryStatus: .noInput(appName: appName),
                errorSummary: nil
            ) {
                state = .completed(.savedDraft)
            }
        case .accessibilityPermissionMissing(let appName):
            if saveDraft(
                polishedText: polishedText,
                rawText: rawText,
                sourceAppName: appName,
                deliveryStatus: .accessibilityPermissionMissing(appName: appName),
                errorSummary: nil
            ) {
                state = .completed(.savedDraft)
            }
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
        guard settings.keepDraftHistoryEnabled else { return true }

        do {
            try draftStore?.saveDraft(
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
    var isRecording: Bool {
        if case .recording = self {
            return true
        }
        return false
    }
}
