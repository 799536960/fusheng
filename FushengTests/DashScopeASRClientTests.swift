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

        _ = try await client.recognize(audioChunks: audio, model: "fun-asr-realtime", apiKey: "test-key")

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
            _ = try await client.recognize(audioChunks: audio, model: "fun-asr-realtime", apiKey: "test-key")
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
    private let receiveWatchdog: TimeInterval?
    private let lock = NSLock()
    private(set) var sentMessages: [URLSessionWebSocketTask.Message] = []
    private(set) var didResume = false
    private(set) var didCancel = false
    private var receiveContinuation: CheckedContinuation<URLSessionWebSocketTask.Message, Error>?

    init(messages: [URLSessionWebSocketTask.Message], receiveWatchdog: TimeInterval? = nil) {
        self.messages = messages
        self.receiveWatchdog = receiveWatchdog
    }

    func resume() {
        didResume = true
    }

    func send(_ message: URLSessionWebSocketTask.Message) async throws {
        sentMessages.append(message)
    }

    func receive() async throws -> URLSessionWebSocketTask.Message {
        if messages.isEmpty {
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
        return messages.removeFirst()
    }

    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        didCancel = true
        finishReceive(throwing: AppError.asrFailed("socket cancelled"))
    }

    private func finishReceive(throwing error: Error) {
        let continuation = lock.withLock {
            defer { receiveContinuation = nil }
            return receiveContinuation
        }
        continuation?.resume(throwing: error)
    }
}
