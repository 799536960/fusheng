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
