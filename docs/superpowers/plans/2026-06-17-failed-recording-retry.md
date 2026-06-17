# Failed Recording Retry Queue Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an independent “失败录音” retry queue so ASR/LLM interface failures preserve the recorded audio and can be retried manually.

**Architecture:** Keep normal text drafts and retryable failed recordings separate. SwiftData stores retry task metadata, a file-store service owns local PCM files, `AppCoordinator` creates failed recording tasks only for ASR/LLM interface failures, and `FailedRecordingRetryService` handles manual retries without putting network logic in SwiftUI views.

**Tech Stack:** Swift 5.10, SwiftUI, SwiftData, AVFoundation PCM audio, URLSession WebSocket ASR client, DashScope chat completions client, XcodeGen, XCTest.

---

## Spec Reference

Implement the approved design in:

`docs/superpowers/specs/2026-06-17-failed-recording-retry-design.md`

## File Structure

- Create `Fusheng/Core/FailedRecordingModels.swift`
  - Defines `FailedRecordingStage`, `FailedRecordingRetryState`, and `FailedRecordingSnapshot`.
- Modify `Fusheng/Core/AppModels.swift`
  - Adds `Notification.Name.failedRecordingQueueDidChange`.
- Modify `Fusheng/Services/ServiceProtocols.swift`
  - Adds `FailedRecordingStoring`, `FailedRecordingAudioStoring`, and `FailedRecordingAudioWriting`.
- Create `Fusheng/Services/FailedRecordingStore.swift`
  - SwiftData `FailedRecordingRecord` and store implementation.
- Create `Fusheng/Services/FailedRecordingAudioStore.swift`
  - Local PCM file writer, reader, delete, and file-existence logic.
- Create `Fusheng/Services/AudioStreamTee.swift`
  - Wraps an `AsyncThrowingStream<Data, Error>` and writes every chunk to a local writer while yielding it downstream.
- Modify `Fusheng/App/AppCoordinator.swift`
  - Creates an audio writer per recording, wraps the ASR stream, saves failed recording tasks on ASR/LLM failures, cleans audio on success/non-interface failures.
- Create `Fusheng/Services/FailedRecordingRetryService.swift`
  - Retries failed recordings from ASR or LLM stage and handles success/failure side effects.
- Create `Fusheng/UI/FailedRecordingView.swift`
  - Shows the failed recording queue and exposes retry/delete actions.
- Modify `Fusheng/App/FushengApp.swift`
  - Adds `FailedRecordingRecord` to the model container, creates failed recording services, adds the failed recording window.
- Modify `Fusheng/UI/RootMenuContent.swift`
  - Adds “打开失败录音” menu entry and window-fronting behavior.
- Modify `project.yml`
  - Preserve current signing/audio settings and the source snapshot script when regenerating the project.
- Create tests:
  - `FushengTests/FailedRecordingModelsTests.swift`
  - `FushengTests/FailedRecordingStoreTests.swift`
  - `FushengTests/FailedRecordingAudioStoreTests.swift`
  - `FushengTests/AudioStreamTeeTests.swift`
  - `FushengTests/FailedRecordingRetryServiceTests.swift`
- Modify tests:
  - `FushengTests/AppCoordinatorTests.swift`
  - `FushengTests/AppBundleConfigurationTests.swift`

Use XcodeGen after file additions:

```bash
xcodegen generate
```

This repo already has `project.yml` and `/opt/homebrew/bin/xcodegen`. The plan first updates `project.yml` so generation does not drop current custom settings.

---

### Task 1: Preserve Project Generation Settings

**Files:**
- Modify: `project.yml`
- Verify: `Fusheng.xcodeproj/project.pbxproj`
- Test: `FushengTests/AppBundleConfigurationTests.swift`

- [ ] **Step 1: Write the failing source-snapshot configuration test**

Add this test to `FushengTests/AppBundleConfigurationTests.swift`:

```swift
func testProjectYMLPreservesGeneratedProjectRequirements() throws {
    let source = try String(
        contentsOf: try projectFileURL("project.yml"),
        encoding: .utf8
    )

    XCTAssertTrue(source.contains("ENABLE_RESOURCE_ACCESS_AUDIO_INPUT: YES"))
    XCTAssertTrue(source.contains("Copy source snapshot"))
    XCTAssertTrue(source.contains("Fusheng/App/FushengApp.swift"))
    XCTAssertTrue(source.contains("Fusheng/UI/RootMenuContent.swift"))
    XCTAssertTrue(source.contains("Fusheng.xcodeproj/project.pbxproj"))
}
```

- [ ] **Step 2: Run the test and verify it fails**

Run:

```bash
xcodebuild test -project Fusheng.xcodeproj -scheme Fusheng -destination 'platform=macOS' -only-testing:FushengTests/AppBundleConfigurationTests/testProjectYMLPreservesGeneratedProjectRequirements
```

Expected: FAIL because `project.yml` does not yet contain `ENABLE_RESOURCE_ACCESS_AUDIO_INPUT` or the source snapshot script.

- [ ] **Step 3: Update `project.yml`**

Change the `Fusheng` target settings to include:

```yaml
        ENABLE_RESOURCE_ACCESS_AUDIO_INPUT: YES
```

Add this under `targets.FushengTests`:

```yaml
    preBuildScripts:
      - name: Copy source snapshot
        basedOnDependencyAnalysis: false
        script: |
          set -euo pipefail

          DESTINATION="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/SourceSnapshot"
          rm -rf "$DESTINATION"
          mkdir -p "$DESTINATION"

          copy_item() {
            source_path="$SRCROOT/$1"
            destination_path="$DESTINATION/$1"
            mkdir -p "$(dirname "$destination_path")"
            /usr/bin/ditto "$source_path" "$destination_path"
          }

          copy_item "Fusheng/App/FushengApp.swift"
          copy_item "Fusheng/App/AppLaunchDelegate.swift"
          copy_item "Fusheng/App/SettingsWindowController.swift"
          copy_item "Fusheng/UI/RootMenuContent.swift"
          copy_item "Fusheng/UI/SettingsView.swift"
          copy_item "Fusheng/Services/HotkeyService.swift"
          copy_item "Fusheng/UI/RecordingOverlayView.swift"
          copy_item "Fusheng/Resources/Info.plist"
          copy_item "Fusheng/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json"
          copy_item "Fusheng/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-512@2x.png"
          copy_item "Fusheng.xcodeproj/project.pbxproj"
```

- [ ] **Step 4: Run the focused test again**

Run:

```bash
xcodebuild test -project Fusheng.xcodeproj -scheme Fusheng -destination 'platform=macOS' -only-testing:FushengTests/AppBundleConfigurationTests/testProjectYMLPreservesGeneratedProjectRequirements
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add project.yml FushengTests/AppBundleConfigurationTests.swift
git commit -m "test: preserve generated project settings"
```

---

### Task 2: Failed Recording Models

**Files:**
- Create: `Fusheng/Core/FailedRecordingModels.swift`
- Modify: `Fusheng/Core/AppModels.swift`
- Modify: `Fusheng/Services/ServiceProtocols.swift`
- Create: `FushengTests/FailedRecordingModelsTests.swift`

- [ ] **Step 1: Write failing model tests**

Create `FushengTests/FailedRecordingModelsTests.swift`:

```swift
import XCTest
@testable import Fusheng

final class FailedRecordingModelsTests: XCTestCase {
    func testStageDisplayText() {
        XCTAssertEqual(FailedRecordingStage.asr.displayText, "识别失败")
        XCTAssertEqual(FailedRecordingStage.polish.displayText, "整理失败")
    }

    func testRetryStateDisplayText() {
        XCTAssertEqual(FailedRecordingRetryState.idle.displayText, "待重试")
        XCTAssertEqual(FailedRecordingRetryState.retrying.displayText, "重试中")
        XCTAssertEqual(FailedRecordingRetryState.failed.displayText, "重试失败")
    }

    func testFailedRecordingSnapshotStoresRetryMetadata() {
        let date = Date(timeIntervalSince1970: 10)
        let snapshot = FailedRecordingSnapshot(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            createdAt: date,
            sourceAppName: "Notes",
            mode: .clean,
            asrModel: "fun-asr-realtime",
            polishModel: "qwen-plus",
            failureStage: .polish,
            errorSummary: "请求失败",
            audioFilePath: "/tmp/audio.pcm",
            rawASRText: "原始文本",
            retryState: .failed,
            lastRetryAt: date
        )

        XCTAssertEqual(snapshot.sourceAppName, "Notes")
        XCTAssertEqual(snapshot.failureStage, .polish)
        XCTAssertEqual(snapshot.rawASRText, "原始文本")
        XCTAssertEqual(snapshot.retryState, .failed)
    }
}
```

- [ ] **Step 2: Run the test and verify it fails**

Run:

```bash
xcodebuild test -project Fusheng.xcodeproj -scheme Fusheng -destination 'platform=macOS' -only-testing:FushengTests/FailedRecordingModelsTests
```

Expected: FAIL because `FailedRecordingStage`, `FailedRecordingRetryState`, and `FailedRecordingSnapshot` do not exist.

- [ ] **Step 3: Add model code**

Create `Fusheng/Core/FailedRecordingModels.swift`:

```swift
import Foundation

enum FailedRecordingStage: String, Codable, Equatable {
    case asr
    case polish

    var displayText: String {
        switch self {
        case .asr:
            return "识别失败"
        case .polish:
            return "整理失败"
        }
    }
}

enum FailedRecordingRetryState: String, Codable, Equatable {
    case idle
    case retrying
    case failed

    var displayText: String {
        switch self {
        case .idle:
            return "待重试"
        case .retrying:
            return "重试中"
        case .failed:
            return "重试失败"
        }
    }
}

struct FailedRecordingSnapshot: Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    let sourceAppName: String
    let mode: TextPolishMode
    let asrModel: String
    let polishModel: String
    let failureStage: FailedRecordingStage
    let errorSummary: String
    let audioFilePath: String
    let rawASRText: String
    let retryState: FailedRecordingRetryState
    let lastRetryAt: Date?
}
```

Modify `Fusheng/Core/AppModels.swift`:

```swift
extension Notification.Name {
    static let audioLevelDidChange = Notification.Name("FushengAudioLevelDidChange")
    static let draftHistoryDidChange = Notification.Name("FushengDraftHistoryDidChange")
    static let speechHotkeyDidChange = Notification.Name("FushengSpeechHotkeyDidChange")
    static let failedRecordingQueueDidChange = Notification.Name("FushengFailedRecordingQueueDidChange")
}
```

Modify `Fusheng/Services/ServiceProtocols.swift` by adding:

```swift
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
```

- [ ] **Step 4: Regenerate project and run model tests**

Run:

```bash
xcodegen generate
xcodebuild test -project Fusheng.xcodeproj -scheme Fusheng -destination 'platform=macOS' -only-testing:FushengTests/FailedRecordingModelsTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add project.yml Fusheng.xcodeproj Fusheng/Core/AppModels.swift Fusheng/Core/FailedRecordingModels.swift Fusheng/Services/ServiceProtocols.swift FushengTests/FailedRecordingModelsTests.swift
git commit -m "feat: add failed recording models"
```

---

### Task 3: Failed Recording SwiftData Store

**Files:**
- Create: `Fusheng/Services/FailedRecordingStore.swift`
- Create: `FushengTests/FailedRecordingStoreTests.swift`

- [ ] **Step 1: Write failing store tests**

Create `FushengTests/FailedRecordingStoreTests.swift`:

```swift
import SwiftData
import XCTest
@testable import Fusheng

@MainActor
final class FailedRecordingStoreTests: XCTestCase {
    func testSaveReadAndDeleteFailedRecording() throws {
        let container = try makeContainer()
        let audio = SpyFailedRecordingAudioStore()
        let store = FailedRecordingStore(modelContext: container.mainContext, audioStore: audio)
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

        try store.saveFailedRecording(
            id: id,
            createdAt: Date(timeIntervalSince1970: 20),
            sourceAppName: "Notes",
            mode: .clean,
            asrModel: "fun-asr-realtime",
            polishModel: "qwen-plus",
            failureStage: .asr,
            errorSummary: "等待 task-finished 超时",
            audioFilePath: "/tmp/\(id.uuidString).pcm",
            rawASRText: ""
        )

        let saved = try XCTUnwrap(store.failedRecording(id: id))
        XCTAssertEqual(saved.id, id)
        XCTAssertEqual(saved.failureStage, .asr)
        XCTAssertEqual(saved.errorSummary, "等待 task-finished 超时")
        XCTAssertEqual(saved.retryState, .idle)

        try store.deleteFailedRecording(id: id)

        XCTAssertNil(try store.failedRecording(id: id))
        XCTAssertEqual(audio.deletedPaths, ["/tmp/\(id.uuidString).pcm"])
    }

    func testUpdateRetryState() throws {
        let container = try makeContainer()
        let store = FailedRecordingStore(modelContext: container.mainContext, audioStore: SpyFailedRecordingAudioStore())
        let id = UUID()
        let retryDate = Date(timeIntervalSince1970: 30)

        try store.saveFailedRecording(
            id: id,
            createdAt: Date(timeIntervalSince1970: 10),
            sourceAppName: "Preview",
            mode: .professional,
            asrModel: "fun-asr-realtime",
            polishModel: "qwen-plus",
            failureStage: .polish,
            errorSummary: "整理失败",
            audioFilePath: "/tmp/audio.pcm",
            rawASRText: "原始文本"
        )

        try store.updateRetryState(id: id, state: .failed, errorSummary: "再次失败", lastRetryAt: retryDate)

        let updated = try XCTUnwrap(store.failedRecording(id: id))
        XCTAssertEqual(updated.retryState, .failed)
        XCTAssertEqual(updated.errorSummary, "再次失败")
        XCTAssertEqual(updated.lastRetryAt, retryDate)
    }

    func testPrunesOldestRecordsBeyondFiftyAndDeletesAudio() throws {
        let container = try makeContainer()
        let audio = SpyFailedRecordingAudioStore()
        let store = FailedRecordingStore(modelContext: container.mainContext, audioStore: audio, retentionLimit: 50)

        for index in 0..<51 {
            let id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!
            try store.saveFailedRecording(
                id: id,
                createdAt: Date(timeIntervalSince1970: TimeInterval(index)),
                sourceAppName: "App",
                mode: .clean,
                asrModel: "asr",
                polishModel: "llm",
                failureStage: .asr,
                errorSummary: "error",
                audioFilePath: "/tmp/\(index).pcm",
                rawASRText: ""
            )
        }

        let recent = try store.recentFailedRecordings(limit: 100)
        XCTAssertEqual(recent.count, 50)
        XCTAssertFalse(recent.contains { $0.audioFilePath == "/tmp/0.pcm" })
        XCTAssertEqual(audio.deletedPaths, ["/tmp/0.pcm"])
    }

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: FailedRecordingRecord.self, configurations: config)
    }
}

private final class SpyFailedRecordingAudioStore: FailedRecordingAudioStoring {
    private(set) var deletedPaths: [String] = []

    func makeWriter(id: UUID) throws -> FailedRecordingAudioWriting {
        StubAudioWriter(filePath: "/tmp/\(id.uuidString).pcm")
    }

    func fileExists(at path: String) -> Bool {
        true
    }

    func audioChunks(from path: String) throws -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func deleteAudio(at path: String) {
        deletedPaths.append(path)
    }
}

private final class StubAudioWriter: FailedRecordingAudioWriting {
    let filePath: String

    init(filePath: String) {
        self.filePath = filePath
    }

    func append(_ data: Data) throws {}
    func close() throws {}
    func delete() {}
}
```

- [ ] **Step 2: Run the test and verify it fails**

Run:

```bash
xcodebuild test -project Fusheng.xcodeproj -scheme Fusheng -destination 'platform=macOS' -only-testing:FushengTests/FailedRecordingStoreTests
```

Expected: FAIL because `FailedRecordingStore` and `FailedRecordingRecord` do not exist.

- [ ] **Step 3: Implement the store**

Create `Fusheng/Services/FailedRecordingStore.swift`:

```swift
import Foundation
import SwiftData

@Model
final class FailedRecordingRecord {
    @Attribute(.unique) var id: UUID
    var idSortKey: String
    var createdAt: Date
    var sourceAppName: String
    var modeRawValue: String
    var asrModel: String
    var polishModel: String
    var failureStageRawValue: String
    var errorSummary: String
    var audioFilePath: String
    var rawASRText: String
    var retryStateRawValue: String
    var lastRetryAt: Date?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        sourceAppName: String,
        mode: TextPolishMode,
        asrModel: String,
        polishModel: String,
        failureStage: FailedRecordingStage,
        errorSummary: String,
        audioFilePath: String,
        rawASRText: String,
        retryState: FailedRecordingRetryState = .idle,
        lastRetryAt: Date? = nil
    ) {
        self.id = id
        self.idSortKey = id.uuidString
        self.createdAt = createdAt
        self.sourceAppName = sourceAppName
        self.modeRawValue = mode.rawValue
        self.asrModel = asrModel
        self.polishModel = polishModel
        self.failureStageRawValue = failureStage.rawValue
        self.errorSummary = errorSummary
        self.audioFilePath = audioFilePath
        self.rawASRText = rawASRText
        self.retryStateRawValue = retryState.rawValue
        self.lastRetryAt = lastRetryAt
    }

    var snapshot: FailedRecordingSnapshot {
        FailedRecordingSnapshot(
            id: id,
            createdAt: createdAt,
            sourceAppName: sourceAppName,
            mode: TextPolishMode(rawValue: modeRawValue) ?? .clean,
            asrModel: asrModel,
            polishModel: polishModel,
            failureStage: FailedRecordingStage(rawValue: failureStageRawValue) ?? .asr,
            errorSummary: errorSummary,
            audioFilePath: audioFilePath,
            rawASRText: rawASRText,
            retryState: FailedRecordingRetryState(rawValue: retryStateRawValue) ?? .idle,
            lastRetryAt: lastRetryAt
        )
    }
}

@MainActor
final class FailedRecordingStore: FailedRecordingStoring {
    private let modelContext: ModelContext
    private let audioStore: FailedRecordingAudioStoring
    private let retentionLimit: Int

    init(modelContext: ModelContext, audioStore: FailedRecordingAudioStoring, retentionLimit: Int = 50) {
        self.modelContext = modelContext
        self.audioStore = audioStore
        self.retentionLimit = retentionLimit
    }

    func saveFailedRecording(
        id: UUID,
        createdAt: Date = Date(),
        sourceAppName: String,
        mode: TextPolishMode,
        asrModel: String,
        polishModel: String,
        failureStage: FailedRecordingStage,
        errorSummary: String,
        audioFilePath: String,
        rawASRText: String
    ) throws {
        let record = FailedRecordingRecord(
            id: id,
            createdAt: createdAt,
            sourceAppName: sourceAppName,
            mode: mode,
            asrModel: asrModel,
            polishModel: polishModel,
            failureStage: failureStage,
            errorSummary: errorSummary,
            audioFilePath: audioFilePath,
            rawASRText: rawASRText
        )
        modelContext.insert(record)
        try pruneIfNeeded()
        try modelContext.save()
        NotificationCenter.default.post(name: .failedRecordingQueueDidChange, object: nil)
    }

    func recentFailedRecordings(limit: Int) throws -> [FailedRecordingSnapshot] {
        guard limit > 0 else { return [] }
        var descriptor = FetchDescriptor<FailedRecordingRecord>(
            sortBy: [
                SortDescriptor(\.createdAt, order: .reverse),
                SortDescriptor(\.idSortKey, order: .reverse)
            ]
        )
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor).map(\.snapshot)
    }

    func failedRecording(id: UUID) throws -> FailedRecordingSnapshot? {
        let descriptor = FetchDescriptor<FailedRecordingRecord>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first?.snapshot
    }

    func updateRetryState(id: UUID, state: FailedRecordingRetryState, errorSummary: String?, lastRetryAt: Date?) throws {
        let records = try records(matching: id)
        for record in records {
            record.retryStateRawValue = state.rawValue
            if let errorSummary {
                record.errorSummary = errorSummary
            }
            record.lastRetryAt = lastRetryAt
        }
        try modelContext.save()
        NotificationCenter.default.post(name: .failedRecordingQueueDidChange, object: nil)
    }

    func deleteFailedRecording(id: UUID) throws {
        let records = try records(matching: id)
        for record in records {
            let path = record.audioFilePath
            modelContext.delete(record)
            audioStore.deleteAudio(at: path)
        }
        try modelContext.save()
        NotificationCenter.default.post(name: .failedRecordingQueueDidChange, object: nil)
    }

    private func records(matching id: UUID) throws -> [FailedRecordingRecord] {
        let descriptor = FetchDescriptor<FailedRecordingRecord>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor)
    }

    private func pruneIfNeeded() throws {
        guard retentionLimit > 0 else { return }
        let records = try modelContext.fetch(FetchDescriptor<FailedRecordingRecord>(
            sortBy: [
                SortDescriptor(\.createdAt, order: .reverse),
                SortDescriptor(\.idSortKey, order: .reverse)
            ]
        ))
        guard records.count > retentionLimit else { return }

        for record in records.dropFirst(retentionLimit) {
            let path = record.audioFilePath
            modelContext.delete(record)
            audioStore.deleteAudio(at: path)
        }
    }
}
```

- [ ] **Step 4: Regenerate project and run store tests**

Run:

```bash
xcodegen generate
xcodebuild test -project Fusheng.xcodeproj -scheme Fusheng -destination 'platform=macOS' -only-testing:FushengTests/FailedRecordingStoreTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add project.yml Fusheng.xcodeproj Fusheng/Services/FailedRecordingStore.swift FushengTests/FailedRecordingStoreTests.swift
git commit -m "feat: add failed recording store"
```

---

### Task 4: Failed Recording Audio File Store

**Files:**
- Create: `Fusheng/Services/FailedRecordingAudioStore.swift`
- Create: `FushengTests/FailedRecordingAudioStoreTests.swift`

- [ ] **Step 1: Write failing audio store tests**

Create `FushengTests/FailedRecordingAudioStoreTests.swift`:

```swift
import XCTest
@testable import Fusheng

final class FailedRecordingAudioStoreTests: XCTestCase {
    func testWriterAppendsReadsAndDeletesPCMFile() async throws {
        let baseURL = FileManager.default.temporaryDirectory
            .appending(path: "FushengAudioStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let store = FailedRecordingAudioStore(baseDirectory: baseURL)
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let writer = try store.makeWriter(id: id)

        try writer.append(Data([1, 2, 3]))
        try writer.append(Data([4, 5]))
        try writer.close()

        XCTAssertTrue(store.fileExists(at: writer.filePath))

        var chunks: [Data] = []
        for try await chunk in try store.audioChunks(from: writer.filePath) {
            chunks.append(chunk)
        }
        XCTAssertEqual(chunks.reduce(Data(), +), Data([1, 2, 3, 4, 5]))

        store.deleteAudio(at: writer.filePath)

        XCTAssertFalse(store.fileExists(at: writer.filePath))
    }

    func testDeletingMissingAudioDoesNotThrow() throws {
        let baseURL = FileManager.default.temporaryDirectory
            .appending(path: "FushengAudioStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let store = FailedRecordingAudioStore(baseDirectory: baseURL)

        store.deleteAudio(at: baseURL.appending(path: "missing.pcm").path)
    }
}
```

- [ ] **Step 2: Run the test and verify it fails**

Run:

```bash
xcodebuild test -project Fusheng.xcodeproj -scheme Fusheng -destination 'platform=macOS' -only-testing:FushengTests/FailedRecordingAudioStoreTests
```

Expected: FAIL because `FailedRecordingAudioStore` does not exist.

- [ ] **Step 3: Implement audio store**

Create `Fusheng/Services/FailedRecordingAudioStore.swift`:

```swift
import Foundation

final class FailedRecordingAudioStore: FailedRecordingAudioStoring {
    private let baseDirectory: URL
    private let fileManager: FileManager

    init(
        baseDirectory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Fusheng", directoryHint: .isDirectory)
            .appending(path: "FailedRecordings", directoryHint: .isDirectory),
        fileManager: FileManager = .default
    ) {
        self.baseDirectory = baseDirectory
        self.fileManager = fileManager
    }

    func makeWriter(id: UUID) throws -> FailedRecordingAudioWriting {
        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        let url = baseDirectory.appending(path: "\(id.uuidString).pcm")
        fileManager.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        return FailedRecordingAudioWriter(fileURL: url, handle: handle, fileManager: fileManager)
    }

    func fileExists(at path: String) -> Bool {
        fileManager.fileExists(atPath: path)
    }

    func audioChunks(from path: String) throws -> AsyncThrowingStream<Data, Error> {
        guard fileManager.fileExists(atPath: path) else {
            throw AppError.recorderFailed("音频文件缺失")
        }

        return AsyncThrowingStream { continuation in
            Task.detached {
                do {
                    let data = try Data(contentsOf: URL(filePath: path))
                    let chunkSize = 4096
                    var offset = 0
                    while offset < data.count {
                        let end = min(offset + chunkSize, data.count)
                        continuation.yield(data.subdata(in: offset..<end))
                        offset = end
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func deleteAudio(at path: String) {
        try? fileManager.removeItem(atPath: path)
    }
}

private final class FailedRecordingAudioWriter: FailedRecordingAudioWriting {
    let filePath: String
    private let fileURL: URL
    private let handle: FileHandle
    private let fileManager: FileManager
    private var isClosed = false

    init(fileURL: URL, handle: FileHandle, fileManager: FileManager) {
        self.fileURL = fileURL
        self.filePath = fileURL.path
        self.handle = handle
        self.fileManager = fileManager
    }

    func append(_ data: Data) throws {
        guard !isClosed else { return }
        try handle.write(contentsOf: data)
    }

    func close() throws {
        guard !isClosed else { return }
        try handle.close()
        isClosed = true
    }

    func delete() {
        try? close()
        try? fileManager.removeItem(at: fileURL)
    }
}
```

- [ ] **Step 4: Regenerate project and run audio store tests**

Run:

```bash
xcodegen generate
xcodebuild test -project Fusheng.xcodeproj -scheme Fusheng -destination 'platform=macOS' -only-testing:FushengTests/FailedRecordingAudioStoreTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add project.yml Fusheng.xcodeproj Fusheng/Services/FailedRecordingAudioStore.swift FushengTests/FailedRecordingAudioStoreTests.swift
git commit -m "feat: add failed recording audio store"
```

---

### Task 5: Tee Audio Stream While Recording

**Files:**
- Create: `Fusheng/Services/AudioStreamTee.swift`
- Create: `FushengTests/AudioStreamTeeTests.swift`

- [ ] **Step 1: Write failing tee tests**

Create `FushengTests/AudioStreamTeeTests.swift`:

```swift
import XCTest
@testable import Fusheng

final class AudioStreamTeeTests: XCTestCase {
    func testTeeWritesEveryChunkAndYieldsSameChunks() async throws {
        let writer = MemoryAudioWriter(filePath: "/tmp/audio.pcm")
        let input = AsyncThrowingStream<Data, Error> { continuation in
            continuation.yield(Data([1]))
            continuation.yield(Data([2, 3]))
            continuation.finish()
        }

        let output = AudioStreamTee.tee(input, writer: writer)

        var received: [Data] = []
        for try await chunk in output {
            received.append(chunk)
        }

        XCTAssertEqual(received, [Data([1]), Data([2, 3])])
        XCTAssertEqual(writer.written, [Data([1]), Data([2, 3])])
        XCTAssertEqual(writer.closeCount, 1)
    }

    func testTeeClosesWriterWhenInputThrows() async {
        let writer = MemoryAudioWriter(filePath: "/tmp/audio.pcm")
        let input = AsyncThrowingStream<Data, Error> { continuation in
            continuation.finish(throwing: AppError.recorderFailed("boom"))
        }

        do {
            for try await _ in AudioStreamTee.tee(input, writer: writer) {}
            XCTFail("Expected throw")
        } catch {
            XCTAssertEqual(writer.closeCount, 1)
        }
    }
}

private final class MemoryAudioWriter: FailedRecordingAudioWriting {
    let filePath: String
    private(set) var written: [Data] = []
    private(set) var closeCount = 0

    init(filePath: String) {
        self.filePath = filePath
    }

    func append(_ data: Data) throws {
        written.append(data)
    }

    func close() throws {
        closeCount += 1
    }

    func delete() {}
}
```

- [ ] **Step 2: Run the test and verify it fails**

Run:

```bash
xcodebuild test -project Fusheng.xcodeproj -scheme Fusheng -destination 'platform=macOS' -only-testing:FushengTests/AudioStreamTeeTests
```

Expected: FAIL because `AudioStreamTee` does not exist.

- [ ] **Step 3: Implement tee**

Create `Fusheng/Services/AudioStreamTee.swift`:

```swift
import Foundation

enum AudioStreamTee {
    static func tee(
        _ input: AsyncThrowingStream<Data, Error>,
        writer: FailedRecordingAudioWriting
    ) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await chunk in input {
                        try writer.append(chunk)
                        continuation.yield(chunk)
                    }
                    try writer.close()
                    continuation.finish()
                } catch {
                    try? writer.close()
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
```

- [ ] **Step 4: Regenerate project and run tee tests**

Run:

```bash
xcodegen generate
xcodebuild test -project Fusheng.xcodeproj -scheme Fusheng -destination 'platform=macOS' -only-testing:FushengTests/AudioStreamTeeTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add project.yml Fusheng.xcodeproj Fusheng/Services/AudioStreamTee.swift FushengTests/AudioStreamTeeTests.swift
git commit -m "feat: tee recorded audio to disk"
```

---

### Task 6: Save Failed Recordings From Coordinator

**Files:**
- Modify: `Fusheng/App/AppCoordinator.swift`
- Modify: `FushengTests/AppCoordinatorTests.swift`

- [ ] **Step 1: Add failing coordinator tests**

Add these tests to `FushengTests/AppCoordinatorTests.swift`:

```swift
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
```

Add helper fakes to the bottom of the file:

```swift
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

    func fileExists(at path: String) -> Bool { true }

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
```

Update `makeCoordinator(...)` in the tests to accept and pass:

```swift
failedRecordingStore: FailedRecordingStoring? = nil,
failedRecordingAudioStore: FailedRecordingAudioStoring? = nil,
```

- [ ] **Step 2: Run the tests and verify they fail**

Run:

```bash
xcodebuild test -project Fusheng.xcodeproj -scheme Fusheng -destination 'platform=macOS' -only-testing:FushengTests/AppCoordinatorTests/testASRFailureSavesFailedRecordingWithAudioPath -only-testing:FushengTests/AppCoordinatorTests/testPolishFailureSavesFailedRecordingAndRawText -only-testing:FushengTests/AppCoordinatorTests/testSuccessfulFlowDeletesFailedRecordingCandidateAudio -only-testing:FushengTests/AppCoordinatorTests/testEmptyRecognitionDeletesAudioAndDoesNotSaveFailedRecording
```

Expected: FAIL because `AppCoordinator` does not accept failed recording dependencies or save/delete candidate audio.

- [ ] **Step 3: Modify `AppCoordinator` initializer and properties**

Add properties:

```swift
private let failedRecordingStore: FailedRecordingStoring?
private let failedRecordingAudioStore: FailedRecordingAudioStoring?
private var activeFailedRecordingID: UUID?
private var activeFailedRecordingAudioWriter: FailedRecordingAudioWriting?
```

Extend the dependency initializer:

```swift
failedRecordingStore: FailedRecordingStoring? = nil,
failedRecordingAudioStore: FailedRecordingAudioStoring? = nil,
```

Assign them in both initializers. In the default initializer, set both to `nil`.

- [ ] **Step 4: Wrap audio stream during start**

In `startRecording()`, after `let focusContext = ...`, create the writer before starting ASR:

```swift
let failedRecordingID = UUID()
let writer = try failedRecordingAudioStore?.makeWriter(id: failedRecordingID)

activeAudioStream = try recorder.startRecording()
activeAPIKey = apiKey
activeFailedRecordingID = failedRecordingID
activeFailedRecordingAudioWriter = writer

let recorderStream = activeAudioStream!
let audioStream = writer.map { AudioStreamTee.tee(recorderStream, writer: $0) } ?? recorderStream
let asrModel = settings.asrModel
```

Pass `audioStream` into ASR instead of `activeAudioStream!`.

- [ ] **Step 5: Save failed recording on ASR failure**

Add helper:

```swift
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
    let errorSummary = error.localizedDescription

    do {
        try failedRecordingStore.saveFailedRecording(
            id: id,
            createdAt: Date(),
            sourceAppName: sourceAppName,
            mode: settings.polishMode,
            asrModel: settings.asrModel,
            polishModel: settings.polishModel,
            failureStage: stage,
            errorSummary: errorSummary,
            audioFilePath: writer.filePath,
            rawASRText: rawASRText
        )
    } catch {
        coordinatorLogger.error("failed to save failed recording: \(error.localizedDescription, privacy: .public)")
    }
}
```

Add cleanup helper:

```swift
private func discardFailedRecordingCandidateAudio() {
    activeFailedRecordingAudioWriter?.delete()
    activeFailedRecordingAudioWriter = nil
    activeFailedRecordingID = nil
}
```

Call `discardFailedRecordingCandidateAudio()` on normal success, empty ASR, missing text polisher, and any non-interface failure path that should not save retry audio.

In `catch let error as AppError` around `recognitionTask.value`, call:

```swift
saveInterfaceFailureRecording(stage: .asr, rawASRText: "", error: error)
clearActiveInputSession()
activeFailedRecordingAudioWriter = nil
activeFailedRecordingID = nil
state = .failed(error)
```

In the generic catch for recognition, call:

```swift
let wrapped = AppError.asrFailed(error.localizedDescription)
saveInterfaceFailureRecording(stage: .asr, rawASRText: "", error: wrapped)
clearActiveInputSession()
activeFailedRecordingAudioWriter = nil
activeFailedRecordingID = nil
state = .failed(wrapped)
```

In the LLM catch inside polishing, before `savePolishFailureDraft(...)`, call:

```swift
saveInterfaceFailureRecording(stage: .polish, rawASRText: recognizedText, error: error)
activeFailedRecordingAudioWriter = nil
activeFailedRecordingID = nil
```

- [ ] **Step 6: Run focused coordinator tests**

Run:

```bash
xcodebuild test -project Fusheng.xcodeproj -scheme Fusheng -destination 'platform=macOS' -only-testing:FushengTests/AppCoordinatorTests
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Fusheng/App/AppCoordinator.swift FushengTests/AppCoordinatorTests.swift
git commit -m "feat: save retryable recordings on interface failures"
```

---

### Task 7: Failed Recording Retry Service

**Files:**
- Create: `Fusheng/Services/FailedRecordingRetryService.swift`
- Create: `FushengTests/FailedRecordingRetryServiceTests.swift`

- [ ] **Step 1: Write failing retry service tests**

Create `FushengTests/FailedRecordingRetryServiceTests.swift` with these covered behaviors:

```swift
import XCTest
@testable import Fusheng

@MainActor
final class FailedRecordingRetryServiceTests: XCTestCase {
    func testASRStageRetryRunsASRAndPolishCopiesSavesDraftAndDeletesFailure() async {
        let failedStore = MemoryFailedRecordingStore(snapshot: makeSnapshot(stage: .asr, rawASRText: ""))
        let audioStore = MemoryRetryAudioStore()
        let inserter = FakeInserter()
        let drafts = FakeDraftStore()
        let asr = FakeASR(text: "重新识别文本")
        let polisher = FakePolisher(text: "重新整理文本")
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
        XCTAssertEqual(inserter.copiedTexts, ["重新整理文本"])
        XCTAssertEqual(drafts.savedDrafts.map(\.polishedText), ["重新整理文本"])
        XCTAssertEqual(drafts.savedDrafts.map(\.rawASRText), ["重新识别文本"])
        XCTAssertEqual(failedStore.deletedIDs, [failedStore.snapshot.id])
    }

    func testPolishStageRetrySkipsASR() async {
        let failedStore = MemoryFailedRecordingStore(snapshot: makeSnapshot(stage: .polish, rawASRText: "已有识别文本"))
        let audioStore = MemoryRetryAudioStore()
        let inserter = FakeInserter()
        let drafts = FakeDraftStore()
        let asr = CountingASR(text: "不应该调用")
        let service = makeService(
            failedStore: failedStore,
            audioStore: audioStore,
            asrClient: asr,
            polisher: FakePolisher(text: "重新整理文本"),
            inserter: inserter,
            drafts: drafts
        )

        await service.retry(id: failedStore.snapshot.id)

        XCTAssertEqual(asr.callCount, 0)
        XCTAssertEqual(inserter.copiedTexts, ["重新整理文本"])
        XCTAssertEqual(drafts.savedDrafts.map(\.rawASRText), ["已有识别文本"])
        XCTAssertEqual(failedStore.deletedIDs, [failedStore.snapshot.id])
    }

    func testRetryFailureKeepsRecordAndUpdatesError() async {
        let failedStore = MemoryFailedRecordingStore(snapshot: makeSnapshot(stage: .polish, rawASRText: "已有识别文本"))
        let service = makeService(
            failedStore: failedStore,
            audioStore: MemoryRetryAudioStore(),
            polisher: FakePolisher(error: FakeError.polishFailed)
        )

        await service.retry(id: failedStore.snapshot.id)

        XCTAssertEqual(failedStore.deletedIDs, [])
        XCTAssertEqual(failedStore.retryStates.last?.state, .failed)
        XCTAssertNotNil(failedStore.retryStates.last?.errorSummary)
    }
}
```

Add these local fakes to the same test file:

```swift
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
    private(set) var readPaths: [String] = []

    func makeWriter(id: UUID) throws -> FailedRecordingAudioWriting {
        StubAudioWriter(filePath: "/tmp/\(id.uuidString).pcm")
    }

    func fileExists(at path: String) -> Bool {
        true
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

private func makeSnapshot(stage: FailedRecordingStage, rawASRText: String) -> FailedRecordingSnapshot {
    FailedRecordingSnapshot(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        createdAt: Date(timeIntervalSince1970: 10),
        sourceAppName: "Notes",
        mode: .clean,
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
```

- [ ] **Step 2: Run the test and verify it fails**

Run:

```bash
xcodebuild test -project Fusheng.xcodeproj -scheme Fusheng -destination 'platform=macOS' -only-testing:FushengTests/FailedRecordingRetryServiceTests
```

Expected: FAIL because `FailedRecordingRetryService` does not exist.

- [ ] **Step 3: Implement retry service**

Create `Fusheng/Services/FailedRecordingRetryService.swift`:

```swift
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

    init(
        apiKeyProvider: APIKeyProviding,
        failedRecordingStore: FailedRecordingStoring,
        audioStore: FailedRecordingAudioStoring,
        asrClient: ASRRecognizing,
        textPolisher: TextPolishing,
        textInserter: TextInserting,
        draftStore: DraftStoring
    ) {
        self.apiKeyProvider = apiKeyProvider
        self.failedRecordingStore = failedRecordingStore
        self.audioStore = audioStore
        self.asrClient = asrClient
        self.textPolisher = textPolisher
        self.textInserter = textInserter
        self.draftStore = draftStore
    }

    func retry(id: UUID) async {
        do {
            guard let snapshot = try failedRecordingStore.failedRecording(id: id) else { return }
            guard let apiKey = try apiKeyProvider.loadAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines), !apiKey.isEmpty else {
                try failedRecordingStore.updateRetryState(id: id, state: .failed, errorSummary: "缺少 API Key", lastRetryAt: Date())
                return
            }
            guard audioStore.fileExists(at: snapshot.audioFilePath) else {
                try failedRecordingStore.updateRetryState(id: id, state: .failed, errorSummary: "音频文件缺失", lastRetryAt: Date())
                return
            }

            try failedRecordingStore.updateRetryState(id: id, state: .retrying, errorSummary: nil, lastRetryAt: Date())

            let rawText: String
            switch snapshot.failureStage {
            case .asr:
                let recognition = try await asrClient.recognize(
                    audioChunks: try audioStore.audioChunks(from: snapshot.audioFilePath),
                    model: snapshot.asrModel,
                    apiKey: apiKey
                )
                rawText = recognition.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            case .polish:
                rawText = snapshot.rawASRText.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            guard !rawText.isEmpty else {
                throw AppError.asrFailed("未识别到语音内容，请确认麦克风权限和输入音量后重试")
            }

            let polishedText = try await textPolisher.polish(
                rawText: rawText,
                mode: snapshot.mode,
                model: snapshot.polishModel,
                apiKey: apiKey
            )

            do {
                try textInserter.copyToClipboard(text: polishedText)
            } catch {
                try draftStore.saveDraft(
                    polishedText: polishedText,
                    rawASRText: rawText,
                    sourceAppName: snapshot.sourceAppName,
                    mode: snapshot.mode,
                    deliveryStatus: .savedDraft,
                    errorSummary: "文本已生成但复制失败：\(error.localizedDescription)"
                )
                try failedRecordingStore.updateRetryState(
                    id: id,
                    state: .failed,
                    errorSummary: "文本已生成但复制失败：\(error.localizedDescription)",
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
            NotificationCenter.default.post(name: .draftHistoryDidChange, object: nil)
            NotificationCenter.default.post(name: .failedRecordingQueueDidChange, object: nil)
        } catch {
            try? failedRecordingStore.updateRetryState(
                id: id,
                state: .failed,
                errorSummary: error.localizedDescription,
                lastRetryAt: Date()
            )
        }
    }
}
```

- [ ] **Step 4: Regenerate project and run retry tests**

Run:

```bash
xcodegen generate
xcodebuild test -project Fusheng.xcodeproj -scheme Fusheng -destination 'platform=macOS' -only-testing:FushengTests/FailedRecordingRetryServiceTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add project.yml Fusheng.xcodeproj Fusheng/Services/FailedRecordingRetryService.swift FushengTests/FailedRecordingRetryServiceTests.swift
git commit -m "feat: retry failed recordings"
```

---

### Task 8: Failed Recording Window and Menu Entry

**Files:**
- Create: `Fusheng/UI/FailedRecordingView.swift`
- Modify: `Fusheng/App/FushengApp.swift`
- Modify: `Fusheng/UI/RootMenuContent.swift`
- Modify: `FushengTests/AppBundleConfigurationTests.swift`

- [ ] **Step 1: Add failing UI configuration tests**

Add to `FushengTests/AppBundleConfigurationTests.swift`:

```swift
func testRootMenuOpensFailedRecordingWindowRefreshesAndActivatesWindow() throws {
    let source = try String(
        contentsOf: try sourceSnapshotURL("Fusheng/UI/RootMenuContent.swift"),
        encoding: .utf8
    )

    XCTAssertTrue(source.contains("Button(\"打开失败录音\""))
    XCTAssertTrue(source.contains("openFailedRecordingWindow()"))
    XCTAssertTrue(source.contains("NotificationCenter.default.post(name: .failedRecordingQueueDidChange"))
    XCTAssertTrue(source.contains("bringWindowToFront(matching:"))
    XCTAssertTrue(source.contains("失败录音"))
}

func testAppCreatesFailedRecordingWindowAndModelContainer() throws {
    let source = try String(
        contentsOf: try sourceSnapshotURL("Fusheng/App/FushengApp.swift"),
        encoding: .utf8
    )

    XCTAssertTrue(source.contains("ModelContainer(for: DraftRecord.self, FailedRecordingRecord.self)"))
    XCTAssertTrue(source.contains("Window(\"失败录音\", id: \"failed-recordings\")"))
    XCTAssertTrue(source.contains("FailedRecordingView("))
    XCTAssertTrue(source.contains("FailedRecordingStore("))
    XCTAssertTrue(source.contains("FailedRecordingRetryService("))
}

func testFailedRecordingViewShowsRetryAndDeleteActions() throws {
    let source = try String(
        contentsOf: try sourceSnapshotURL("Fusheng/UI/FailedRecordingView.swift"),
        encoding: .utf8
    )

    XCTAssertTrue(source.contains("struct FailedRecordingView"))
    XCTAssertTrue(source.contains("重新请求"))
    XCTAssertTrue(source.contains("删除"))
    XCTAssertTrue(source.contains("音频文件缺失"))
    XCTAssertTrue(source.contains(".failedRecordingQueueDidChange"))
    XCTAssertTrue(source.contains("retryService.retry"))
}
```

- [ ] **Step 2: Run the tests and verify they fail**

Run:

```bash
xcodebuild test -project Fusheng.xcodeproj -scheme Fusheng -destination 'platform=macOS' -only-testing:FushengTests/AppBundleConfigurationTests/testRootMenuOpensFailedRecordingWindowRefreshesAndActivatesWindow -only-testing:FushengTests/AppBundleConfigurationTests/testAppCreatesFailedRecordingWindowAndModelContainer -only-testing:FushengTests/AppBundleConfigurationTests/testFailedRecordingViewShowsRetryAndDeleteActions
```

Expected: FAIL because the UI and wiring do not exist.

- [ ] **Step 3: Create `FailedRecordingView`**

Create `Fusheng/UI/FailedRecordingView.swift`:

```swift
import SwiftUI

struct FailedRecordingView: View {
    @State private var records: [FailedRecordingSnapshot] = []
    @State private var errorMessage: String?

    let store: FailedRecordingStoring
    let audioStore: FailedRecordingAudioStoring
    let retryService: FailedRecordingRetryService

    var body: some View {
        VStack {
            if records.isEmpty {
                ContentUnavailableView("暂无失败录音", systemImage: "waveform.badge.exclamationmark")
            } else {
                List {
                    ForEach(records) { record in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(record.failureStage.displayText)
                                    .font(.headline)
                                Text(record.retryState.displayText)
                                    .foregroundStyle(.secondary)
                            }

                            Text(record.errorSummary)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 8) {
                                Text(record.createdAt.formatted())
                                Text(record.sourceAppName)
                                Text(record.mode.displayName)
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)

                            if !record.rawASRText.isEmpty {
                                Text(record.rawASRText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }

                            if !audioStore.fileExists(at: record.audioFilePath) {
                                Text("音频文件缺失")
                                    .foregroundStyle(.red)
                            }

                            HStack {
                                Button("重新请求") {
                                    Task {
                                        await retryService.retry(id: record.id)
                                        reload()
                                    }
                                }
                                .disabled(record.retryState == .retrying || !audioStore.fileExists(at: record.audioFilePath))

                                Button("删除", role: .destructive) {
                                    delete(record)
                                }
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }
        .padding()
        .alert("失败录音操作失败", isPresented: errorBinding) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: .failedRecordingQueueDidChange)) { _ in
            reload()
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func reload() {
        do {
            records = try store.recentFailedRecordings(limit: 100)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ record: FailedRecordingSnapshot) {
        do {
            try store.deleteFailedRecording(id: record.id)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

- [ ] **Step 4: Wire app dependencies and window**

Modify `Fusheng/App/FushengApp.swift`:

```swift
private let failedRecordingAudioStore: FailedRecordingAudioStore
private let failedRecordingStore: FailedRecordingStore
private let failedRecordingRetryService: FailedRecordingRetryService
```

In `init()`:

```swift
let failedRecordingAudioStore = FailedRecordingAudioStore()
let failedRecordingStore = FailedRecordingStore(
    modelContext: draftModelContainer.mainContext,
    audioStore: failedRecordingAudioStore
)
let textInserter = TextInsertionService()
let draftStore = DraftStore(modelContext: draftModelContainer.mainContext)
let asrClient = DashScopeASRClient()
let textPolisher = TextPolishClient()
let keychain = KeychainService()

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

let retryService = FailedRecordingRetryService(
    apiKeyProvider: keychain,
    failedRecordingStore: failedRecordingStore,
    audioStore: failedRecordingAudioStore,
    asrClient: asrClient,
    textPolisher: textPolisher,
    textInserter: textInserter,
    draftStore: draftStore
)
```

Assign the properties and add the window:

```swift
Window("失败录音", id: "failed-recordings") {
    FailedRecordingView(
        store: failedRecordingStore,
        audioStore: failedRecordingAudioStore,
        retryService: failedRecordingRetryService
    )
    .frame(width: 760, height: 520)
}
```

Change the model container factory:

```swift
return try ModelContainer(for: DraftRecord.self, FailedRecordingRecord.self)
```

- [ ] **Step 5: Add root menu entry**

Modify `Fusheng/UI/RootMenuContent.swift`:

```swift
Button("打开失败录音", action: openFailedRecordingWindow)
```

Add:

```swift
private func openFailedRecordingWindow() {
    NotificationCenter.default.post(name: .failedRecordingQueueDidChange, object: nil)
    openWindow(id: "failed-recordings")
    bringWindowToFront(matching: { $0.title.contains("失败录音") })
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
        NotificationCenter.default.post(name: .failedRecordingQueueDidChange, object: nil)
        bringWindowToFront(matching: { $0.title.contains("失败录音") })
    }
}
```

- [ ] **Step 6: Add failed recording view to source snapshot script**

In `project.yml`, add this line inside the `Copy source snapshot` script after the `RootMenuContent.swift` copy:

```bash
copy_item "Fusheng/UI/FailedRecordingView.swift"
```

- [ ] **Step 7: Regenerate project and run UI config tests**

Run:

```bash
xcodegen generate
xcodebuild test -project Fusheng.xcodeproj -scheme Fusheng -destination 'platform=macOS' -only-testing:FushengTests/AppBundleConfigurationTests
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add project.yml Fusheng.xcodeproj Fusheng/App/FushengApp.swift Fusheng/UI/RootMenuContent.swift Fusheng/UI/FailedRecordingView.swift FushengTests/AppBundleConfigurationTests.swift
git commit -m "feat: add failed recording window"
```

---

### Task 9: Full Verification and Install

**Files:**
- Verify all changed source and test files.

- [ ] **Step 1: Run all tests**

Run:

```bash
xcodebuild test -project Fusheng.xcodeproj -scheme Fusheng -destination 'platform=macOS'
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 2: Run normal build**

Run:

```bash
xcodebuild build -project Fusheng.xcodeproj -scheme Fusheng -destination 'platform=macOS'
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Install and restart app**

Run:

```bash
set -e
APP_SRC="$HOME/Library/Developer/Xcode/DerivedData/Fusheng-abcvbuywzmlvjshjpgdgmavzwqyp/Build/Products/Debug/Fusheng.app"
APP_DST="/Applications/浮声.app"
osascript -e 'tell application id "com.fusheng.voiceinput" to quit' >/dev/null 2>&1 || true
sleep 1
pkill -x Fusheng >/dev/null 2>&1 || true
sleep 1
ditto "$APP_SRC" "$APP_DST"
open "$APP_DST"
sleep 2
pgrep -fl "/Applications/浮声.app/Contents/MacOS/Fusheng"
```

Expected: one running `/Applications/浮声.app/Contents/MacOS/Fusheng` process.

- [ ] **Step 4: Manual QA**

Run these manual checks:

1. Set a valid API Key.
2. Temporarily make ASR fail by setting an invalid ASR model.
3. Record a short voice clip.
4. Verify “失败录音” contains an “识别失败” item.
5. Restore ASR model to `fun-asr-realtime`.
6. Click “重新请求”.
7. Verify result is copied to clipboard.
8. Verify a normal草稿历史 item is saved.
9. Verify failed recording item disappears.
10. Verify a normal successful recording does not add a failed recording item.

- [ ] **Step 5: Commit final verification adjustments if needed**

Only commit if manual QA exposes small fixes. Stage the exact files changed by those fixes, then commit:

```bash
git commit -m "fix: complete failed recording retry flow"
```

If no changes are needed, do not create an empty commit.

---

## Self-Review

Spec coverage:

- Independent “失败录音” page: Task 8.
- ASR-stage failed audio persistence: Tasks 4, 5, 6.
- LLM-stage failed task with `rawASRText`: Tasks 3 and 6.
- Retry from failed stage: Task 7.
- Copy to clipboard and save normal draft on retry success: Task 7.
- Delete failed item and audio after success: Task 7.
- Retention limit 50: Task 3.
- Not affected by “保留历史草稿”: Task 6 saves via `FailedRecordingStore`, not `DraftStore`.
- Only ASR/LLM interface failures enter queue: Task 6 tests ASR/LLM failures, empty ASR, and success cleanup.
- Window refresh/front behavior: Task 8.

Placeholder scan:

- No placeholder tokens or unspecified “handle edge cases” steps remain.
- Every implementation task includes tests, commands, and code snippets.

Type consistency:

- Store protocol names match implementation names.
- Snapshot fields match SwiftData record fields.
- Retry service uses existing `ASRRecognizing`, `TextPolishing`, `TextInserting`, and `DraftStoring` protocols.
- `FailedRecordingAudioStoring` returns `AsyncThrowingStream<Data, Error>`, matching `ASRRecognizing`.
