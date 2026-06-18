import Foundation
import SwiftData

@Model
final class DraftRecord {
    @Attribute(.unique) var id: UUID
    var idSortKey: String
    var polishedText: String
    var rawASRText: String
    var createdAt: Date
    var sourceAppName: String
    var modeRawValue: String
    var deliveryStatusRawValue: String
    var deliveryStatusAppName: String?
    var errorSummary: String?

    init(
        id: UUID = UUID(),
        polishedText: String,
        rawASRText: String,
        createdAt: Date = Date(),
        sourceAppName: String,
        mode: TextPolishMode,
        deliveryStatus: DraftDeliveryStatus,
        errorSummary: String?
    ) {
        self.id = id
        self.idSortKey = id.uuidString
        self.polishedText = polishedText
        self.rawASRText = rawASRText
        self.createdAt = createdAt
        self.sourceAppName = sourceAppName
        self.modeRawValue = mode.rawValue
        self.errorSummary = errorSummary

        let storage = DraftDeliveryStatusStorage(deliveryStatus)
        self.deliveryStatusRawValue = storage.rawValue
        self.deliveryStatusAppName = storage.appName
    }

    var mode: TextPolishMode {
        TextPolishMode(rawValue: modeRawValue) ?? .clean
    }

    var deliveryStatus: DraftDeliveryStatus {
        DraftDeliveryStatusStorage(rawValue: deliveryStatusRawValue, appName: deliveryStatusAppName).status
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
        deliveryStatus: DraftDeliveryStatus,
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
        NotificationCenter.default.post(name: .draftHistoryDidChange, object: nil)
    }

    func recentDrafts(limit: Int) throws -> [DraftSnapshot] {
        guard limit > 0 else { return [] }

        var descriptor = FetchDescriptor<DraftRecord>(
            sortBy: [
                SortDescriptor(\.createdAt, order: .reverse),
                SortDescriptor(\.idSortKey, order: .reverse)
            ]
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
        NotificationCenter.default.post(name: .draftHistoryDidChange, object: nil)
    }
}

private struct DraftDeliveryStatusStorage {
    let rawValue: String
    let appName: String?

    init(_ status: DraftDeliveryStatus) {
        switch status {
        case .pasted:
            self.rawValue = "pasted"
            self.appName = nil
        case .savedDraft:
            self.rawValue = "savedDraft"
            self.appName = nil
        case .pasteFailed:
            self.rawValue = "pasteFailed"
            self.appName = nil
        case .autoPasteDisabled:
            self.rawValue = "autoPasteDisabled"
            self.appName = nil
        case .noInput(let appName):
            self.rawValue = "noInput"
            self.appName = appName
        case .accessibilityPermissionMissing(let appName):
            self.rawValue = "accessibilityPermissionMissing"
            self.appName = appName
        }
    }

    init(rawValue: String, appName: String?) {
        self.rawValue = rawValue
        self.appName = appName
    }

    var status: DraftDeliveryStatus {
        switch rawValue {
        case "pasted":
            return .pasted
        case "savedDraft":
            return .savedDraft
        case "pasteFailed":
            return .pasteFailed
        case "autoPasteDisabled":
            return .autoPasteDisabled
        case "noInput":
            return .noInput(appName: appName ?? "")
        case "accessibilityPermissionMissing":
            return .accessibilityPermissionMissing(appName: appName ?? "")
        default:
            return .savedDraft
        }
    }
}
