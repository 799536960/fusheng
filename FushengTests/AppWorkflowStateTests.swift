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
        XCTAssertEqual(AppWorkflowState.recognizing.menuBarSystemImage, "waveform")
        XCTAssertEqual(AppWorkflowState.polishing.menuBarSystemImage, "sparkles")
        XCTAssertEqual(AppWorkflowState.delivering.menuBarSystemImage, "arrow.up.doc")
        XCTAssertEqual(AppWorkflowState.completed(.pasted).menuBarSystemImage, "waveform.circle")
        XCTAssertEqual(AppWorkflowState.failed(.asrFailed("网络断开")).menuBarSystemImage, "exclamationmark.triangle")
    }

    func testDraftDeliveryStatusDisplayTextIncludesAssociatedAppName() {
        XCTAssertEqual(DraftDeliveryStatus.noInput(appName: "Preview").displayText, "Preview 无可输入位置")
    }

    func testDraftSnapshotUsesTypedDeliveryStatus() {
        let snapshot = DraftSnapshot(
            id: UUID(),
            polishedText: "整理后文本",
            rawASRText: "原始文本",
            createdAt: Date(timeIntervalSince1970: 1),
            sourceAppName: "Preview",
            mode: .clean,
            deliveryStatus: .noInput(appName: "Preview"),
            errorSummary: nil
        )

        XCTAssertEqual(snapshot.deliveryStatus, .noInput(appName: "Preview"))
    }
}
