# Fusheng macOS MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS 14+ menu bar app that records speech, sends audio to Alibaba DashScope real-time ASR, polishes the recognized text with the OpenAI-compatible DashScope chat API, and either pastes the result into the current focused input or saves it as a local draft.

**Architecture:** Use a native SwiftUI menu bar app generated from `project.yml` with XcodeGen. Keep UI, orchestration, storage, network clients, audio capture, hotkeys, accessibility focus detection, and text insertion behind focused types and protocols so the coordinator state machine can be tested with fakes.

**Tech Stack:** SwiftUI, AppKit, AVFoundation, Accessibility API, SwiftData, Keychain Services, URLSession WebSocket, KeyboardShortcuts 3.0.0, XCTest, XcodeGen.

---

## Scope Check

The spec contains one integrated vertical product: a menu bar voice input app. Its modules are coupled by a single user flow, so this remains one implementation plan split into small, testable tasks.

## Target File Structure

```text
project.yml
Fusheng/
  App/
    FushengApp.swift
    AppCoordinator.swift
  Core/
    AppWorkflowState.swift
    AppError.swift
    AppModels.swift
    TextPolishMode.swift
    TriggerMode.swift
  Services/
    ServiceProtocols.swift
    SettingsStore.swift
    KeychainService.swift
    DraftStore.swift
    DashScopeASRClient.swift
    DashScopeASREvents.swift
    TextPolishClient.swift
    HotkeyService.swift
    AudioRecorder.swift
    FocusDetector.swift
    TextInsertionService.swift
  UI/
    RootMenuContent.swift
    SettingsView.swift
    DraftHistoryView.swift
    RecordingOverlayView.swift
  Resources/
    Info.plist
  Fusheng.entitlements
FushengTests/
  AppWorkflowStateTests.swift
  SettingsStoreTests.swift
  DraftStoreTests.swift
  DashScopeASREventsTests.swift
  TextPolishClientTests.swift
  AppCoordinatorTests.swift
```

## Task 1: Generate the macOS App Shell

**Files:**
- Create: `project.yml`
- Create: `Fusheng/Resources/Info.plist`
- Create: `Fusheng/Fusheng.entitlements`
- Create: `Fusheng/App/FushengApp.swift`
- Create: `Fusheng/App/AppCoordinator.swift`
- Create: `Fusheng/UI/RootMenuContent.swift`
- Create: `FushengTests/SanityTests.swift`

- [ ] **Step 1: Write the project definition**

Create `project.yml`:

```yaml
name: Fusheng
options:
  minimumXcodeGenVersion: 2.42.0
  deploymentTarget:
    macOS: "14.0"
packages:
  KeyboardShortcuts:
    url: https://github.com/sindresorhus/KeyboardShortcuts
    from: 3.0.0
settings:
  base:
    SWIFT_VERSION: 5.10
    MACOSX_DEPLOYMENT_TARGET: "14.0"
targets:
  Fusheng:
    type: application
    platform: macOS
    sources:
      - Fusheng
    dependencies:
      - package: KeyboardShortcuts
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.fusheng.voiceinput
        PRODUCT_NAME: Fusheng
        INFOPLIST_FILE: Fusheng/Resources/Info.plist
        CODE_SIGN_STYLE: Automatic
        ENABLE_HARDENED_RUNTIME: YES
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
  FushengTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - FushengTests
    dependencies:
      - target: Fusheng
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.fusheng.voiceinput.tests
        GENERATE_INFOPLIST_FILE: YES
```

- [ ] **Step 2: Add app metadata**

Create `Fusheng/Resources/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>浮声</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>浮声需要使用麦克风录制语音并转换为文本。</string>
</dict>
</plist>
```

Create `Fusheng/Fusheng.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict/>
</plist>
```

- [ ] **Step 3: Add the initial SwiftUI menu bar app**

Create `Fusheng/App/FushengApp.swift`:

```swift
import SwiftUI

@main
struct FushengApp: App {
    @StateObject private var coordinator = AppCoordinator()

    var body: some Scene {
        MenuBarExtra("浮声", systemImage: coordinator.menuBarSystemImage) {
            RootMenuContent()
                .environmentObject(coordinator)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            Text("设置将在后续任务接入。")
                .frame(width: 360, height: 160)
        }
    }
}
```

Create `Fusheng/App/AppCoordinator.swift`:

```swift
import Foundation

@MainActor
final class AppCoordinator: ObservableObject {
    @Published private(set) var statusText = "空闲"

    var menuBarSystemImage: String {
        statusText == "录音中" ? "waveform.circle.fill" : "waveform.circle"
    }

    func toggleRecordingForShell() {
        statusText = statusText == "录音中" ? "空闲" : "录音中"
    }
}
```

Create `Fusheng/UI/RootMenuContent.swift`:

```swift
import SwiftUI

struct RootMenuContent: View {
    @EnvironmentObject private var coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading) {
            Text("状态：\(coordinator.statusText)")

            Button("开始/停止录音") {
                coordinator.toggleRecordingForShell()
            }

            Divider()

            Button("打开设置") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }

            Button("退出") {
                NSApp.terminate(nil)
            }
        }
        .padding(.vertical, 6)
    }
}
```

- [ ] **Step 4: Add the first smoke test**

Create `FushengTests/SanityTests.swift`:

```swift
import XCTest
@testable import Fusheng

final class SanityTests: XCTestCase {
    @MainActor
    func testShellCoordinatorTogglesStatus() {
        let coordinator = AppCoordinator()

        XCTAssertEqual(coordinator.statusText, "空闲")
        coordinator.toggleRecordingForShell()
        XCTAssertEqual(coordinator.statusText, "录音中")
        coordinator.toggleRecordingForShell()
        XCTAssertEqual(coordinator.statusText, "空闲")
    }
}
```

- [ ] **Step 5: Generate and test the project**

Run:

```bash
if ! command -v xcodegen >/dev/null 2>&1; then brew install xcodegen; fi
xcodegen generate
xcodebuild test -project Fusheng.xcodeproj -scheme Fusheng -destination 'platform=macOS'
```

Expected: XcodeGen creates `Fusheng.xcodeproj`; the test target builds and `SanityTests.testShellCoordinatorTogglesStatus` passes.

- [ ] **Step 6: Commit**

```bash
git add project.yml Fusheng FushengTests Fusheng.xcodeproj
git commit -m "chore: create macOS menu bar app shell"
```

## Task 2: Add Core Models and Workflow State

**Files:**
- Create: `Fusheng/Core/AppWorkflowState.swift`
- Create: `Fusheng/Core/AppError.swift`
- Create: `Fusheng/Core/AppModels.swift`
- Create: `Fusheng/Core/TextPolishMode.swift`
- Create: `Fusheng/Core/TriggerMode.swift`
- Create: `Fusheng/Services/ServiceProtocols.swift`
- Modify: `Fusheng/App/AppCoordinator.swift`
- Test: `FushengTests/AppWorkflowStateTests.swift`

- [ ] **Step 1: Write failing state display tests**

Create `FushengTests/AppWorkflowStateTests.swift`:

```swift
import XCTest
@testable import Fusheng

final class AppWorkflowStateTests: XCTestCase {
    func testWorkflowStateDisplayText() {
        XCTAssertEqual(AppWorkflowState.idle.displayText, "空闲")
        XCTAssertEqual(AppWorkflowState.recording(startedAt: Date(timeIntervalSince1970: 1)).displayText, "录音中")
        XCTAssertEqual(AppWorkflowState.recognizing.displayText, "识别中")
        XCTAssertEqual(AppWorkflowState.polishing.displayText, "整理中")
        XCTAssertEqual(AppWorkflowState.delivering.displayText, "输出中")
        XCTAssertEqual(AppWorkflowState.completed(.pasted).displayText, "已粘贴")
        XCTAssertEqual(AppWorkflowState.completed(.savedDraft).displayText, "已保存草稿")
        XCTAssertEqual(AppWorkflowState.failed(.missingAPIKey).displayText, "错误：缺少 API Key")
    }

    func testMenuBarImageChangesForActiveStates() {
        XCTAssertEqual(AppWorkflowState.idle.menuBarSystemImage, "waveform.circle")
        XCTAssertEqual(AppWorkflowState.recording(startedAt: Date()).menuBarSystemImage, "waveform.circle.fill")
        XCTAssertEqual(AppWorkflowState.polishing.menuBarSystemImage, "sparkles")
        XCTAssertEqual(AppWorkflowState.failed(.asrFailed("网络断开")).menuBarSystemImage, "exclamationmark.triangle")
    }
}
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
xcodebuild test -project Fusheng.xcodeproj -scheme Fusheng -destination 'platform=macOS' -only-testing:FushengTests/AppWorkflowStateTests
```

Expected: FAIL because `AppWorkflowState` is not defined.

- [ ] **Step 3: Add core enums and value types**

Create `Fusheng/Core/AppError.swift`:

```swift
import Foundation

enum AppError: Error, Equatable, LocalizedError {
    case missingAPIKey
    case microphonePermissionDenied
    case accessibilityPermissionDenied
    case recorderFailed(String)
    case asrFailed(String)
    case polishFailed(String)
    case insertionFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "缺少 API Key"
        case .microphonePermissionDenied:
            return "麦克风未授权"
        case .accessibilityPermissionDenied:
            return "辅助功能未授权"
        case .recorderFailed(let message):
            return "录音失败：\(message)"
        case .asrFailed(let message):
            return "识别失败：\(message)"
        case .polishFailed(let message):
            return "整理失败：\(message)"
        case .insertionFailed(let message):
            return "粘贴失败：\(message)"
        }
    }
}
```

Create `Fusheng/Core/AppModels.swift`:

```swift
import Foundation

enum DeliveryResult: Equatable {
    case pasted
    case savedDraft
}

struct RecognitionResult: Equatable {
    let rawText: String
    let partialText: String
}

struct PolishedText: Equatable {
    let rawText: String
    let polishedText: String
    let mode: TextPolishMode
}

struct DraftSnapshot: Identifiable, Equatable {
    let id: UUID
    let polishedText: String
    let rawASRText: String
    let createdAt: Date
    let sourceAppName: String
    let mode: TextPolishMode
    let deliveryStatus: String
    let errorSummary: String?
}
```

Create `Fusheng/Core/TextPolishMode.swift`:

```swift
import Foundation

enum TextPolishMode: String, CaseIterable, Identifiable, Codable {
    case original
    case clean
    case professional
    case concise

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .original: return "原文"
        case .clean: return "整理"
        case .professional: return "专业"
        case .concise: return "简短"
        }
    }
}
```

Create `Fusheng/Core/TriggerMode.swift`:

```swift
import Foundation

enum TriggerMode: String, CaseIterable, Identifiable, Codable {
    case toggle
    case hold

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .toggle: return "按一次开始/再按一次结束"
        case .hold: return "按住说话/松开结束"
        }
    }
}
```

Create `Fusheng/Core/AppWorkflowState.swift`:

```swift
import Foundation

enum AppWorkflowState: Equatable {
    case idle
    case recording(startedAt: Date)
    case recognizing
    case polishing
    case delivering
    case completed(DeliveryResult)
    case failed(AppError)

    var displayText: String {
        switch self {
        case .idle:
            return "空闲"
        case .recording:
            return "录音中"
        case .recognizing:
            return "识别中"
        case .polishing:
            return "整理中"
        case .delivering:
            return "输出中"
        case .completed(.pasted):
            return "已粘贴"
        case .completed(.savedDraft):
            return "已保存草稿"
        case .failed(let error):
            return "错误：\(error.localizedDescription)"
        }
    }

    var menuBarSystemImage: String {
        switch self {
        case .idle, .completed:
            return "waveform.circle"
        case .recording:
            return "waveform.circle.fill"
        case .recognizing:
            return "waveform"
        case .polishing:
            return "sparkles"
        case .delivering:
            return "arrow.up.doc"
        case .failed:
            return "exclamationmark.triangle"
        }
    }
}
```

- [ ] **Step 4: Add service protocols**

Create `Fusheng/Services/ServiceProtocols.swift`:

```swift
import Foundation

protocol APIKeyProviding {
    func loadAPIKey() throws -> String?
}

protocol SettingsProviding {
    var triggerMode: TriggerMode { get set }
    var asrModel: String { get set }
    var polishModel: String { get set }
    var polishMode: TextPolishMode { get set }
    var autoPasteEnabled: Bool { get set }
    var restoreClipboardEnabled: Bool { get set }
    var keepDraftHistoryEnabled: Bool { get set }
}

protocol DraftStoring {
    func saveDraft(polishedText: String, rawASRText: String, sourceAppName: String, mode: TextPolishMode, deliveryStatus: String, errorSummary: String?) throws
    func recentDrafts(limit: Int) throws -> [DraftSnapshot]
    func deleteDraft(id: UUID) throws
}

protocol TextPolishing {
    func polish(rawText: String, mode: TextPolishMode, model: String, apiKey: String) async throws -> String
}

protocol FocusDetecting {
    func focusedInputContext() -> FocusInputContext
}

protocol TextInserting {
    func paste(text: String, restoreClipboard: Bool) async throws
}

protocol SourceAppProviding {
    func currentAppName() -> String
}

enum FocusInputContext: Equatable {
    case inputAvailable(appName: String)
    case noInput(appName: String)
    case accessibilityPermissionMissing(appName: String)
}
```

- [ ] **Step 5: Update AppCoordinator to use the workflow state**

Replace `Fusheng/App/AppCoordinator.swift`:

```swift
import Foundation

@MainActor
final class AppCoordinator: ObservableObject {
    @Published private(set) var state: AppWorkflowState = .idle

    var statusText: String { state.displayText }
    var menuBarSystemImage: String { state.menuBarSystemImage }

    func toggleRecordingForShell() {
        switch state {
        case .recording:
            state = .idle
        default:
            state = .recording(startedAt: Date())
        }
    }
}
```

- [ ] **Step 6: Run tests**

Run:

```bash
xcodebuild test -project Fusheng.xcodeproj -scheme Fusheng -destination 'platform=macOS'
```

Expected: PASS for `SanityTests` and `AppWorkflowStateTests`.

- [ ] **Step 7: Commit**

```bash
git add Fusheng FushengTests
git commit -m "feat: add core workflow models"
```

## Task 3: Implement Settings and Keychain Storage

**Files:**
- Create: `Fusheng/Services/SettingsStore.swift`
- Create: `Fusheng/Services/KeychainService.swift`
- Test: `FushengTests/SettingsStoreTests.swift`

- [ ] **Step 1: Write failing settings tests**

Create `FushengTests/SettingsStoreTests.swift`:

```swift
import XCTest
@testable import Fusheng

final class SettingsStoreTests: XCTestCase {
    func testDefaultSettings() {
        let defaults = UserDefaults(suiteName: "SettingsStoreTests.default")!
        defaults.removePersistentDomain(forName: "SettingsStoreTests.default")

        let store = SettingsStore(defaults: defaults)

        XCTAssertEqual(store.triggerMode, .toggle)
        XCTAssertEqual(store.asrModel, "fun-asr-realtime")
        XCTAssertEqual(store.polishModel, "qwen-plus")
        XCTAssertEqual(store.polishMode, .clean)
        XCTAssertTrue(store.autoPasteEnabled)
        XCTAssertTrue(store.restoreClipboardEnabled)
        XCTAssertTrue(store.keepDraftHistoryEnabled)
    }

    func testPersistsSettings() {
        let defaults = UserDefaults(suiteName: "SettingsStoreTests.persist")!
        defaults.removePersistentDomain(forName: "SettingsStoreTests.persist")

        var store = SettingsStore(defaults: defaults)
        store.triggerMode = .hold
        store.asrModel = "custom-asr"
        store.polishModel = "custom-chat"
        store.polishMode = .professional
        store.autoPasteEnabled = false
        store.restoreClipboardEnabled = false
        store.keepDraftHistoryEnabled = false

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.triggerMode, .hold)
        XCTAssertEqual(reloaded.asrModel, "custom-asr")
        XCTAssertEqual(reloaded.polishModel, "custom-chat")
        XCTAssertEqual(reloaded.polishMode, .professional)
        XCTAssertFalse(reloaded.autoPasteEnabled)
        XCTAssertFalse(reloaded.restoreClipboardEnabled)
        XCTAssertFalse(reloaded.keepDraftHistoryEnabled)
    }
}
```

- [ ] **Step 2: Run settings tests and verify failure**

Run:

```bash
xcodebuild test -project Fusheng.xcodeproj -scheme Fusheng -destination 'platform=macOS' -only-testing:FushengTests/SettingsStoreTests
```

Expected: FAIL because `SettingsStore` is not defined.

- [ ] **Step 3: Add SettingsStore**

Create `Fusheng/Services/SettingsStore.swift`:

```swift
import Foundation

struct SettingsStore: SettingsProviding {
    private enum Key {
        static let triggerMode = "triggerMode"
        static let asrModel = "asrModel"
        static let polishModel = "polishModel"
        static let polishMode = "polishMode"
        static let autoPasteEnabled = "autoPasteEnabled"
        static let restoreClipboardEnabled = "restoreClipboardEnabled"
        static let keepDraftHistoryEnabled = "keepDraftHistoryEnabled"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var triggerMode: TriggerMode {
        get { TriggerMode(rawValue: defaults.string(forKey: Key.triggerMode) ?? "") ?? .toggle }
        set { defaults.set(newValue.rawValue, forKey: Key.triggerMode) }
    }

    var asrModel: String {
        get { defaults.string(forKey: Key.asrModel) ?? "fun-asr-realtime" }
        set { defaults.set(newValue, forKey: Key.asrModel) }
    }

    var polishModel: String {
        get { defaults.string(forKey: Key.polishModel) ?? "qwen-plus" }
        set { defaults.set(newValue, forKey: Key.polishModel) }
    }

    var polishMode: TextPolishMode {
        get { TextPolishMode(rawValue: defaults.string(forKey: Key.polishMode) ?? "") ?? .clean }
        set { defaults.set(newValue.rawValue, forKey: Key.polishMode) }
    }

    var autoPasteEnabled: Bool {
        get { defaults.object(forKey: Key.autoPasteEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.autoPasteEnabled) }
    }

    var restoreClipboardEnabled: Bool {
        get { defaults.object(forKey: Key.restoreClipboardEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.restoreClipboardEnabled) }
    }

    var keepDraftHistoryEnabled: Bool {
        get { defaults.object(forKey: Key.keepDraftHistoryEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.keepDraftHistoryEnabled) }
    }
}
```

- [ ] **Step 4: Add KeychainService**

Create `Fusheng/Services/KeychainService.swift`:

```swift
import Foundation
import Security

struct KeychainService: APIKeyProviding {
    private let service = "com.fusheng.voiceinput"
    private let account = "dashscope-api-key"

    func saveAPIKey(_ apiKey: String) throws {
        let data = Data(apiKey.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)

        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw AppError.recorderFailed("Keychain 保存失败：\(status)")
        }
    }

    func loadAPIKey() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw AppError.recorderFailed("Keychain 读取失败：\(status)")
        }
        return String(data: data, encoding: .utf8)
    }

    func deleteAPIKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AppError.recorderFailed("Keychain 删除失败：\(status)")
        }
    }
}
```

- [ ] **Step 5: Run tests**

Run:

```bash
xcodebuild test -project Fusheng.xcodeproj -scheme Fusheng -destination 'platform=macOS' -only-testing:FushengTests/SettingsStoreTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Fusheng/Services/SettingsStore.swift Fusheng/Services/KeychainService.swift FushengTests/SettingsStoreTests.swift
git commit -m "feat: add settings and keychain storage"
```

## Task 4: Implement SwiftData Draft Storage

**Files:**
- Create: `Fusheng/Services/DraftStore.swift`
- Test: `FushengTests/DraftStoreTests.swift`

- [ ] **Step 1: Write failing draft store tests**

Create `FushengTests/DraftStoreTests.swift`:

```swift
import SwiftData
import XCTest
@testable import Fusheng

final class DraftStoreTests: XCTestCase {
    @MainActor
    func testSaveAndReadRecentDrafts() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DraftRecord.self, configurations: config)
        let store = DraftStore(modelContext: container.mainContext)

        try store.saveDraft(
            polishedText: "整理后的文本",
            rawASRText: "原始识别文本",
            sourceAppName: "Notes",
            mode: .clean,
            deliveryStatus: "savedDraft",
            errorSummary: nil
        )

        let drafts = try store.recentDrafts(limit: 5)
        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(drafts[0].polishedText, "整理后的文本")
        XCTAssertEqual(drafts[0].rawASRText, "原始识别文本")
        XCTAssertEqual(drafts[0].sourceAppName, "Notes")
        XCTAssertEqual(drafts[0].mode, .clean)
    }

    @MainActor
    func testDeleteDraft() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DraftRecord.self, configurations: config)
        let store = DraftStore(modelContext: container.mainContext)

        try store.saveDraft(polishedText: "A", rawASRText: "B", sourceAppName: "X", mode: .original, deliveryStatus: "savedDraft", errorSummary: nil)
        let draft = try XCTUnwrap(store.recentDrafts(limit: 1).first)

        try store.deleteDraft(id: draft.id)

        XCTAssertEqual(try store.recentDrafts(limit: 5), [])
    }
}
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
xcodebuild test -project Fusheng.xcodeproj -scheme Fusheng -destination 'platform=macOS' -only-testing:FushengTests/DraftStoreTests
```

Expected: FAIL because `DraftRecord` and `DraftStore` are not defined.

- [ ] **Step 3: Add DraftStore**

Create `Fusheng/Services/DraftStore.swift`:

```swift
import Foundation
import SwiftData

@Model
final class DraftRecord {
    @Attribute(.unique) var id: UUID
    var polishedText: String
    var rawASRText: String
    var createdAt: Date
    var sourceAppName: String
    var modeRawValue: String
    var deliveryStatus: String
    var errorSummary: String?

    init(
        id: UUID = UUID(),
        polishedText: String,
        rawASRText: String,
        createdAt: Date = Date(),
        sourceAppName: String,
        mode: TextPolishMode,
        deliveryStatus: String,
        errorSummary: String?
    ) {
        self.id = id
        self.polishedText = polishedText
        self.rawASRText = rawASRText
        self.createdAt = createdAt
        self.sourceAppName = sourceAppName
        self.modeRawValue = mode.rawValue
        self.deliveryStatus = deliveryStatus
        self.errorSummary = errorSummary
    }

    var mode: TextPolishMode {
        TextPolishMode(rawValue: modeRawValue) ?? .clean
    }
}

@MainActor
final class DraftStore: DraftStoring {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func saveDraft(
        polishedText: String,
        rawASRText: String,
        sourceAppName: String,
        mode: TextPolishMode,
        deliveryStatus: String,
        errorSummary: String?
    ) throws {
        let record = DraftRecord(
            polishedText: polishedText,
            rawASRText: rawASRText,
            sourceAppName: sourceAppName,
            mode: mode,
            deliveryStatus: deliveryStatus,
            errorSummary: errorSummary
        )
        modelContext.insert(record)
        try modelContext.save()
    }

    func recentDrafts(limit: Int) throws -> [DraftSnapshot] {
        var descriptor = FetchDescriptor<DraftRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit

        return try modelContext.fetch(descriptor).map { record in
            DraftSnapshot(
                id: record.id,
                polishedText: record.polishedText,
                rawASRText: record.rawASRText,
                createdAt: record.createdAt,
                sourceAppName: record.sourceAppName,
                mode: record.mode,
                deliveryStatus: record.deliveryStatus,
                errorSummary: record.errorSummary
            )
        }
    }

    func deleteDraft(id: UUID) throws {
        let descriptor = FetchDescriptor<DraftRecord>(
            predicate: #Predicate { $0.id == id }
        )
        for record in try modelContext.fetch(descriptor) {
            modelContext.delete(record)
        }
        try modelContext.save()
    }
}
```

- [ ] **Step 4: Run tests**

Run:

```bash
xcodebuild test -project Fusheng.xcodeproj -scheme Fusheng -destination 'platform=macOS' -only-testing:FushengTests/DraftStoreTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Fusheng/Services/DraftStore.swift FushengTests/DraftStoreTests.swift
git commit -m "feat: add local draft storage"
```

## Task 5: Implement Text Polish Request Construction and Client

**Files:**
- Create: `Fusheng/Services/TextPolishClient.swift`
- Test: `FushengTests/TextPolishClientTests.swift`

- [ ] **Step 1: Write failing prompt and request tests**

Create `FushengTests/TextPolishClientTests.swift`:

```swift
import XCTest
@testable import Fusheng

final class TextPolishClientTests: XCTestCase {
    func testSystemPromptForCleanMode() {
        let prompt = TextPolishPrompt.systemPrompt(for: .clean)
        XCTAssertTrue(prompt.contains("保留原意"))
        XCTAssertTrue(prompt.contains("删除明显口头禅"))
    }

    func testRequestBodyDoesNotContainAPIKey() throws {
        let request = try TextPolishRequestBuilder.request(
            rawText: "嗯这个明天我们开会说",
            mode: .professional,
            model: "qwen-plus",
            apiKey: "secret-key"
        )

        let body = try XCTUnwrap(request.httpBody)
        let bodyString = String(data: body, encoding: .utf8)!

        XCTAssertEqual(request.url?.absoluteString, "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret-key")
        XCTAssertFalse(bodyString.contains("secret-key"))
        XCTAssertTrue(bodyString.contains("qwen-plus"))
        XCTAssertTrue(bodyString.contains("嗯这个明天我们开会说"))
    }
}
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
xcodebuild test -project Fusheng.xcodeproj -scheme Fusheng -destination 'platform=macOS' -only-testing:FushengTests/TextPolishClientTests
```

Expected: FAIL because `TextPolishPrompt` and `TextPolishRequestBuilder` are not defined.

- [ ] **Step 3: Add prompt and request builder**

Create `Fusheng/Services/TextPolishClient.swift`:

```swift
import Foundation

enum TextPolishPrompt {
    static func systemPrompt(for mode: TextPolishMode) -> String {
        switch mode {
        case .original:
            return "你是语音转文字清理助手。保留原意和口语表达，只补齐必要标点，不扩写。"
        case .clean:
            return "你是语音转文字清理助手。保留原意，删除明显口头禅和重复词，补充自然标点，让文本可直接发送。"
        case .professional:
            return "你是专业写作助手。保留原意，修正明显错字，删除明显口头禅，改写成清晰、正式、可直接用于需求、技术说明或会议纪要的文本。"
        case .concise:
            return "你是简洁表达助手。保留关键意思，删除冗余表达，把语音内容压缩成更短、更清楚的文本。"
        }
    }
}

enum TextPolishRequestBuilder {
    private static let endpoint = URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")!

    static func request(rawText: String, mode: TextPolishMode, model: String, apiKey: String) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ChatCompletionRequest(
            model: model,
            messages: [
                .init(role: "system", content: TextPolishPrompt.systemPrompt(for: mode)),
                .init(role: "user", content: rawText)
            ],
            temperature: 0.2
        )
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }
}

private struct ChatCompletionRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
    let temperature: Double
}

private struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String
        }

        let message: Message
    }

    let choices: [Choice]
}

struct TextPolishClient: TextPolishing {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func polish(rawText: String, mode: TextPolishMode, model: String, apiKey: String) async throws -> String {
        let request = try TextPolishRequestBuilder.request(rawText: rawText, mode: mode, model: model, apiKey: apiKey)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw AppError.polishFailed("HTTP 响应异常")
        }

        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines), !content.isEmpty else {
            throw AppError.polishFailed("模型返回空文本")
        }
        return content
    }
}
```

- [ ] **Step 4: Run tests**

Run:

```bash
xcodebuild test -project Fusheng.xcodeproj -scheme Fusheng -destination 'platform=macOS' -only-testing:FushengTests/TextPolishClientTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Fusheng/Services/TextPolishClient.swift FushengTests/TextPolishClientTests.swift
git commit -m "feat: add text polish client"
```

## Task 6: Implement DashScope ASR Event Types and WebSocket Client

**Files:**
- Create: `Fusheng/Services/DashScopeASREvents.swift`
- Create: `Fusheng/Services/DashScopeASRClient.swift`
- Modify: `Fusheng/Services/ServiceProtocols.swift`
- Test: `FushengTests/DashScopeASREventsTests.swift`

- [ ] **Step 1: Write failing ASR event tests**

Create `FushengTests/DashScopeASREventsTests.swift`:

```swift
import XCTest
@testable import Fusheng

final class DashScopeASREventsTests: XCTestCase {
    func testBuildRunTaskEvent() throws {
        let event = DashScopeASRRunTaskEvent(taskID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, model: "fun-asr-realtime")
        let data = try JSONEncoder().encode(event)
        let json = String(data: data, encoding: .utf8)!

        XCTAssertTrue(json.contains("\"action\":\"run-task\""))
        XCTAssertTrue(json.contains("\"model\":\"fun-asr-realtime\""))
        XCTAssertTrue(json.contains("\"format\":\"pcm\""))
        XCTAssertTrue(json.contains("\"sample_rate\":16000"))
    }

    func testParseResultGeneratedEvent() throws {
        let json = """
        {
          "header": { "event": "result-generated", "task_id": "task-1" },
          "payload": { "output": { "sentence": { "text": "你好世界", "sentence_end": true } } }
        }
        """

        let event = try DashScopeASRServerEvent.parse(Data(json.utf8))

        XCTAssertEqual(event, .resultGenerated(text: "你好世界", isFinalSentence: true))
    }

    func testParseTaskFinishedEvent() throws {
        let json = """
        { "header": { "event": "task-finished", "task_id": "task-1" }, "payload": {} }
        """

        let event = try DashScopeASRServerEvent.parse(Data(json.utf8))

        XCTAssertEqual(event, .taskFinished)
    }
}
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
xcodebuild test -project Fusheng.xcodeproj -scheme Fusheng -destination 'platform=macOS' -only-testing:FushengTests/DashScopeASREventsTests
```

Expected: FAIL because ASR event types are not defined.

- [ ] **Step 3: Add ASR service protocol**

Append to `Fusheng/Services/ServiceProtocols.swift`:

```swift
protocol ASRRecognizing {
    func recognize(audioChunks: AsyncThrowingStream<Data, Error>, model: String, apiKey: String) async throws -> RecognitionResult
}
```

- [ ] **Step 4: Add event models and parser**

Create `Fusheng/Services/DashScopeASREvents.swift`:

```swift
import Foundation

struct DashScopeASRRunTaskEvent: Encodable {
    struct Header: Encodable {
        let action = "run-task"
        let taskID: String
        let streaming = "duplex"

        enum CodingKeys: String, CodingKey {
            case action
            case taskID = "task_id"
            case streaming
        }
    }

    struct Payload: Encodable {
        struct Parameters: Encodable {
            let format = "pcm"
            let sampleRate = 16000

            enum CodingKeys: String, CodingKey {
                case format
                case sampleRate = "sample_rate"
            }
        }

        let taskGroup = "audio"
        let task = "asr"
        let function = "recognition"
        let model: String
        let parameters = Parameters()

        enum CodingKeys: String, CodingKey {
            case taskGroup = "task_group"
            case task
            case function
            case model
            case parameters
        }
    }

    let header: Header
    let payload: Payload

    init(taskID: UUID, model: String) {
        self.header = Header(taskID: taskID.uuidString)
        self.payload = Payload(model: model)
    }
}

struct DashScopeASRFinishTaskEvent: Encodable {
    struct Header: Encodable {
        let action = "finish-task"
        let taskID: String
        let streaming = "duplex"

        enum CodingKeys: String, CodingKey {
            case action
            case taskID = "task_id"
            case streaming
        }
    }

    let header: Header

    init(taskID: UUID) {
        self.header = Header(taskID: taskID.uuidString)
    }
}

enum DashScopeASRServerEvent: Equatable {
    case taskStarted
    case resultGenerated(text: String, isFinalSentence: Bool)
    case taskFinished
    case taskFailed(String)
    case ignored(String)

    static func parse(_ data: Data) throws -> DashScopeASRServerEvent {
        let object = try JSONSerialization.jsonObject(with: data)
        guard
            let dictionary = object as? [String: Any],
            let header = dictionary["header"] as? [String: Any],
            let eventName = header["event"] as? String
        else {
            throw AppError.asrFailed("服务端事件格式无效")
        }

        switch eventName {
        case "task-started":
            return .taskStarted
        case "result-generated":
            let payload = dictionary["payload"] as? [String: Any]
            let output = payload?["output"] as? [String: Any]
            let sentence = output?["sentence"] as? [String: Any]
            let text = sentence?["text"] as? String ?? ""
            let isFinal = sentence?["sentence_end"] as? Bool ?? false
            return .resultGenerated(text: text, isFinalSentence: isFinal)
        case "task-finished":
            return .taskFinished
        case "task-failed":
            let message = (header["error_message"] as? String) ?? "ASR 任务失败"
            return .taskFailed(message)
        default:
            return .ignored(eventName)
        }
    }
}
```

- [ ] **Step 5: Add the WebSocket client**

Create `Fusheng/Services/DashScopeASRClient.swift`:

```swift
import Foundation

struct DashScopeASRClient: ASRRecognizing {
    private let endpoint = URL(string: "wss://dashscope.aliyuncs.com/api-ws/v1/inference")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func recognize(audioChunks: AsyncThrowingStream<Data, Error>, model: String, apiKey: String) async throws -> RecognitionResult {
        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let taskID = UUID()
        let webSocket = session.webSocketTask(with: request)
        webSocket.resume()

        try await sendJSON(DashScopeASRRunTaskEvent(taskID: taskID, model: model), through: webSocket)
        try await waitForTaskStarted(from: webSocket)
        async let receiver: RecognitionResult = collectResults(from: webSocket)

        for try await chunk in audioChunks {
            try await webSocket.send(.data(chunk))
        }

        try await sendJSON(DashScopeASRFinishTaskEvent(taskID: taskID), through: webSocket)
        let result = try await receiver
        webSocket.cancel(with: .normalClosure, reason: nil)
        return result
    }

    private func sendJSON<T: Encodable>(_ value: T, through webSocket: URLSessionWebSocketTask) async throws {
        let data = try JSONEncoder().encode(value)
        guard let text = String(data: data, encoding: .utf8) else {
            throw AppError.asrFailed("ASR 控制事件编码失败")
        }
        try await webSocket.send(.string(text))
    }

    private func waitForTaskStarted(from webSocket: URLSessionWebSocketTask) async throws {
        while true {
            let event = try await receiveServerEvent(from: webSocket)
            switch event {
            case .taskStarted:
                return
            case .taskFailed(let message):
                throw AppError.asrFailed(message)
            case .ignored:
                continue
            case .resultGenerated, .taskFinished:
                continue
            }
        }
    }

    private func collectResults(from webSocket: URLSessionWebSocketTask) async throws -> RecognitionResult {
        var finalText = ""
        var partialText = ""

        while true {
            let event = try await receiveServerEvent(from: webSocket)
            switch event {
            case .taskStarted:
                continue
            case .resultGenerated(let text, let isFinalSentence):
                partialText = text
                if isFinalSentence, !text.isEmpty {
                    finalText += text
                }
            case .taskFinished:
                return RecognitionResult(rawText: finalText.isEmpty ? partialText : finalText, partialText: partialText)
            case .taskFailed(let message):
                throw AppError.asrFailed(message)
            case .ignored:
                continue
            }
        }
    }

    private func receiveServerEvent(from webSocket: URLSessionWebSocketTask) async throws -> DashScopeASRServerEvent {
        let message = try await webSocket.receive()
        let data: Data
        switch message {
        case .data(let receivedData):
            data = receivedData
        case .string(let receivedText):
            data = Data(receivedText.utf8)
        @unknown default:
            throw AppError.asrFailed("未知 WebSocket 消息类型")
        }
        return try DashScopeASRServerEvent.parse(data)
    }
}
```

- [ ] **Step 6: Run tests**

Run:

```bash
xcodebuild test -project Fusheng.xcodeproj -scheme Fusheng -destination 'platform=macOS' -only-testing:FushengTests/DashScopeASREventsTests
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Fusheng/Services/DashScopeASREvents.swift Fusheng/Services/DashScopeASRClient.swift Fusheng/Services/ServiceProtocols.swift FushengTests/DashScopeASREventsTests.swift
git commit -m "feat: add dashscope asr client"
```

## Task 7: Implement the Coordinator State Machine

**Files:**
- Modify: `Fusheng/App/AppCoordinator.swift`
- Modify: `Fusheng/Services/ServiceProtocols.swift`
- Test: `FushengTests/AppCoordinatorTests.swift`

- [ ] **Step 1: Add recorder protocol**

Append to `Fusheng/Services/ServiceProtocols.swift`:

```swift
protocol AudioRecording {
    func startRecording() throws -> AsyncThrowingStream<Data, Error>
    func stopRecording()
}
```

- [ ] **Step 2: Write failing coordinator tests**

Create `FushengTests/AppCoordinatorTests.swift`:

```swift
import XCTest
@testable import Fusheng

@MainActor
final class AppCoordinatorTests: XCTestCase {
    func testMissingAPIKeyFailsBeforeRecording() async {
        let coordinator = AppCoordinator(
            settings: FakeSettings(),
            apiKeyProvider: FakeAPIKeyProvider(apiKey: nil),
            recorder: FakeRecorder(),
            asrClient: FakeASR(text: "原始文本"),
            textPolisher: FakePolisher(text: "整理文本"),
            focusDetector: FakeFocus(.inputAvailable(appName: "Notes")),
            textInserter: FakeInserter(),
            draftStore: FakeDraftStore(),
            sourceAppProvider: FakeSourceAppProvider()
        )

        await coordinator.startRecording()

        XCTAssertEqual(coordinator.state, .failed(.missingAPIKey))
    }

    func testSuccessfulFlowPastesWhenInputAvailable() async throws {
        let inserter = FakeInserter()
        let drafts = FakeDraftStore()
        let coordinator = AppCoordinator(
            settings: FakeSettings(),
            apiKeyProvider: FakeAPIKeyProvider(apiKey: "key"),
            recorder: FakeRecorder(),
            asrClient: FakeASR(text: "原始文本"),
            textPolisher: FakePolisher(text: "整理文本"),
            focusDetector: FakeFocus(.inputAvailable(appName: "Notes")),
            textInserter: inserter,
            draftStore: drafts,
            sourceAppProvider: FakeSourceAppProvider()
        )

        await coordinator.startRecording()
        await coordinator.finishRecording()

        XCTAssertEqual(inserter.pastedTexts, ["整理文本"])
        XCTAssertEqual(drafts.savedDrafts.count, 0)
        XCTAssertEqual(coordinator.state, .completed(.pasted))
    }

    func testNoInputSavesDraft() async throws {
        let drafts = FakeDraftStore()
        let coordinator = AppCoordinator(
            settings: FakeSettings(),
            apiKeyProvider: FakeAPIKeyProvider(apiKey: "key"),
            recorder: FakeRecorder(),
            asrClient: FakeASR(text: "原始文本"),
            textPolisher: FakePolisher(text: "整理文本"),
            focusDetector: FakeFocus(.noInput(appName: "Preview")),
            textInserter: FakeInserter(),
            draftStore: drafts,
            sourceAppProvider: FakeSourceAppProvider()
        )

        await coordinator.startRecording()
        await coordinator.finishRecording()

        XCTAssertEqual(drafts.savedDrafts.map(\.polishedText), ["整理文本"])
        XCTAssertEqual(coordinator.state, .completed(.savedDraft))
    }
}

private struct FakeSettings: SettingsProviding {
    var triggerMode: TriggerMode = .toggle
    var asrModel = "fun-asr-realtime"
    var polishModel = "qwen-plus"
    var polishMode: TextPolishMode = .clean
    var autoPasteEnabled = true
    var restoreClipboardEnabled = true
    var keepDraftHistoryEnabled = true
}

private struct FakeAPIKeyProvider: APIKeyProviding {
    let apiKey: String?
    func loadAPIKey() throws -> String? { apiKey }
}

private final class FakeRecorder: AudioRecording {
    func startRecording() throws -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(Data([1, 2, 3]))
            continuation.finish()
        }
    }

    func stopRecording() {}
}

private struct FakeASR: ASRRecognizing {
    let text: String
    func recognize(audioChunks: AsyncThrowingStream<Data, Error>, model: String, apiKey: String) async throws -> RecognitionResult {
        for try await _ in audioChunks {}
        return RecognitionResult(rawText: text, partialText: text)
    }
}

private struct FakePolisher: TextPolishing {
    let text: String
    func polish(rawText: String, mode: TextPolishMode, model: String, apiKey: String) async throws -> String { text }
}

private struct FakeFocus: FocusDetecting {
    let context: FocusInputContext
    init(_ context: FocusInputContext) { self.context = context }
    func focusedInputContext() -> FocusInputContext { context }
}

private final class FakeInserter: TextInserting {
    var pastedTexts: [String] = []
    func paste(text: String, restoreClipboard: Bool) async throws {
        pastedTexts.append(text)
    }
}

private final class FakeDraftStore: DraftStoring {
    struct SavedDraft {
        let polishedText: String
    }

    var savedDrafts: [SavedDraft] = []

    func saveDraft(polishedText: String, rawASRText: String, sourceAppName: String, mode: TextPolishMode, deliveryStatus: String, errorSummary: String?) throws {
        savedDrafts.append(SavedDraft(polishedText: polishedText))
    }

    func recentDrafts(limit: Int) throws -> [DraftSnapshot] { [] }
    func deleteDraft(id: UUID) throws {}
}

private struct FakeSourceAppProvider: SourceAppProviding {
    func currentAppName() -> String { "TestApp" }
}
```

- [ ] **Step 3: Run coordinator tests and verify failure**

Run:

```bash
xcodebuild test -project Fusheng.xcodeproj -scheme Fusheng -destination 'platform=macOS' -only-testing:FushengTests/AppCoordinatorTests
```

Expected: FAIL because `AppCoordinator` has no dependency-injected initializer or async workflow methods.

- [ ] **Step 4: Replace AppCoordinator with dependency-injected state machine**

Replace `Fusheng/App/AppCoordinator.swift`:

```swift
import Foundation

@MainActor
final class AppCoordinator: ObservableObject {
    @Published private(set) var state: AppWorkflowState = .idle
    @Published private(set) var latestPartialText = ""

    private var settings: SettingsProviding
    private let apiKeyProvider: APIKeyProviding
    private let recorder: AudioRecording?
    private let asrClient: ASRRecognizing?
    private let textPolisher: TextPolishing?
    private let focusDetector: FocusDetecting?
    private let textInserter: TextInserting?
    private let draftStore: DraftStoring?
    private let sourceAppProvider: SourceAppProviding?
    private var currentAudioChunks: AsyncThrowingStream<Data, Error>?
    private var apiKeyForCurrentRun: String?

    init(
        settings: SettingsProviding = SettingsStore(),
        apiKeyProvider: APIKeyProviding = KeychainService(),
        recorder: AudioRecording? = nil,
        asrClient: ASRRecognizing? = nil,
        textPolisher: TextPolishing? = nil,
        focusDetector: FocusDetecting? = nil,
        textInserter: TextInserting? = nil,
        draftStore: DraftStoring? = nil,
        sourceAppProvider: SourceAppProviding? = nil
    ) {
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
        default:
            state = .recording(startedAt: Date())
        }
    }

    func startRecording() async {
        do {
            guard let apiKey = try apiKeyProvider.loadAPIKey(), !apiKey.isEmpty else {
                state = .failed(.missingAPIKey)
                return
            }
            guard let recorder else {
                state = .failed(.recorderFailed("录音服务未初始化"))
                return
            }

            apiKeyForCurrentRun = apiKey
            currentAudioChunks = try recorder.startRecording()
            state = .recording(startedAt: Date())
        } catch let error as AppError {
            state = .failed(error)
        } catch {
            state = .failed(.recorderFailed(error.localizedDescription))
        }
    }

    func finishRecording() async {
        guard let audioChunks = currentAudioChunks, let apiKey = apiKeyForCurrentRun else {
            state = .failed(.recorderFailed("没有正在进行的录音"))
            return
        }
        recorder?.stopRecording()

        do {
            guard let asrClient, let textPolisher else {
                state = .failed(.asrFailed("识别服务未初始化"))
                return
            }

            state = .recognizing
            let recognition = try await asrClient.recognize(audioChunks: audioChunks, model: settings.asrModel, apiKey: apiKey)
            latestPartialText = recognition.partialText

            state = .polishing
            let polishedText = try await textPolisher.polish(
                rawText: recognition.rawText,
                mode: settings.polishMode,
                model: settings.polishModel,
                apiKey: apiKey
            )

            state = .delivering
            try await deliver(polishedText: polishedText, rawText: recognition.rawText)
        } catch let error as AppError {
            state = .failed(error)
        } catch {
            state = .failed(.asrFailed(error.localizedDescription))
        }
    }

    private func deliver(polishedText: String, rawText: String) async throws {
        let context = focusDetector?.focusedInputContext() ?? .noInput(appName: sourceAppProvider?.currentAppName() ?? "未知 App")

        switch context {
        case .inputAvailable where settings.autoPasteEnabled:
            do {
                try await textInserter?.paste(text: polishedText, restoreClipboard: settings.restoreClipboardEnabled)
                state = .completed(.pasted)
            } catch {
                try saveDraft(polishedText: polishedText, rawText: rawText, status: "pasteFailed", errorSummary: error.localizedDescription)
                state = .completed(.savedDraft)
            }
        case .inputAvailable:
            try saveDraft(polishedText: polishedText, rawText: rawText, status: "autoPasteDisabled", errorSummary: nil)
            state = .completed(.savedDraft)
        case .noInput(let appName):
            try saveDraft(polishedText: polishedText, rawText: rawText, status: "noInput:\(appName)", errorSummary: nil)
            state = .completed(.savedDraft)
        case .accessibilityPermissionMissing(let appName):
            try saveDraft(polishedText: polishedText, rawText: rawText, status: "accessibilityMissing:\(appName)", errorSummary: AppError.accessibilityPermissionDenied.localizedDescription)
            state = .completed(.savedDraft)
        }
    }

    private func saveDraft(polishedText: String, rawText: String, status: String, errorSummary: String?) throws {
        guard settings.keepDraftHistoryEnabled else { return }
        try draftStore?.saveDraft(
            polishedText: polishedText,
            rawASRText: rawText,
            sourceAppName: sourceAppProvider?.currentAppName() ?? "未知 App",
            mode: settings.polishMode,
            deliveryStatus: status,
            errorSummary: errorSummary
        )
    }
}
```

- [ ] **Step 5: Run coordinator tests**

Run:

```bash
xcodebuild test -project Fusheng.xcodeproj -scheme Fusheng -destination 'platform=macOS' -only-testing:FushengTests/AppCoordinatorTests
```

Expected: PASS.

- [ ] **Step 6: Run full test suite**

Run:

```bash
xcodebuild test -project Fusheng.xcodeproj -scheme Fusheng -destination 'platform=macOS'
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Fusheng/App/AppCoordinator.swift Fusheng/Services/ServiceProtocols.swift FushengTests/AppCoordinatorTests.swift
git commit -m "feat: add voice workflow coordinator"
```

## Task 8: Build Menu, Settings, Draft History, and Overlay UI

**Files:**
- Modify: `Fusheng/App/FushengApp.swift`
- Modify: `Fusheng/UI/RootMenuContent.swift`
- Create: `Fusheng/UI/SettingsView.swift`
- Create: `Fusheng/UI/DraftHistoryView.swift`
- Create: `Fusheng/UI/RecordingOverlayView.swift`

- [ ] **Step 1: Replace the app shell with SwiftData and settings windows**

Replace `Fusheng/App/FushengApp.swift`:

```swift
import SwiftData
import SwiftUI

@main
struct FushengApp: App {
    @StateObject private var coordinator = AppCoordinator()

    var body: some Scene {
        MenuBarExtra("浮声", systemImage: coordinator.menuBarSystemImage) {
            RootMenuContent()
                .environmentObject(coordinator)
                .modelContainer(for: DraftRecord.self)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environmentObject(coordinator)
                .frame(width: 520, height: 520)
        }

        Window("草稿历史", id: "draft-history") {
            DraftHistoryView()
                .modelContainer(for: DraftRecord.self)
                .frame(width: 720, height: 520)
        }

        Window("录音状态", id: "recording-overlay") {
            RecordingOverlayView()
                .environmentObject(coordinator)
                .frame(width: 280, height: 120)
        }
    }
}
```

- [ ] **Step 2: Implement menu content**

Replace `Fusheng/UI/RootMenuContent.swift`:

```swift
import SwiftData
import SwiftUI

struct RootMenuContent: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.openWindow) private var openWindow
    @Query(sort: \DraftRecord.createdAt, order: .reverse) private var drafts: [DraftRecord]

    var body: some View {
        VStack(alignment: .leading) {
            Text("状态：\(coordinator.statusText)")

            Button("开始/停止录音") {
                Task {
                    if case .recording = coordinator.state {
                        await coordinator.finishRecording()
                    } else {
                        await coordinator.startRecording()
                    }
                }
            }

            Divider()

            if drafts.isEmpty {
                Text("暂无草稿")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(drafts.prefix(5)) { draft in
                    Button(draft.polishedText.prefix(24).description) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(draft.polishedText, forType: .string)
                    }
                }
            }

            Divider()

            Button("打开草稿历史") {
                openWindow(id: "draft-history")
            }

            Button("打开设置") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }

            Button("退出") {
                NSApp.terminate(nil)
            }
        }
        .padding(.vertical, 6)
    }
}
```

- [ ] **Step 3: Implement settings UI**

Create `Fusheng/UI/SettingsView.swift`:

```swift
import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    static let voiceInput = Self("voiceInput")
}

struct SettingsView: View {
    @State private var settings = SettingsStore()
    @State private var apiKey = ""
    @State private var keychainMessage = ""
    private let keychain = KeychainService()

    var body: some View {
        Form {
            Section("阿里百炼") {
                SecureField("API Key", text: $apiKey)
                Button("保存 API Key") {
                    do {
                        try keychain.saveAPIKey(apiKey)
                        keychainMessage = "API Key 已保存"
                    } catch {
                        keychainMessage = error.localizedDescription
                    }
                }
                Text(keychainMessage).foregroundStyle(.secondary)
            }

            Section("模型") {
                TextField("ASR 模型", text: Binding(get: { settings.asrModel }, set: { settings.asrModel = $0 }))
                TextField("整理模型", text: Binding(get: { settings.polishModel }, set: { settings.polishModel = $0 }))
                Picker("整理模式", selection: Binding(get: { settings.polishMode }, set: { settings.polishMode = $0 })) {
                    ForEach(TextPolishMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
            }

            Section("快捷键") {
                KeyboardShortcuts.Recorder("语音输入", name: .voiceInput)
                Picker("触发方式", selection: Binding(get: { settings.triggerMode }, set: { settings.triggerMode = $0 })) {
                    ForEach(TriggerMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
            }

            Section("输出") {
                Toggle("自动粘贴到当前输入框", isOn: Binding(get: { settings.autoPasteEnabled }, set: { settings.autoPasteEnabled = $0 }))
                Toggle("粘贴后恢复剪贴板", isOn: Binding(get: { settings.restoreClipboardEnabled }, set: { settings.restoreClipboardEnabled = $0 }))
                Toggle("保留历史草稿", isOn: Binding(get: { settings.keepDraftHistoryEnabled }, set: { settings.keepDraftHistoryEnabled = $0 }))
            }
        }
        .padding()
        .onAppear {
            apiKey = (try? keychain.loadAPIKey()) ?? ""
        }
    }
}
```

- [ ] **Step 4: Implement draft history UI**

Create `Fusheng/UI/DraftHistoryView.swift`:

```swift
import SwiftData
import SwiftUI

struct DraftHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DraftRecord.createdAt, order: .reverse) private var drafts: [DraftRecord]
    @State private var searchText = ""

    private var filteredDrafts: [DraftRecord] {
        guard !searchText.isEmpty else { return drafts }
        return drafts.filter {
            $0.polishedText.localizedCaseInsensitiveContains(searchText) ||
            $0.rawASRText.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack {
            TextField("搜索草稿", text: $searchText)
                .textFieldStyle(.roundedBorder)

            List(filteredDrafts) { draft in
                VStack(alignment: .leading, spacing: 8) {
                    Text(draft.polishedText)
                    Text(draft.createdAt.formatted())
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Button("复制") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(draft.polishedText, forType: .string)
                        }

                        Button("删除") {
                            modelContext.delete(draft)
                            try? modelContext.save()
                        }
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .padding()
    }
}
```

- [ ] **Step 5: Implement recording overlay**

Create `Fusheng/UI/RecordingOverlayView.swift`:

```swift
import SwiftUI

struct RecordingOverlayView: View {
    @EnvironmentObject private var coordinator: AppCoordinator

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: coordinator.menuBarSystemImage)
                .font(.system(size: 32))
            Text(coordinator.statusText)
                .font(.headline)
            if !coordinator.latestPartialText.isEmpty {
                Text(coordinator.latestPartialText)
                    .font(.caption)
                    .lineLimit(2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}
```

- [ ] **Step 6: Build**

Run:

```bash
xcodebuild build -project Fusheng.xcodeproj -scheme Fusheng -destination 'platform=macOS'
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 7: Commit**

```bash
git add Fusheng/App/FushengApp.swift Fusheng/UI
git commit -m "feat: add menu settings and draft UI"
```

## Task 9: Implement Hotkeys and Audio Recording

**Files:**
- Create: `Fusheng/Services/HotkeyService.swift`
- Create: `Fusheng/Services/AudioRecorder.swift`
- Modify: `Fusheng/App/FushengApp.swift`

- [ ] **Step 1: Add HotkeyService**

Create `Fusheng/Services/HotkeyService.swift`:

```swift
import Foundation
import KeyboardShortcuts

@MainActor
final class HotkeyService {
    private let settings: SettingsProviding
    private let onStart: () -> Void
    private let onFinish: () -> Void

    init(settings: SettingsProviding, onStart: @escaping () -> Void, onFinish: @escaping () -> Void) {
        self.settings = settings
        self.onStart = onStart
        self.onFinish = onFinish
    }

    func start() {
        KeyboardShortcuts.onKeyDown(for: .voiceInput) { [weak self] in
            guard let self else { return }
            switch self.settings.triggerMode {
            case .toggle:
                self.onStart()
            case .hold:
                self.onStart()
            }
        }

        KeyboardShortcuts.onKeyUp(for: .voiceInput) { [weak self] in
            guard let self else { return }
            if self.settings.triggerMode == .hold {
                self.onFinish()
            }
        }
    }
}
```

- [ ] **Step 2: Add AudioRecorder**

Create `Fusheng/Services/AudioRecorder.swift`:

```swift
import AVFoundation
import Foundation

final class AudioRecorder: AudioRecording {
    private let engine = AVAudioEngine()
    private var continuation: AsyncThrowingStream<Data, Error>.Continuation?

    func startRecording() throws -> AsyncThrowingStream<Data, Error> {
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard let outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true) else {
            throw AppError.recorderFailed("无法创建 16 kHz PCM 格式")
        }
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw AppError.recorderFailed("无法创建音频格式转换器")
        }

        let stream = AsyncThrowingStream<Data, Error> { continuation in
            self.continuation = continuation
        }

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            do {
                let converted = try self.convert(buffer: buffer, converter: converter, outputFormat: outputFormat)
                self.continuation?.yield(converted)
            } catch {
                self.continuation?.finish(throwing: error)
            }
        }

        engine.prepare()
        try engine.start()
        return stream
    }

    func stopRecording() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        continuation?.finish()
        continuation = nil
    }

    private func convert(buffer: AVAudioPCMBuffer, converter: AVAudioConverter, outputFormat: AVAudioFormat) throws -> Data {
        let frameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * outputFormat.sampleRate / buffer.format.sampleRate)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameCapacity) else {
            throw AppError.recorderFailed("无法创建输出音频缓冲")
        }

        var error: NSError?
        var didProvideInput = false
        let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if didProvideInput {
                outStatus.pointee = .noDataNow
                return nil
            }
            didProvideInput = true
            outStatus.pointee = .haveData
            return buffer
        }

        if let error {
            throw AppError.recorderFailed(error.localizedDescription)
        }
        guard status != .error else {
            throw AppError.recorderFailed("音频转换失败")
        }
        guard let channelData = outputBuffer.int16ChannelData else {
            throw AppError.recorderFailed("PCM 数据为空")
        }

        let frameLength = Int(outputBuffer.frameLength)
        return Data(bytes: channelData[0], count: frameLength * MemoryLayout<Int16>.size)
    }
}
```

- [ ] **Step 3: Wire concrete services into app startup**

Modify `Fusheng/App/FushengApp.swift` so the coordinator is created by an initializer:

```swift
import SwiftData
import SwiftUI

@main
struct FushengApp: App {
    @StateObject private var coordinator: AppCoordinator
    @State private var hotkeyService: HotkeyService?

    init() {
        let settings = SettingsStore()
        let coordinator = AppCoordinator(
            settings: settings,
            apiKeyProvider: KeychainService(),
            recorder: AudioRecorder(),
            asrClient: DashScopeASRClient(),
            textPolisher: TextPolishClient(),
            focusDetector: nil,
            textInserter: nil,
            draftStore: nil,
            sourceAppProvider: nil
        )
        _coordinator = StateObject(wrappedValue: coordinator)
    }

    var body: some Scene {
        MenuBarExtra("浮声", systemImage: coordinator.menuBarSystemImage) {
            RootMenuContent()
                .environmentObject(coordinator)
                .modelContainer(for: DraftRecord.self)
                .task {
                    if hotkeyService == nil {
                        let service = HotkeyService(settings: SettingsStore()) {
                            Task { await coordinator.startRecording() }
                        } onFinish: {
                            Task { await coordinator.finishRecording() }
                        }
                        service.start()
                        hotkeyService = service
                    }
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
                .modelContainer(for: DraftRecord.self)
                .frame(width: 720, height: 520)
        }

        Window("录音状态", id: "recording-overlay") {
            RecordingOverlayView()
                .environmentObject(coordinator)
                .frame(width: 280, height: 120)
        }
    }
}
```

- [ ] **Step 4: Build**

Run:

```bash
xcodebuild build -project Fusheng.xcodeproj -scheme Fusheng -destination 'platform=macOS'
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add Fusheng/Services/HotkeyService.swift Fusheng/Services/AudioRecorder.swift Fusheng/App/FushengApp.swift
git commit -m "feat: add hotkeys and audio recorder"
```

## Task 10: Implement Focus Detection and Text Insertion

**Files:**
- Create: `Fusheng/Services/FocusDetector.swift`
- Create: `Fusheng/Services/TextInsertionService.swift`
- Modify: `Fusheng/App/FushengApp.swift`

- [ ] **Step 1: Add focus detector**

Create `Fusheng/Services/FocusDetector.swift`:

```swift
import AppKit
import ApplicationServices
import Foundation

struct FocusDetector: FocusDetecting, SourceAppProviding {
    func focusedInputContext() -> FocusInputContext {
        let appName = currentAppName()
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: false] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            return .accessibilityPermissionMissing(appName: appName)
        }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedValue: AnyObject?
        let focusedStatus = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedValue)
        guard focusedStatus == .success, let focusedElement = focusedValue else {
            return .noInput(appName: appName)
        }

        var roleValue: AnyObject?
        AXUIElementCopyAttributeValue(focusedElement as! AXUIElement, kAXRoleAttribute as CFString, &roleValue)
        let role = roleValue as? String

        let textRoles = [
            kAXTextFieldRole as String,
            kAXTextAreaRole as String,
            kAXComboBoxRole as String
        ]

        if let role, textRoles.contains(role) {
            return .inputAvailable(appName: appName)
        }

        var selectedTextRange: AnyObject?
        let rangeStatus = AXUIElementCopyAttributeValue(focusedElement as! AXUIElement, kAXSelectedTextRangeAttribute as CFString, &selectedTextRange)
        if rangeStatus == .success {
            return .inputAvailable(appName: appName)
        }

        return .noInput(appName: appName)
    }

    func currentAppName() -> String {
        NSWorkspace.shared.frontmostApplication?.localizedName ?? "未知 App"
    }
}
```

- [ ] **Step 2: Add text insertion service**

Create `Fusheng/Services/TextInsertionService.swift`:

```swift
import AppKit
import Foundation

struct TextInsertionService: TextInserting {
    func paste(text: String, restoreClipboard: Bool) async throws {
        let pasteboard = NSPasteboard.general
        let previousItems = pasteboard.pasteboardItems

        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            throw AppError.insertionFailed("无法写入剪贴板")
        }

        guard
            let source = CGEventSource(stateID: .hidSystemState),
            let commandDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true),
            let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
            let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false),
            let commandUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)
        else {
            throw AppError.insertionFailed("无法创建粘贴事件")
        }

        vDown.flags = .maskCommand
        vUp.flags = .maskCommand
        commandDown.post(tap: .cghidEventTap)
        vDown.post(tap: .cghidEventTap)
        vUp.post(tap: .cghidEventTap)
        commandUp.post(tap: .cghidEventTap)

        if restoreClipboard {
            try await Task.sleep(nanoseconds: 250_000_000)
            pasteboard.clearContents()
            if let previousItems {
                pasteboard.writeObjects(previousItems)
            }
        }
    }
}
```

- [ ] **Step 3: Wire concrete focus and insertion services**

Modify the `AppCoordinator` creation in `Fusheng/App/FushengApp.swift`:

```swift
let focusDetector = FocusDetector()
let coordinator = AppCoordinator(
    settings: settings,
    apiKeyProvider: KeychainService(),
    recorder: AudioRecorder(),
    asrClient: DashScopeASRClient(),
    textPolisher: TextPolishClient(),
    focusDetector: focusDetector,
    textInserter: TextInsertionService(),
    draftStore: nil,
    sourceAppProvider: focusDetector
)
```

- [ ] **Step 4: Build**

Run:

```bash
xcodebuild build -project Fusheng.xcodeproj -scheme Fusheng -destination 'platform=macOS'
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add Fusheng/Services/FocusDetector.swift Fusheng/Services/TextInsertionService.swift Fusheng/App/FushengApp.swift
git commit -m "feat: add focus detection and paste insertion"
```

## Task 11: Wire SwiftData DraftStore Into the Coordinator

**Files:**
- Modify: `Fusheng/App/FushengApp.swift`
- Modify: `Fusheng/App/AppCoordinator.swift`

- [ ] **Step 1: Add runtime draft store injection**

Modify `Fusheng/App/FushengApp.swift` to create a shared `ModelContainer` and inject `DraftStore`:

```swift
import SwiftData
import SwiftUI

@main
struct FushengApp: App {
    @StateObject private var coordinator: AppCoordinator
    @State private var hotkeyService: HotkeyService?
    private let modelContainer: ModelContainer

    init() {
        let container = try! ModelContainer(for: DraftRecord.self)
        self.modelContainer = container

        let settings = SettingsStore()
        let focusDetector = FocusDetector()
        let coordinator = AppCoordinator(
            settings: settings,
            apiKeyProvider: KeychainService(),
            recorder: AudioRecorder(),
            asrClient: DashScopeASRClient(),
            textPolisher: TextPolishClient(),
            focusDetector: focusDetector,
            textInserter: TextInsertionService(),
            draftStore: DraftStore(modelContext: container.mainContext),
            sourceAppProvider: focusDetector
        )
        _coordinator = StateObject(wrappedValue: coordinator)
    }

    var body: some Scene {
        MenuBarExtra("浮声", systemImage: coordinator.menuBarSystemImage) {
            RootMenuContent()
                .environmentObject(coordinator)
                .modelContainer(modelContainer)
                .task {
                    if hotkeyService == nil {
                        let service = HotkeyService(settings: SettingsStore()) {
                            Task { await coordinator.startRecording() }
                        } onFinish: {
                            Task { await coordinator.finishRecording() }
                        }
                        service.start()
                        hotkeyService = service
                    }
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
                .modelContainer(modelContainer)
                .frame(width: 720, height: 520)
        }

        Window("录音状态", id: "recording-overlay") {
            RecordingOverlayView()
                .environmentObject(coordinator)
                .frame(width: 280, height: 120)
        }
    }
}
```

- [ ] **Step 2: Prevent duplicate start calls in hold mode**

Modify `startRecording()` in `Fusheng/App/AppCoordinator.swift` by adding this guard at the top:

```swift
if case .recording = state {
    return
}
```

- [ ] **Step 3: Build and test**

Run:

```bash
xcodebuild test -project Fusheng.xcodeproj -scheme Fusheng -destination 'platform=macOS'
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add Fusheng/App/FushengApp.swift Fusheng/App/AppCoordinator.swift
git commit -m "feat: wire runtime draft storage"
```

## Task 12: End-to-End Runtime Verification

**Files:**
- Modify: `docs/superpowers/plans/2026-06-16-fusheng-macos-mvp.md`

- [ ] **Step 1: Run full automated tests**

Run:

```bash
xcodebuild test -project Fusheng.xcodeproj -scheme Fusheng -destination 'platform=macOS'
```

Expected: PASS.

- [ ] **Step 2: Launch the app from Xcode build output**

Run:

```bash
xcodebuild build -project Fusheng.xcodeproj -scheme Fusheng -destination 'platform=macOS'
open "$(find ~/Library/Developer/Xcode/DerivedData -path '*/Build/Products/Debug/Fusheng.app' -print -quit)"
```

Expected: a menu bar item named 浮声 appears.

- [ ] **Step 3: Manual verification checklist**

Record results directly under this task in the plan file using this format:

```markdown
Manual verification on 2026-06-16:
- App launches and shows menu bar item: pass
- API Key saves and reloads from Keychain: pass
- Toggle trigger starts and finishes recording: pass
- Hold trigger starts on key down and finishes on key up: pass
- Real DashScope ASR returns Chinese text: pass
- Text polish returns cleaned text: pass
- Focused text input receives pasted text: pass
- No focused text input creates draft: pass
- Draft copy works: pass
- Draft delete works: pass
- API Key is absent from logs: pass
```

- [ ] **Step 4: Commit verification notes**

```bash
git add docs/superpowers/plans/2026-06-16-fusheng-macos-mvp.md
git commit -m "test: record fusheng mvp verification"
```

## Self-Review Notes

- Spec coverage: project setup, settings, Keychain, SwiftData drafts, menu UI, settings UI, hotkeys, audio recording, DashScope ASR, text polish, focus detection, paste insertion, coordinator state machine, and verification are all mapped to tasks.
- Placeholder scan: this plan uses concrete files, code snippets, commands, and expected results.
- Type consistency: shared names are `AppWorkflowState`, `AppError`, `TextPolishMode`, `TriggerMode`, `SettingsStore`, `KeychainService`, `DraftRecord`, `DraftStore`, `DashScopeASRClient`, `TextPolishClient`, `FocusDetector`, `TextInsertionService`, and `AppCoordinator`.
