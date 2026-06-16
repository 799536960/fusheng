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

@MainActor
protocol DraftStoring {
    func saveDraft(polishedText: String, rawASRText: String, sourceAppName: String, mode: TextPolishMode, deliveryStatus: DraftDeliveryStatus, errorSummary: String?) throws
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
