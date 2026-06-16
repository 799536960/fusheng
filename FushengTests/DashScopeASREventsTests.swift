import XCTest
@testable import Fusheng

final class DashScopeASREventsTests: XCTestCase {
    func testBuildRunTaskEvent() throws {
        let event = DashScopeASRRunTaskEvent(taskID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, model: "fun-asr-realtime")
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(ControlEvent.self, from: data)

        XCTAssertEqual(decoded.header.action, "run-task")
        XCTAssertEqual(decoded.header.taskID, "00000000-0000-0000-0000-000000000001")
        XCTAssertEqual(decoded.header.streaming, "duplex")
        XCTAssertEqual(decoded.payload.taskGroup, "audio")
        XCTAssertEqual(decoded.payload.task, "asr")
        XCTAssertEqual(decoded.payload.function, "recognition")
        XCTAssertEqual(decoded.payload.model, "fun-asr-realtime")
        XCTAssertEqual(decoded.payload.parameters.format, "pcm")
        XCTAssertEqual(decoded.payload.parameters.sampleRate, 16_000)
        XCTAssertNotNil(decoded.payload.input)
    }

    func testBuildFinishTaskEvent() throws {
        let event = DashScopeASRFinishTaskEvent(taskID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(FinishEvent.self, from: data)

        XCTAssertEqual(decoded.header.action, "finish-task")
        XCTAssertEqual(decoded.header.taskID, "00000000-0000-0000-0000-000000000001")
        XCTAssertEqual(decoded.header.streaming, "duplex")
        XCTAssertNotNil(decoded.payload.input)
    }

    func testParseResultGeneratedEvent() throws {
        let json = """
        {
          "header": { "event": "result-generated", "task_id": "task-1" },
          "payload": { "output": { "sentence": { "text": "你好世界", "sentence_end": true } } }
        }
        """

        let event = try DashScopeASRServerEvent.parse(Data(json.utf8))

        XCTAssertEqual(event, .resultGenerated(text: "你好世界", isFinalSentence: true))
    }

    func testParseTaskFinishedEvent() throws {
        let json = """
        { "header": { "event": "task-finished", "task_id": "task-1" }, "payload": {} }
        """

        let event = try DashScopeASRServerEvent.parse(Data(json.utf8))

        XCTAssertEqual(event, .taskFinished)
    }

    func testParseTaskStartedEvent() throws {
        let json = """
        { "header": { "event": "task-started", "task_id": "task-1" }, "payload": {} }
        """

        let event = try DashScopeASRServerEvent.parse(Data(json.utf8))

        XCTAssertEqual(event, .taskStarted)
    }

    func testParseTaskFailedEventUsesErrorMessage() throws {
        let json = """
        { "header": { "event": "task-failed", "task_id": "task-1" }, "payload": { "error_message": "bad audio" } }
        """

        let event = try DashScopeASRServerEvent.parse(Data(json.utf8))

        XCTAssertEqual(event, .taskFailed("bad audio"))
    }

    func testParseTaskFailedEventPrefersHeaderErrorMessageAndCode() throws {
        let json = """
        {
          "header": {
            "event": "task-failed",
            "task_id": "task-1",
            "error_code": "InvalidAudio",
            "error_message": "bad audio"
          },
          "payload": { "error_message": "payload message" }
        }
        """

        let event = try DashScopeASRServerEvent.parse(Data(json.utf8))

        XCTAssertEqual(event, .taskFailed("InvalidAudio: bad audio"))
    }

    func testParseUnknownEventReturnsIgnored() throws {
        let json = """
        { "header": { "event": "heartbeat", "task_id": "task-1" }, "payload": {} }
        """

        let event = try DashScopeASRServerEvent.parse(Data(json.utf8))

        XCTAssertEqual(event, .ignored("heartbeat"))
    }

    func testParseInvalidJSONThrowsASRFailed() {
        XCTAssertThrowsError(try DashScopeASRServerEvent.parse(Data("not-json".utf8))) { error in
            XCTAssertEqual(error as? AppError, .asrFailed("服务端事件格式无效"))
        }
    }

    func testParseMissingHeaderThrowsASRFailed() {
        let json = """
        { "payload": {} }
        """

        XCTAssertThrowsError(try DashScopeASRServerEvent.parse(Data(json.utf8))) { error in
            XCTAssertEqual(error as? AppError, .asrFailed("服务端事件格式无效"))
        }
    }
}

private struct ControlEvent: Decodable {
    struct Header: Decodable {
        let action: String
        let taskID: String
        let streaming: String

        enum CodingKeys: String, CodingKey {
            case action
            case taskID = "task_id"
            case streaming
        }
    }

    struct Payload: Decodable {
        struct Parameters: Decodable {
            let format: String
            let sampleRate: Int

            enum CodingKeys: String, CodingKey {
                case format
                case sampleRate = "sample_rate"
            }
        }

        let taskGroup: String
        let task: String
        let function: String
        let model: String
        let parameters: Parameters
        let input: [String: String]?

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
}

private struct FinishEvent: Decodable {
    struct Header: Decodable {
        let action: String
        let taskID: String
        let streaming: String

        enum CodingKeys: String, CodingKey {
            case action
            case taskID = "task_id"
            case streaming
        }
    }

    struct Payload: Decodable {
        let input: [String: String]?
    }

    let header: Header
    let payload: Payload
}
