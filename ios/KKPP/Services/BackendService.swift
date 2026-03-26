import Foundation

struct BackendStreamResult {
    let reply: String
    let structuredAction: StructuredAction?
}

struct HealthResponse: Decodable {
    let ok: Bool
    let service: String
    let timezone: String
    let timestamp: String
}

final class BackendService {
    private let session: URLSession
    private let baseURL: URL
    private let decoder = JSONDecoder()

    init(baseURLString: String = "http://127.0.0.1:3000") {
        self.baseURL = URL(string: baseURLString) ?? URL(string: "http://127.0.0.1:3000")!
        self.session = URLSession(configuration: .default)
    }

    var baseURLString: String {
        baseURL.absoluteString
    }

    func healthCheck() async throws -> HealthResponse {
        let (data, response) = try await session.data(from: baseURL.appending(path: "/health"))
        try validate(response: response, data: data)
        return try decoder.decode(HealthResponse.self, from: data)
    }

    func process(request: ProcessRequest) async throws -> ProcessResponse {
        var urlRequest = URLRequest(url: baseURL.appending(path: "/process"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await session.data(for: urlRequest)
        try validate(response: response, data: data)
        return try decoder.decode(ProcessResponse.self, from: data)
    }

    func streamProcess(
        request: ProcessRequest,
        onAction: @escaping @Sendable (StructuredAction?) -> Void,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> BackendStreamResult {
        var urlRequest = URLRequest(url: baseURL.appending(path: "/process/stream"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        urlRequest.timeoutInterval = 60
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (bytes, response) = try await session.bytes(for: urlRequest)
        try validate(response: response, data: Data())

        var finalReply = ""
        var finalAction: StructuredAction?

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = line.replacingOccurrences(of: "data: ", with: "")
            guard let data = payload.data(using: .utf8) else { continue }
            let event = try decoder.decode(StreamingEvent.self, from: data)

            switch event.type {
            case "action":
                finalAction = event.structuredAction
                onAction(event.structuredAction)
            case "token":
                let token = event.content ?? ""
                finalReply += token
                onToken(token)
            case "done":
                return BackendStreamResult(
                    reply: event.reply ?? finalReply,
                    structuredAction: event.structuredAction ?? finalAction
                )
            case "error":
                throw NSError(domain: "BackendService", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: event.message ?? "后端服务暂时不可用。"
                ])
            default:
                continue
            }
        }

        return BackendStreamResult(reply: finalReply, structuredAction: finalAction)
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "BackendService", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "无法识别服务器响应。"
            ])
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "服务器请求失败。"
            throw NSError(domain: "BackendService", code: httpResponse.statusCode, userInfo: [
                NSLocalizedDescriptionKey: message
            ])
        }
    }
}
