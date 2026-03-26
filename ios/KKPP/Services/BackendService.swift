import Foundation

struct BackendStreamResult {
    let reply: String
    let structuredAction: StructuredAction?
    let structuredActions: [StructuredAction]?
    let collaboration: CollaborationPayload?
}

struct HealthResponse: Decodable {
    let ok: Bool
    let service: String
    let timezone: String
    let timestamp: String
    let transcriptionAvailable: Bool?
}

struct TranscriptionResponse: Decodable {
    let text: String
    let provider: String?
    let model: String?
}

final class BackendService {
    private let session: URLSession
    private let baseURL: URL
    private let decoder = JSONDecoder()

    init(baseURLString: String = "http://127.0.0.1:3000") {
        self.baseURL = URL(string: baseURLString) ?? URL(string: "http://127.0.0.1:3000")!
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 180
        self.session = URLSession(configuration: configuration)
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
        onToken: @escaping @Sendable (String) -> Void,
        onCollaboration: @escaping @Sendable (CollaborationPayload?) -> Void,
        onStage: @escaping @Sendable (String) -> Void
    ) async throws -> BackendStreamResult {
        var urlRequest = URLRequest(url: baseURL.appending(path: "/process/stream"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        urlRequest.timeoutInterval = 120
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (bytes, response) = try await session.bytes(for: urlRequest)
        try validate(response: response, data: Data())

        var finalReply = ""
        var finalAction: StructuredAction?
        var finalActions: [StructuredAction]?
        var finalCollaboration: CollaborationPayload?

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = line.replacingOccurrences(of: "data: ", with: "")
            guard let data = payload.data(using: .utf8) else { continue }
            let event = try decoder.decode(StreamingEvent.self, from: data)

            switch event.type {
            case "stage":
                if let message = event.message, !message.isEmpty {
                    onStage(message)
                }
            case "action":
                finalAction = event.structuredAction
                finalActions = event.structuredActions
                finalCollaboration = event.collaboration
                onAction(event.structuredAction)
                onCollaboration(event.collaboration)
            case "token":
                let token = event.content ?? ""
                finalReply += token
                onToken(token)
            case "done":
                return BackendStreamResult(
                    reply: event.reply ?? finalReply,
                    structuredAction: event.structuredAction ?? finalAction,
                    structuredActions: event.structuredActions ?? finalActions,
                    collaboration: event.collaboration ?? finalCollaboration
                )
            case "error":
                throw NSError(domain: "BackendService", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: event.message ?? "后端服务暂时不可用。"
                ])
            default:
                continue
            }
        }

        return BackendStreamResult(reply: finalReply, structuredAction: finalAction, structuredActions: finalActions, collaboration: finalCollaboration)
    }


    func transcribeAudio(fileURL: URL, fallbackText: String, localeIdentifier: String) async throws -> TranscriptionResponse {
        var urlRequest = URLRequest(url: baseURL.appending(path: "/transcribe"))
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 90

        let audioData = try Data(contentsOf: fileURL)
        urlRequest.httpBody = audioData
        urlRequest.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(fileURL.lastPathComponent, forHTTPHeaderField: "X-File-Name")
        urlRequest.setValue(localeIdentifier, forHTTPHeaderField: "X-Locale-Identifier")
        if fallbackText.isEmpty == false {
            let encoded = Data(fallbackText.prefix(800).utf8).base64EncodedString()
            urlRequest.setValue(encoded, forHTTPHeaderField: "X-Fallback-Text-Base64")
        }

        let (data, response) = try await session.data(for: urlRequest)
        try validate(response: response, data: data)
        return try decoder.decode(TranscriptionResponse.self, from: data)
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
