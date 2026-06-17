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
