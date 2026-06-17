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
