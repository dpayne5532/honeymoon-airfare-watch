import Foundation

/// Where the GitHub Action publishes data/history.json. Shared by the app and the widget.
public enum HistoryRemote {
    public static let owner = "dpayne5532"
    public static let repo = "honeymoon-airfare-watch"
    public static let branch = "master"

    public enum RemoteError: LocalizedError {
        case http(Int)

        public var errorDescription: String? {
            switch self {
            case .http(403): "GitHub rate limit hit. Try again in a few minutes."
            case .http(404): "Couldn't find history.json in \(owner)/\(repo). Is the repo still public?"
            case .http(let code): "GitHub returned HTTP \(code)."
            }
        }
    }

    /// Downloads and decodes the latest history. Returns the raw bytes too, for caching.
    public static func fetch() async throws -> (FareHistory, Data) {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.github.com"
        components.path = "/repos/\(owner)/\(repo)/contents/data/history.json"
        components.queryItems = [URLQueryItem(name: "ref", value: branch)]

        var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("application/vnd.github.raw+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw RemoteError.http(http.statusCode)
        }
        return (try FareHistory.decode(data), data)
    }

    /// Last successful download, stored in the calling process's own container.
    public static func loadCache() -> FareHistory? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? FareHistory.decode(data)
    }

    public static func saveCache(_ data: Data) {
        try? FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
        try? data.write(to: cacheURL, options: .atomic)
    }

    private static var cacheURL: URL {
        URL.applicationSupportDirectory.appending(path: "history.json")
    }
}
