import SwiftData
import SwiftUI

@main
struct FushengApp: App {
    @StateObject private var coordinator: AppCoordinator
    @State private var hotkeyService: HotkeyService?

    private let settings: SettingsStore
    private let draftModelContainer: ModelContainer

    init() {
        let settings = SettingsStore()
        let draftModelContainer = Self.makeDraftModelContainer()
        let coordinator = AppCoordinator(
            settings: settings,
            apiKeyProvider: KeychainService(),
            recorder: AudioRecorder(),
            asrClient: DashScopeASRClient(),
            textPolisher: TextPolishClient(),
            focusDetector: nil,
            textInserter: nil,
            draftStore: DraftStore(modelContext: draftModelContainer.mainContext),
            sourceAppProvider: nil
        )

        self.settings = settings
        self.draftModelContainer = draftModelContainer
        _coordinator = StateObject(wrappedValue: coordinator)
    }

    var body: some Scene {
        MenuBarExtra("浮声", systemImage: coordinator.menuBarSystemImage) {
            RootMenuContent()
                .environmentObject(coordinator)
                .modelContainer(draftModelContainer)
                .task {
                    startHotkeyServiceIfNeeded()
                }
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environmentObject(coordinator)
                .frame(width: 520, height: 520)
        }

        Window("草稿历史", id: "draft-history") {
            DraftHistoryView()
                .modelContainer(draftModelContainer)
                .frame(width: 720, height: 520)
        }

        Window("录音状态", id: "recording-overlay") {
            RecordingOverlayView()
                .environmentObject(coordinator)
                .frame(width: 280, height: 120)
        }
    }

    private static func makeDraftModelContainer() -> ModelContainer {
        do {
            return try ModelContainer(for: DraftRecord.self)
        } catch {
            fatalError("Failed to create draft model container: \(error)")
        }
    }

    private func startHotkeyServiceIfNeeded() {
        guard hotkeyService == nil else { return }

        let service = HotkeyService(
            settings: settings,
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
                Task { await coordinator.startRecording() }
            },
            onFinish: {
                Task { await coordinator.finishRecording() }
            }
        )
        service.start()
        hotkeyService = service
    }
}
