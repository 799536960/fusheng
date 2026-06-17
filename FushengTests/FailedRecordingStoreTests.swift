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
