import Foundation

extension Notification.Name {
    static let audioLevelDidChange = Notification.Name("FushengAudioLevelDidChange")
    static let draftHistoryDidChange = Notification.Name("FushengDraftHistoryDidChange")
    static let speechHotkeyDidChange = Notification.Name("FushengSpeechHotkeyDidChange")
    static let failedRecordingQueueDidChange = Notification.Name("FushengFailedRecordingQueueDidChange")
}

enum DeliveryResult: Equatable {
    case pasted
    case savedDraft
}

enum DraftDeliveryStatus: Equatable {
    case pasted
    case savedDraft
    case pasteFailed
    case autoPasteDisabled
    case noInput(appName: String)
    case accessibilityPermissionMissing(appName: String)

    var displayText: String {
        switch self {
        case .pasted:
            return "已粘贴"
        case .savedDraft:
            return "已保存草稿"
        case .pasteFailed:
            return "粘贴失败"
        case .autoPasteDisabled:
            return "自动粘贴已关闭"
        case .noInput(let appName):
            return "\(appName) 无可输入位置"
        case .accessibilityPermissionMissing(let appName):
            return "\(appName) 缺少辅助功能权限"
        }
    }
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
    let deliveryStatus: DraftDeliveryStatus
    let errorSummary: String?
}
