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
            deliveryStatus: .savedDraft,
            errorSummary: nil
        )

        let drafts = try store.recentDrafts(limit: 5)
        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(drafts[0].polishedText, "整理后的文本")
        XCTAssertEqual(drafts[0].rawASRText, "原始识别文本")
        XCTAssertEqual(drafts[0].sourceAppName, "Notes")
        XCTAssertEqual(drafts[0].mode, .clean)
        XCTAssertEqual(drafts[0].deliveryStatus, .savedDraft)
    }

    @MainActor
    func testDeleteDraft() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DraftRecord.self, configurations: config)
        let store = DraftStore(modelContext: container.mainContext)

        try store.saveDraft(polishedText: "A", rawASRText: "B", sourceAppName: "X", mode: .original, deliveryStatus: .savedDraft, errorSummary: nil)
        let draft = try XCTUnwrap(store.recentDrafts(limit: 1).first)

        try store.deleteDraft(id: draft.id)

        XCTAssertEqual(try store.recentDrafts(limit: 5), [])
    }

    @MainActor
    func testAssociatedValueDeliveryStatusRoundTrips() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DraftRecord.self, configurations: config)
        let store = DraftStore(modelContext: container.mainContext)

        try store.saveDraft(
            polishedText: "A",
            rawASRText: "B",
            sourceAppName: "Preview",
            mode: .concise,
            deliveryStatus: .noInput(appName: "Preview"),
            errorSummary: "No input"
        )
        try store.saveDraft(
            polishedText: "C",
            rawASRText: "D",
            sourceAppName: "Safari",
            mode: .professional,
            deliveryStatus: .accessibilityPermissionMissing(appName: "Safari"),
            errorSummary: nil
        )

        let statuses = try store.recentDrafts(limit: 2).map(\.deliveryStatus)
        XCTAssertTrue(statuses.contains(.noInput(appName: "Preview")))
        XCTAssertTrue(statuses.contains(.accessibilityPermissionMissing(appName: "Safari")))
    }

    @MainActor
    func testRecentDraftsReturnsNewestFirstWithStableTieBreakAndLimit() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DraftRecord.self, configurations: config)
        let store = DraftStore(modelContext: container.mainContext)
        let sameCreatedAt = Date(timeIntervalSince1970: 10)

        container.mainContext.insert(DraftRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            polishedText: "same-time-low-id",
            rawASRText: "A",
            createdAt: sameCreatedAt,
            sourceAppName: "Notes",
            mode: .clean,
            deliveryStatus: .savedDraft,
            errorSummary: nil
        ))
        container.mainContext.insert(DraftRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            polishedText: "same-time-high-id",
            rawASRText: "B",
            createdAt: sameCreatedAt,
            sourceAppName: "Notes",
            mode: .clean,
            deliveryStatus: .savedDraft,
            errorSummary: nil
        ))
        container.mainContext.insert(DraftRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            polishedText: "newer",
            rawASRText: "C",
            createdAt: Date(timeIntervalSince1970: 20),
            sourceAppName: "Notes",
            mode: .clean,
            deliveryStatus: .savedDraft,
            errorSummary: nil
        ))
        try container.mainContext.save()

        let drafts = try store.recentDrafts(limit: 2)

        XCTAssertEqual(drafts.map(\.polishedText), ["newer", "same-time-high-id"])
    }

    @MainActor
    func testUnknownStoredDeliveryStatusFallsBackToSavedDraft() throws {
        let record = DraftRecord(
            polishedText: "A",
            rawASRText: "B",
            sourceAppName: "Notes",
            mode: .clean,
            deliveryStatus: .pasted,
            errorSummary: nil
        )
        record.deliveryStatusRawValue = "future-status"

        XCTAssertEqual(record.deliveryStatus, .savedDraft)
    }
}
