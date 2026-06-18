import XCTest
@testable import Fusheng

final class DashScopeASRClientTests: XCTestCase {
    func testRecognizeSendsControlEventsAsStringFramesAndAudioAsDataFrames() async throws {
        let task = FakeWebSocketTask(messages: [
            .string(#"{ "header": { "event": "task-started" }, "payload": {} }"#),
            .string(#"{ "header": { "event": "task-finished" }, "payload": {} }"#)
        ])
        let session = FakeWebSocketSession(task: task)
        let client = DashScopeASRClient(session: session, startTimeout: 1, finishTimeout: 1)
        let audio = AsyncThrowingStream<Data, Error> { continuation in
            continuation.yield(Data([0x01, 0x02]))
            continuation.finish()
        }

        _ = try await client.recognize(
            audioChunks: audio,
            model: "fun-asr-realtime",
            apiKey: "test-key",
            onPartialResult: { _ in }
        )

        XCTAssertEqual(session.request?.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        XCTAssertEqual(task.sentMessages.count, 3)

        guard case .string(let runTaskJSON) = task.sentMessages[0] else {
            return XCTFail("Expected run-task control message to be a string frame")
        }
        XCTAssertTrue(runTaskJSON.contains(#""action":"run-task""#))

        guard case .data(let audioData) = task.sentMessages[1] else {
            return XCTFail("Expected audio chunk to be a data frame")
        }
        XCTAssertEqual(audioData, Data([0x01, 0x02]))

        guard case .string(let finishTaskJSON) = task.sentMessages[2] else {
            return XCTFail("Expected finish-task control message to be a string frame")
        }
        XCTAssertTrue(finishTaskJSON.contains(#""action":"finish-task""#))
    }

    func testRecognizeTimesOutWaitingForTaskStarted() async {
        let task = FakeWebSocketTask(messages: [], receiveWatchdog: 0.2)
        let session = FakeWebSocketSession(task: task)
        let client = DashScopeASRClient(session: session, startTimeout: 0.01, finishTimeout: 1)
        let audio = AsyncThrowingStream<Data, Error> { continuation in
            continuation.finish()
        }

        let start = Date()
        do {
            _ = try await client.recognize(
                audioChunks: audio,
                model: "fun-asr-realtime",
                apiKey: "test-key",
                onPartialResult: { _ in }
            )
            XCTFail("Expected AppError.asrFailed")
        } catch let error as AppError {
            guard case .asrFailed(let message) = error else {
                return XCTFail("Expected AppError.asrFailed, got \(error)")
            }
            XCTAssertTrue(message.contains("task-started"))
            XCTAssertLessThan(Date().timeIntervalSince(start), 0.15)
            XCTAssertTrue(task.didCancel)
        } catch {
            XCTFail("Expected AppError.asrFailed, got \(type(of: error)): \(error)")
        }
    }

    func testRecognizePublishesPartialResultsBeforeReturningFinalText() async throws {
        let task = FakeWebSocketTask(messages: [
            .string(#"{ "header": { "event": "task-started" }, "payload": {} }"#),
            .string(#"{ "header": { "event": "result-generated" }, "payload": { "output": { "sentence": { "text": "我", "sentence_end": false } } } }"#),
            .string(#"{ "header": { "event": "result-generated" }, "payload": { "output": { "sentence": { "text": "我要输入", "sentence_end": true } } } }"#),
            .string(#"{ "header": { "event": "task-finished" }, "payload": {} }"#)
        ])
        let session = FakeWebSocketSession(task: task)
        let client = DashScopeASRClient(session: session, startTimeout: 1, finishTimeout: 1)
        let audio = AsyncThrowingStream<Data, Error> { continuation in
            continuation.yield(Data([0x01]))
            continuation.finish()
        }
        let partialCollector = PartialCollector()

        let result = try await client.recognize(
            audioChunks: audio,
            model: "fun-asr-realtime",
            apiKey: "test-key",
            onPartialResult: { partial in
                await partialCollector.append(partial)
            }
        )

        let partials = await partialCollector.values
        XCTAssertEqual(partials, ["我", "我要输入"])
        XCTAssertEqual(result.rawText, "我要输入")
        XCTAssertEqual(result.partialText, "我要输入")
    }

    func testRecognizeDoesNotDuplicateCumulativeFinalText() async throws {
        let task = FakeWebSocketTask(messages: [
            .string(#"{ "header": { "event": "task-started" }, "payload": {} }"#),
            .string(#"{ "header": { "event": "result-generated" }, "payload": { "output": { "sentence": { "text": "你能听到我说话吗？", "sentence_end": true } } } }"#),
            .string(#"{ "header": { "event": "result-generated" }, "payload": { "output": { "sentence": { "text": "你能听到我说话吗？你知道我在说什么吗？", "sentence_end": true } } } }"#),
            .string(#"{ "header": { "event": "task-finished" }, "payload": {} }"#)
        ])
        let session = FakeWebSocketSession(task: task)
        let client = DashScopeASRClient(session: session, startTimeout: 1, finishTimeout: 1)
        let audio = AsyncThrowingStream<Data, Error> { continuation in
            continuation.yield(Data([0x01]))
            continuation.finish()
        }

        let result = try await client.recognize(
            audioChunks: audio,
            model: "fun-asr-realtime",
            apiKey: "test-key",
            onPartialResult: { _ in }
        )

        XCTAssertEqual(result.rawText, "你能听到我说话吗？你知道我在说什么吗？")
        XCTAssertEqual(result.partialText, "你能听到我说话吗？你知道我在说什么吗？")
    }

    func testRecognizeUsesLatestTextWhenTaskFinishedTimesOutAfterAudioEnds() async throws {
        let task = FakeWebSocketTask(
            messages: [
                .string(#"{ "header": { "event": "task-started" }, "payload": {} }"#)
            ],
            messagesAfterFinishTask: [
                .string(#"{ "header": { "event": "result-generated" }, "payload": { "output": { "sentence": { "text": "长语音已经识别出来", "sentence_end": true } } } }"#)
            ]
        )
        let session = FakeWebSocketSession(task: task)
        let client = DashScopeASRClient(session: session, startTimeout: 1, finishTimeout: 0.03)
        let audio = AsyncThrowingStream<Data, Error> { continuation in
            continuation.yield(Data([0x01]))
            continuation.finish()
        }

        let result = try await client.recognize(
            audioChunks: audio,
            model: "fun-asr-realtime",
            apiKey: "test-key",
            onPartialResult: { _ in }
        )

        XCTAssertEqual(result.rawText, "长语音已经识别出来")
        XCTAssertEqual(result.partialText, "长语音已经识别出来")
    }

    func testLongRecordingDoesNotStartFinishTimeoutBeforeFinishTaskIsSent() async throws {
        let task = FakeWebSocketTask(
            messages: [
                .string(#"{ "header": { "event": "task-started" }, "payload": {} }"#)
            ],
            messagesAfterFinishTask: [
                .string(#"{ "header": { "event": "result-generated" }, "payload": { "output": { "sentence": { "text": "长语音识别完成", "sentence_end": true } } } }"#),
                .string(#"{ "header": { "event": "task-finished" }, "payload": {} }"#)
            ]
        )
        let session = FakeWebSocketSession(task: task)
        let client = DashScopeASRClient(session: session, startTimeout: 1, finishTimeout: 0.03)
        let audio = AsyncThrowingStream<Data, Error> { continuation in
            Task {
                continuation.yield(Data([0x01]))
                try? await Task.sleep(nanoseconds: 80_000_000)
                continuation.yield(Data([0x02]))
                continuation.finish()
            }
        }

        let result = try await client.recognize(
            audioChunks: audio,
            model: "fun-asr-realtime",
            apiKey: "test-key",
            onPartialResult: { _ in }
        )

        XCTAssertEqual(result.rawText, "长语音识别完成")
        XCTAssertEqual(result.partialText, "长语音识别完成")
        XCTAssertFalse(task.cancelCloseCodes.contains(.goingAway))
    }

    func testRecognizeIgnoresHeartbeatResultEventsWithoutClearingLatestText() async throws {
        let task = FakeWebSocketTask(messages: [
            .string(#"{ "header": { "event": "task-started" }, "payload": {} }"#),
            .string(#"{ "header": { "event": "result-generated" }, "payload": { "output": { "sentence": { "text": "我要输入", "sentence_end": false } } } }"#),
            .string(#"{ "header": { "event": "result-generated" }, "payload": { "output": { "sentence": { "text": "", "heartbeat": true, "sentence_end": false } } } }"#),
            .string(#"{ "header": { "event": "task-finished" }, "payload": {} }"#)
        ])
        let session = FakeWebSocketSession(task: task)
        let client = DashScopeASRClient(session: session, startTimeout: 1, finishTimeout: 1)
        let audio = AsyncThrowingStream<Data, Error> { continuation in
            continuation.yield(Data([0x01]))
            continuation.finish()
        }
        let partialCollector = PartialCollector()

        let result = try await client.recognize(
            audioChunks: audio,
            model: "fun-asr-realtime",
            apiKey: "test-key",
            onPartialResult: { partial in
                await partialCollector.append(partial)
            }
        )

        let partials = await partialCollector.values
        XCTAssertEqual(partials, ["我要输入"])
        XCTAssertEqual(result.rawText, "我要输入")
        XCTAssertEqual(result.partialText, "我要输入")
    }
}

private actor PartialCollector {
    private var storedValues: [String] = []

    var values: [String] {
        storedValues
    }

    func append(_ value: String) {
        storedValues.append(value)
    }
}

private final class FakeWebSocketSession: WebSocketSessioning {
    let task: FakeWebSocketTask
    private(set) var request: URLRequest?

    init(task: FakeWebSocketTask) {
        self.task = task
    }

    func webSocketTask(with request: URLRequest) -> WebSocketTasking {
        self.request = request
        return task
    }
}

private final class FakeWebSocketTask: WebSocketTasking {
    private var messages: [URLSessionWebSocketTask.Message]
    private let messagesAfterFinishTask: [URLSessionWebSocketTask.Message]
    private let receiveWatchdog: TimeInterval?
    private let lock = NSLock()
    private(set) var sentMessages: [URLSessionWebSocketTask.Message] = []
    private(set) var didResume = false
    private(set) var didCancel = false
    private(set) var cancelCloseCodes: [URLSessionWebSocketTask.CloseCode] = []
    private var receiveContinuation: CheckedContinuation<URLSessionWebSocketTask.Message, Error>?

    init(
        messages: [URLSessionWebSocketTask.Message],
        messagesAfterFinishTask: [URLSessionWebSocketTask.Message] = [],
        receiveWatchdog: TimeInterval? = nil
    ) {
        self.messages = messages
        self.messagesAfterFinishTask = messagesAfterFinishTask
        self.receiveWatchdog = receiveWatchdog
    }

    func resume() {
        didResume = true
    }

    func send(_ message: URLSessionWebSocketTask.Message) async throws {
        lock.withLock {
            sentMessages.append(message)
        }

        if case .string(let text) = message, text.contains(#""action":"finish-task""#) {
            for message in messagesAfterFinishTask {
                enqueue(message)
            }
        }
    }

    func receive() async throws -> URLSessionWebSocketTask.Message {
        if let message = lock.withLock({ messages.isEmpty ? nil : messages.removeFirst() }) {
            return message
        }

        return try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                receiveContinuation = continuation
            }
            if let receiveWatchdog {
                Task {
                    try? await Task.sleep(nanoseconds: UInt64(receiveWatchdog * 1_000_000_000))
                    self.finishReceive(throwing: AppError.asrFailed("receive watchdog expired"))
                }
            }
        }
    }

    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        didCancel = true
        cancelCloseCodes.append(closeCode)
        finishReceive(throwing: AppError.asrFailed("socket cancelled"))
    }

    private func enqueue(_ message: URLSessionWebSocketTask.Message) {
        let continuation: CheckedContinuation<URLSessionWebSocketTask.Message, Error>? = lock.withLock {
            if let receiveContinuation {
                self.receiveContinuation = nil
                return receiveContinuation
            }

            messages.append(message)
            return nil
        }

        continuation?.resume(returning: message)
    }

    private func finishReceive(throwing error: Error) {
        let continuation = lock.withLock {
            defer { receiveContinuation = nil }
            return receiveContinuation
        }
        continuation?.resume(throwing: error)
    }
}
