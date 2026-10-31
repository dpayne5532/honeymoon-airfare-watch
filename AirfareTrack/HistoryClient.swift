import FareKit
import Foundation

/// Downloads data/history.json from the GitHub repo via the contents API.
/// Works for public repos with no token, or private repos with a fine-grained token.
nonisolated struct HistoryClient: Sendable {
    var settings: AppSettings

    enum ClientError: LocalizedError {
        case notConfigured
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .notConfigured: "Set your GitHub repo in Settings."
            case .http(401), .http(403): "GitHub rejected the request. Check the token in Settings."
            case .http(404): "history.json not found. Check the repo, branch, and token (private repos need a token)."
            case .http(let code): "GitHub returned HTTP \(code)."
            }
        }
    }

    func fetch() async throws -> (FareHistory, Data) {
        guard settings.isConfigured else { throw ClientError.notConfigured }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.github.com"
        components.path = "/repos/\(settings.repoOwner)/\(settings.repoName)/contents/data/history.json"
        components.queryItems = [URLQueryItem(name: "ref", value: settings.branch)]

        var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("application/vnd.github.raw+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let token = settings.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ClientError.http(http.statusCode)
        }
        return (try FareHistory.decode(data), data)
    }
}

/// Last successfully downloaded history, so the app works offline.
nonisolated enum HistoryCache {
    private static var url: URL {
        URL.applicationSupportDirectory.appending(path: "history.json")
    }

    static func load() -> FareHistory? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? FareHistory.decode(data)
    }

    static func save(_ data: Data) {
        try? FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
