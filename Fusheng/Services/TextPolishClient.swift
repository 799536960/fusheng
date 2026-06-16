import Foundation

enum TextPolishPrompt {
    static func systemPrompt(for mode: TextPolishMode) -> String {
        switch mode {
        case .original:
            return "你是语音转文字清理助手。保留原意和口语表达，只补齐必要标点，不扩写。"
        case .clean:
            return "你是语音转文字清理助手。保留原意，删除明显口头禅和重复词，补充自然标点，让文本可直接发送。"
        case .professional:
            return "你是专业写作助手。保留原意，修正明显错字，删除明显口头禅，改写成清晰、正式、可直接用于需求、技术说明或会议纪要的文本。"
        case .concise:
            return "你是简洁表达助手。保留关键意思，删除冗余表达，把语音内容压缩成更短、更清楚的文本。"
        }
    }
}

enum TextPolishRequestBuilder {
    private static let endpoint = URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")!

    static func request(rawText: String, mode: TextPolishMode, model: String, apiKey: String) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ChatCompletionRequest(
            model: model,
            messages: [
                .init(role: "system", content: TextPolishPrompt.systemPrompt(for: mode)),
                .init(role: "user", content: rawText)
            ],
            temperature: 0.2
        )
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }
}

private struct ChatCompletionRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
    let temperature: Double
}

private struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String
        }

        let message: Message
    }

    let choices: [Choice]
}

struct TextPolishClient: TextPolishing {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func polish(rawText: String, mode: TextPolishMode, model: String, apiKey: String) async throws -> String {
        do {
            let request = try TextPolishRequestBuilder.request(rawText: rawText, mode: mode, model: model, apiKey: apiKey)
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
                throw AppError.polishFailed("HTTP 响应异常")
            }

            let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
            guard let content = decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines), !content.isEmpty else {
                throw AppError.polishFailed("模型返回空文本")
            }
            return content
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.polishFailed("请求或解析失败：\(error.localizedDescription)")
        }
    }
}
