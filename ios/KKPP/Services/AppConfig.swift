import Foundation

enum AppConfig {
    static var backendBaseURL: String {
        if let value = Bundle.main.object(forInfoDictionaryKey: "KKPPBackendBaseURL") as? String,
           !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value
        }

        return "http://127.0.0.1:3000"
    }

    static var backendHostHint: String {
        guard let host = URL(string: backendBaseURL)?.host else {
            return backendBaseURL
        }

        return host
    }
}
