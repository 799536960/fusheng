import AppKit
import SwiftData
import SwiftUI

@main
@MainActor
struct FushengApp: App {
    @NSApplicationDelegateAdaptor(AppLaunchDelegate.self) private var appLaunchDelegate
    @StateObject private var coordinator: AppCoordinator

    private let settings: SettingsStore
    private let draftModelContainer: ModelContainer
    private let failedRecordingAudioStore: FailedRecordingAudioStore
    private let failedRecordingStore: FailedRecordingStore
    private let failedRecordingRetryService: FailedRecordingRetryService
    private let hotkeyService: HotkeyService

    init() {
        let settings = SettingsStore()
        let draftModelContainer = Self.makeDraftModelContainer()
        let focusDetector = FocusDetector()
        let keychain = KeychainService()
        let asrClient = DashScopeASRClient()
        let textPolisher = TextPolishClient()
        let textInserter = TextInsertionService()
        let draftStore = DraftStore(modelContext: draftModelContainer.mainContext)
        let failedRecordingAudioStore = FailedRecordingAudioStore()
        let failedRecordingStore = FailedRecordingStore(
            modelContext: draftModelContainer.mainContext,
            audioStore: failedRecordingAudioStore
        )
        let coordinator = AppCoordinator(
            settings: settings,
            apiKeyProvider: keychain,
            recorder: AudioRecorder(),
            asrClient: asrClient,
            textPolisher: textPolisher,
            focusDetector: focusDetector,
            textInserter: textInserter,
            draftStore: draftStore,
            sourceAppProvider: focusDetector,
            failedRecordingStore: failedRecordingStore,
            failedRecordingAudioStore: failedRecordingAudioStore
        )
        let failedRecordingRetryService = FailedRecordingRetryService(
            apiKeyProvider: keychain,
            failedRecordingStore: failedRecordingStore,
            audioStore: failedRecordingAudioStore,
            asrClient: asrClient,
            textPolisher: textPolisher,
            textInserter: textInserter,
            draftStore: draftStore,
            settings: settings
        )
        let service = HotkeyService(
            settings: settings,
            canStart: {
                coordinator.canStartRecordingFromHotkey
            },
            onToggle: {
                Task {
                    if case .recording = coordinator.state {
                        await coordinator.finishRecording()
                    } else {
                        await coordinator.startRecording()
                    }
                }
            },
            onStart: {
                DiagnosticLog.write(category: "App", message: "hotkey onStart closure invoked")
                Task { @MainActor [coordinator] in
                    DiagnosticLog.write(category: "App", message: "hotkey start task entered state=\(coordinator.statusText)")
                    await coordinator.startRecording()
                    DiagnosticLog.write(category: "App", message: "hotkey start task completed state=\(coordinator.statusText)")
                }
            },
            onFinish: {
                DiagnosticLog.write(category: "App", message: "hotkey onFinish closure invoked")
                Task { @MainActor [coordinator] in
                    DiagnosticLog.write(category: "App", message: "hotkey finish task entered state=\(coordinator.statusText)")
                    await coordinator.finishRecording()
                    DiagnosticLog.write(category: "App", message: "hotkey finish task completed state=\(coordinator.statusText)")
                }
            }
        )
        if !Self.isRunningTests {
            service.start()
        }

        self.settings = settings
        self.draftModelContainer = draftModelContainer
        self.failedRecordingAudioStore = failedRecordingAudioStore
        self.failedRecordingStore = failedRecordingStore
        self.failedRecordingRetryService = failedRecordingRetryService
        self.hotkeyService = service
        _coordinator = StateObject(wrappedValue: coordinator)
    }

    var body: some Scene {
        MenuBarExtra {
            RootMenuContent()
                .environmentObject(coordinator)
                .modelContainer(draftModelContainer)
        } label: {
            Image(nsImage: Self.menuBarIconImage)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .accessibilityLabel("浮声")
        }
        .menuBarExtraStyle(.menu)

        Window("草稿历史", id: "draft-history") {
            DraftHistoryView()
                .modelContainer(draftModelContainer)
                .frame(width: 720, height: 520)
        }

        Window("失败录音", id: "failed-recordings") {
            FailedRecordingView(
                store: failedRecordingStore,
                audioStore: failedRecordingAudioStore,
                retryService: failedRecordingRetryService
            )
            .frame(width: 760, height: 520)
        }
    }

    private static func makeDraftModelContainer() -> ModelContainer {
        do {
            return try ModelContainer(for: DraftRecord.self, FailedRecordingRecord.self)
        } catch {
            fatalError("Failed to create draft model container: \(error)")
        }
    }

    private static var menuBarIconImage: NSImage {
        let image = NSImage(named: "MenuBarIcon")
            ?? NSImage(systemSymbolName: "waveform", accessibilityDescription: "浮声")
            ?? NSImage(size: NSSize(width: 18, height: 18))
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }

    private static var isRunningTests: Bool {
        NSClassFromString("XCTestCase") != nil
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.arguments.contains { argument in
                argument == "-XCTest"
                    || argument.contains("XCTest")
                    || argument.hasSuffix(".xctest")
            }
            || Bundle.allBundles.contains { bundle in
                bundle.bundlePath.hasSuffix(".xctest")
            }
    }
}
