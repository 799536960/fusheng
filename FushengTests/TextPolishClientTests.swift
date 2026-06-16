import XCTest
@testable import Fusheng

final class TextPolishClientTests: XCTestCase {
    override func tearDown() {
        FakeURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testSystemPromptForCleanMode() {
        let prompt = TextPolishPrompt.systemPrompt(for: .clean)
        XCTAssertTrue(prompt.contains("保留原意"))
        XCTAssertTrue(prompt.contains("删除明显口头禅"))
    }

    func testRequestBodyContainsExpectedChatCompletionJSONWithoutAPIKey() throws {
        let request = try TextPolishRequestBuilder.request(
            rawText: "嗯这个明天我们开会说",
            mode: .professional,
            model: "qwen-plus",
            apiKey: "secret-key"
        )

        let body = try XCTUnwrap(request.httpBody)
        let bodyString = String(data: body, encoding: .utf8)!
        let decoded = try JSONDecoder().decode(RequestBody.self, from: body)

        XCTAssertEqual(request.url?.absoluteString, "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret-key")
        XCTAssertFalse(bodyString.contains("secret-key"))
        XCTAssertEqual(decoded.model, "qwen-plus")
        XCTAssertEqual(decoded.messages.count, 2)
        XCTAssertEqual(decoded.messages[0].role, "system")
        XCTAssertEqual(decoded.messages[0].content, TextPolishPrompt.systemPrompt(for: .professional))
        XCTAssertEqual(decoded.messages[1].role, "user")
        XCTAssertEqual(decoded.messages[1].content, "嗯这个明天我们开会说")
        XCTAssertEqual(decoded.temperature, 0.2)
    }

    func testClientReturnsTrimmedFirstChoiceContent() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FakeURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = TextPolishClient(session: session)

        FakeURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            let data = #"{"choices":[{"message":{"content":"  明天我们开会说。  "}}]}"#.data(using: .utf8)!
            return (response, data)
        }

        let result = try await client.polish(
            rawText: "嗯这个明天我们开会说",
            mode: .clean,
            model: "qwen-plus",
            apiKey: "test-key"
        )

        XCTAssertEqual(result, "明天我们开会说。")
    }

    func testClientThrowsPolishFailedForNon2xxResponse() async throws {
        let client = makeClient()
        FakeURLProtocol.requestHandler = { request in
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Data())
        }

        await assertPolishFailed {
            _ = try await client.polish(rawText: "hello", mode: .clean, model: "qwen-plus", apiKey: "test-key")
        }
    }

    func testClientThrowsPolishFailedForEmptyContent() async throws {
        let client = makeClient()
        FakeURLProtocol.requestHandler = { request in
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            let data = #"{"choices":[{"message":{"content":"   \n  "}}]}"#.data(using: .utf8)!
            return (response, data)
        }

        await assertPolishFailed {
            _ = try await client.polish(rawText: "hello", mode: .clean, model: "qwen-plus", apiKey: "test-key")
        }
    }

    func testClientThrowsPolishFailedForMalformedResponseJSON() async throws {
        let client = makeClient()
        FakeURLProtocol.requestHandler = { request in
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            let data = #"{"choices":"not-an-array"}"#.data(using: .utf8)!
            return (response, data)
        }

        await assertPolishFailed {
            _ = try await client.polish(rawText: "hello", mode: .clean, model: "qwen-plus", apiKey: "test-key")
        }
    }

    func testClientThrowsPolishFailedForTransportError() async throws {
        let client = makeClient()
        FakeURLProtocol.requestHandler = { _ in
            throw URLError(.notConnectedToInternet)
        }

        await assertPolishFailed {
            _ = try await client.polish(rawText: "hello", mode: .clean, model: "qwen-plus", apiKey: "test-key")
        }
    }

    private func makeClient() -> TextPolishClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FakeURLProtocol.self]
        return TextPolishClient(session: URLSession(configuration: configuration))
    }

    private func assertPolishFailed(
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("Expected AppError.polishFailed", file: file, line: line)
        } catch let error as AppError {
            guard case .polishFailed(let message) = error else {
                XCTFail("Expected AppError.polishFailed, got \(error)", file: file, line: line)
                return
            }
            XCTAssertFalse(message.isEmpty, file: file, line: line)
        } catch {
            XCTFail("Expected AppError.polishFailed, got \(type(of: error)): \(error)", file: file, line: line)
        }
    }
}

private struct RequestBody: Decodable {
    struct Message: Decodable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
    let temperature: Double
}

private final class FakeURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let requestHandler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: AppError.polishFailed("Missing fake request handler"))
            return
        }

        do {
            let (response, data) = try requestHandler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
