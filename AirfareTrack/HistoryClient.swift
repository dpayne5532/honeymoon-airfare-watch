import FareKit
import Foundation

/// Downloads data/history.json from the GitHub repo via the contents API.
nonisolated struct HistoryClient: Sendable {
    enum ClientError: LocalizedError {
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .http(403): "GitHub rate limit hit. Try again in a few minutes."
            case .http(404): "Couldn't find history.json in \(DataSource.owner)/\(DataSource.repo). Is the repo still public?"
            case .http(let code): "GitHub returned HTTP \(code)."
            }
        }
    }

    func fetch() async throws -> (FareHistory, Data) {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.github.com"
        components.path = "/repos/\(DataSource.owner)/\(DataSource.repo)/contents/data/history.json"
        components.queryItems = [URLQueryItem(name: "ref", value: DataSource.branch)]

        var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("application/vnd.github.raw+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

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
