import Foundation

struct DashScopeASRRunTaskEvent: Encodable {
    struct EmptyInput: Encodable {}

    struct Header: Encodable {
        let action = "run-task"
        let taskID: String
        let streaming = "duplex"

        enum CodingKeys: String, CodingKey {
            case action
            case taskID = "task_id"
            case streaming
        }
    }

    struct Payload: Encodable {
        struct Parameters: Encodable {
            let format = "pcm"
            let sampleRate = 16_000

            enum CodingKeys: String, CodingKey {
                case format
                case sampleRate = "sample_rate"
            }
        }

        let taskGroup = "audio"
        let task = "asr"
        let function = "recognition"
        let model: String
        let parameters = Parameters()
        let input = EmptyInput()

        enum CodingKeys: String, CodingKey {
            case taskGroup = "task_group"
            case task
            case function
            case model
            case parameters
            case input
        }
    }

    let header: Header
    let payload: Payload

    init(taskID: UUID, model: String) {
        self.header = Header(taskID: taskID.uuidString)
        self.payload = Payload(model: model)
    }
}

struct DashScopeASRFinishTaskEvent: Encodable {
    struct EmptyInput: Encodable {}

    struct Header: Encodable {
        let action = "finish-task"
        let taskID: String
        let streaming = "duplex"

        enum CodingKeys: String, CodingKey {
            case action
            case taskID = "task_id"
            case streaming
        }
    }

    struct Payload: Encodable {
        let input = EmptyInput()
    }

    let header: Header
    let payload = Payload()

    init(taskID: UUID) {
        self.header = Header(taskID: taskID.uuidString)
    }
}

enum DashScopeASRServerEvent: Equatable {
    case taskStarted
    case resultGenerated(text: String, isFinalSentence: Bool)
    case taskFinished
    case taskFailed(String)
    case ignored(String)

    static func parse(_ data: Data) throws -> DashScopeASRServerEvent {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let header = root["header"] as? [String: Any],
            let eventName = header["event"] as? String
        else {
            throw AppError.asrFailed("服务端事件格式无效")
        }

        switch eventName {
        case "task-started":
            return .taskStarted
        case "result-generated":
            return try parseResultGenerated(from: root)
        case "task-finished":
            return .taskFinished
        case "task-failed":
            let payload = root["payload"] as? [String: Any]
            return .taskFailed(taskFailedMessage(header: header, payload: payload))
        default:
            return .ignored(eventName)
        }
    }

    private static func parseResultGenerated(from root: [String: Any]) throws -> DashScopeASRServerEvent {
        guard
            let payload = root["payload"] as? [String: Any],
            let output = payload["output"] as? [String: Any],
            let sentence = output["sentence"] as? [String: Any],
            let text = sentence["text"] as? String
        else {
            throw AppError.asrFailed("服务端事件格式无效")
        }

        let isFinalSentence = sentence["sentence_end"] as? Bool ?? false
        return .resultGenerated(text: text, isFinalSentence: isFinalSentence)
    }

    private static func taskFailedMessage(header: [String: Any], payload: [String: Any]?) -> String {
        let headerMessage = header["error_message"] as? String
        let headerCode = header["error_code"] as? String

        switch (headerCode, headerMessage) {
        case (.some(let code), .some(let message)):
            return "\(code): \(message)"
        case (.some(let code), .none):
            return code
        case (.none, .some(let message)):
            return message
        case (.none, .none):
            return (payload?["error_message"] as? String) ?? "语音识别失败"
        }
    }
}
