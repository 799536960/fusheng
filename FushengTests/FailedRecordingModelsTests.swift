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
