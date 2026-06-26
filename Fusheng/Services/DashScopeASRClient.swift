import Foundation

private struct ASRTimeout: Error {}

private enum ASRStreamingResult {
    case finishTaskSent
    case recognition(RecognitionResult)
}

private actor RecognitionAccumulator {
    private var finalText = ""
    private var partialText = ""

    func record(text: String, isFinalSentence: Bool) -> String {
        if isFinalSentence {
            if text.hasPrefix(finalText) {
                finalText = text
            } else {
                finalText += text
            }

            partialText = finalText
            return partialText
        }

        if finalText.isEmpty || text.hasPrefix(finalText) {
            partialText = text
        } else {
            partialText = finalText + text
        }

        return partialText
    }

    func resultIfAvailable() -> RecognitionResult? {
        let rawText = partialText.isEmpty ? finalText : partialText
        guard !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return RecognitionResult(rawText: rawText, partialText: partialText)
    }
}

protocol WebSocketTasking {
    func resume()
    func send(_ message: URLSessionWebSocketTask.Message) async throws
    func receive() async throws -> URLSessionWebSocketTask.Message
    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?)
}

protocol WebSocketSessioning {
    func webSocketTask(with request: URLRequest) -> WebSocketTasking
}

extension URLSessionWebSocketTask: WebSocketTasking {}

private struct URLSessionWebSocketSession: WebSocketSessioning {
    let session: URLSession

    func webSocketTask(with request: URLRequest) -> WebSocketTasking {
        session.webSocketTask(with: request)
    }
}

struct DashScopeASRClient: ASRRecognizing {
    private let session: WebSocketSessioning
    private let endpoint = URL(string: "wss://dashscope.aliyuncs.com/api-ws/v1/inference")!
    private let startTimeout: TimeInterval
    private let finishTimeout: TimeInterval

    init(session: URLSession = .shared, startTimeout: TimeInterval = 10, finishTimeout: TimeInterval = 180) {
        self.session = URLSessionWebSocketSession(session: session)
        self.startTimeout = startTimeout
        self.finishTimeout = finishTimeout
    }

    init(session: WebSocketSessioning, startTimeout: TimeInterval = 10, finishTimeout: TimeInterval = 180) {
        self.session = session
        self.startTimeout = startTimeout
        self.finishTimeout = finishTimeout
    }

    func recognize(
        audioChunks: AsyncThrowingStream<Data, Error>,
        model: String,
        apiKey: String,
        onPartialResult: @escaping @Sendable (String) async -> Void
    ) async throws -> RecognitionResult {
        let taskID = UUID()
        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let socket = session.webSocketTask(with: request)
        socket.resume()
        defer {
            socket.cancel(with: .normalClosure, reason: nil)
        }

        try await send(DashScopeASRRunTaskEvent(taskID: taskID, model: model), using: socket)
        try await withTimeout(seconds: startTimeout, message: "等待 task-started 超时", onTimeout: {
            socket.cancel(with: .goingAway, reason: nil)
        }) {
            try await waitForTaskStarted(using: socket)
        }

        let accumulator = RecognitionAccumulator()

        return try await withThrowingTaskGroup(of: ASRStreamingResult.self) { group in
            group.addTask {
                for try await chunk in audioChunks {
                    try await socket.send(.data(chunk))
                }

                try await send(DashScopeASRFinishTaskEvent(taskID: taskID), using: socket)
                return .finishTaskSent
            }

            group.addTask {
                let result = try await collectRecognitionResult(
                    using: socket,
                    accumulator: accumulator,
                    onPartialResult: onPartialResult
                )
                return .recognition(result)
            }

            var didStartFinishTimeout = false

            do {
                while let result = try await group.next() {
                    switch result {
                    case .recognition(let result):
                        group.cancelAll()
                        return result
                    case .finishTaskSent:
                        guard !didStartFinishTimeout else { continue }
                        didStartFinishTimeout = true
                        group.addTask {
                            let nanoseconds = UInt64(max(finishTimeout, 0) * 1_000_000_000)
                            try await Task.sleep(nanoseconds: nanoseconds)
                            if let fallbackResult = await accumulator.resultIfAvailable() {
                                Task {
                                    try? await Task.sleep(nanoseconds: 1_000_000)
                                    socket.cancel(with: .goingAway, reason: nil)
                                }
                                return .recognition(fallbackResult)
                            }
                            throw ASRTimeout()
                        }
                    }
                }

                throw AppError.asrFailed("识别任务异常结束")
            } catch is ASRTimeout {
                socket.cancel(with: .goingAway, reason: nil)
                group.cancelAll()
                throw AppError.asrFailed("等待 task-finished 超时")
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }

    private func send<Event: Encodable>(_ event: Event, using socket: WebSocketTasking) async throws {
        do {
            let data = try JSONEncoder().encode(event)
            guard let json = String(data: data, encoding: .utf8) else {
                throw AppError.asrFailed("控制事件编码失败")
            }
            try await socket.send(.string(json))
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.asrFailed("发送识别事件失败：\(error.localizedDescription)")
        }
    }

    private func waitForTaskStarted(using socket: WebSocketTasking) async throws {
        while true {
            let event = try await receiveEvent(using: socket)
            switch event {
            case .taskStarted:
                return
            case .taskFailed(let message):
                throw AppError.asrFailed(message)
            case .resultGenerated, .taskFinished, .ignored:
                continue
            }
        }
    }

    private func collectRecognitionResult(
        using socket: WebSocketTasking,
        accumulator: RecognitionAccumulator,
        onPartialResult: @escaping @Sendable (String) async -> Void
    ) async throws -> RecognitionResult {
        while true {
            let event = try await receiveEvent(using: socket)
            switch event {
            case .resultGenerated(let text, let isFinalSentence):
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    continue
                }
                let partialText = await accumulator.record(text: text, isFinalSentence: isFinalSentence)
                await onPartialResult(partialText)
            case .taskFinished:
                return await accumulator.resultIfAvailable() ?? RecognitionResult(rawText: "", partialText: "")
            case .taskFailed(let message):
                throw AppError.asrFailed(message)
            case .taskStarted, .ignored:
                continue
            }
        }
    }

    private func receiveEvent(using socket: WebSocketTasking) async throws -> DashScopeASRServerEvent {
        do {
            let message = try await socket.receive()
            switch message {
            case .data(let data):
                return try DashScopeASRServerEvent.parse(data)
            case .string(let text):
                return try DashScopeASRServerEvent.parse(Data(text.utf8))
            @unknown default:
                return .ignored("unknown-message")
            }
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.asrFailed("接收识别事件失败：\(error.localizedDescription)")
        }
    }

    private func withTimeout<T>(
        seconds: TimeInterval,
        message: String,
        onTimeout: @escaping () -> Void,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                let nanoseconds = UInt64(max(seconds, 0) * 1_000_000_000)
                try await Task.sleep(nanoseconds: nanoseconds)
                throw ASRTimeout()
            }

            do {
                guard let result = try await group.next() else {
                    throw AppError.asrFailed(message)
                }
                group.cancelAll()
                return result
            } catch is ASRTimeout {
                onTimeout()
                group.cancelAll()
                throw AppError.asrFailed(message)
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }
}
