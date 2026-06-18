import AVFoundation
import Foundation

protocol APIKeyProviding {
    func loadAPIKey() throws -> String?
}

protocol SettingsProviding {
    var triggerMode: TriggerMode { get set }
    var holdKey: SpeechHotkey { get set }
    var asrModel: String { get set }
    var polishModel: String { get set }
    var polishMode: TextPolishMode { get set }
    var autoPasteEnabled: Bool { get set }
    var restoreClipboardEnabled: Bool { get set }
    var keepDraftHistoryEnabled: Bool { get set }
    func polishStrategy(for mode: TextPolishMode) -> TextPolishStrategy
    func savePolishStrategy(_ strategy: TextPolishStrategy, for mode: TextPolishMode)
    func resetPolishStrategy(for mode: TextPolishMode)
    func resetAllPolishStrategies()
}

@MainActor
protocol DraftStoring {
    func saveDraft(polishedText: String, rawASRText: String, sourceAppName: String, mode: TextPolishMode, deliveryStatus: DraftDeliveryStatus, errorSummary: String?) throws
    func recentDrafts(limit: Int) throws -> [DraftSnapshot]
    func deleteDraft(id: UUID) throws
}

@MainActor
protocol FailedRecordingStoring {
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
    ) throws
    func recentFailedRecordings(limit: Int) throws -> [FailedRecordingSnapshot]
    func failedRecording(id: UUID) throws -> FailedRecordingSnapshot?
    func updateRetryState(id: UUID, state: FailedRecordingRetryState, errorSummary: String?, lastRetryAt: Date?) throws
    func deleteFailedRecording(id: UUID) throws
}

protocol FailedRecordingAudioWriting: AnyObject {
    var filePath: String { get }
    func append(_ data: Data) throws
    func close() throws
    func delete()
}

protocol FailedRecordingAudioStoring {
    func makeWriter(id: UUID) throws -> FailedRecordingAudioWriting
    func fileExists(at path: String) -> Bool
    func audioChunks(from path: String) throws -> AsyncThrowingStream<Data, Error>
    func deleteAudio(at path: String)
}

protocol TextPolishing {
    func polish(rawText: String, strategy: TextPolishStrategy, model: String, apiKey: String) async throws -> String
}

protocol ASRRecognizing {
    func recognize(
        audioChunks: AsyncThrowingStream<Data, Error>,
        model: String,
        apiKey: String,
        onPartialResult: @escaping @Sendable (String) async -> Void
    ) async throws -> RecognitionResult
}

extension ASRRecognizing {
    func recognize(audioChunks: AsyncThrowingStream<Data, Error>, model: String, apiKey: String) async throws -> RecognitionResult {
        try await recognize(audioChunks: audioChunks, model: model, apiKey: apiKey, onPartialResult: { _ in })
    }
}

protocol FocusDetecting {
    func focusedInputContext() -> FocusInputContext
}

protocol TextInserting {
    func paste(text: String, restoreClipboard: Bool) async throws
    func copyToClipboard(text: String) throws
    @MainActor func makeComposition() -> TextComposing
}

@MainActor
protocol TextComposing: AnyObject {
    func update(text: String) async throws
    func commit(text: String, restoreClipboard: Bool) async throws
}

protocol SourceAppProviding {
    func currentAppName() -> String
}

enum MicrophonePermissionState: Equatable {
    case authorized
    case notDetermined
    case denied
    case restricted
    case unknown

    init(authorizationStatus: AVAuthorizationStatus) {
        switch authorizationStatus {
        case .authorized:
            self = .authorized
        case .notDetermined:
            self = .notDetermined
        case .denied:
            self = .denied
        case .restricted:
            self = .restricted
        @unknown default:
            self = .unknown
        }
    }
}

protocol MicrophonePermissionProviding {
    var currentMicrophonePermission: MicrophonePermissionState { get }
    func requestMicrophonePermission() async -> MicrophonePermissionState
}

struct SystemMicrophonePermissionProvider: MicrophonePermissionProviding {
    var currentMicrophonePermission: MicrophonePermissionState {
        MicrophonePermissionState(authorizationStatus: AVCaptureDevice.authorizationStatus(for: .audio))
    }

    func requestMicrophonePermission() async -> MicrophonePermissionState {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                continuation.resume(returning: currentMicrophonePermission)
            }
        }
    }
}

protocol AudioRecording {
    func startRecording() throws -> AsyncThrowingStream<Data, Error>
    func stopRecording()
}

enum FocusInputContext: Equatable {
    case inputAvailable(appName: String)
    case noInput(appName: String)
    case accessibilityPermissionMissing(appName: String)
}
