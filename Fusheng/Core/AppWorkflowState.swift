import Foundation

enum AppWorkflowState: Equatable {
    case idle
    case recording(startedAt: Date)
    case recognizing
    case polishing
    case delivering
    case completed(DeliveryResult)
    case failed(AppError)

    var displayText: String {
        switch self {
        case .idle:
            return "空闲"
        case .recording:
            return "录音中"
        case .recognizing:
            return "识别中"
        case .polishing:
            return "整理中"
        case .delivering:
            return "输出中"
        case .completed(.pasted):
            return "已粘贴"
        case .completed(.savedDraft):
            return "已保存草稿"
        case .failed(let error):
            return "错误：\(error.localizedDescription)"
        }
    }

    var menuBarSystemImage: String {
        switch self {
        case .idle, .completed:
            return "waveform.circle"
        case .recording:
            return "waveform.circle.fill"
        case .recognizing:
            return "waveform"
        case .polishing:
            return "sparkles"
        case .delivering:
            return "arrow.up.doc"
        case .failed:
            return "exclamationmark.triangle"
        }
    }
}
