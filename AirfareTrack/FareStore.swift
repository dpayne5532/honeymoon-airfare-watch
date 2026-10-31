import BackgroundTasks
import FareKit
import Foundation
import Observation

@Observable
final class FareStore {
    private(set) var history: FareHistory?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var lastRefreshed: Date?

    init() {
        history = HistoryRemote.loadCache()
    }

    func prediction(target: Double?) -> FarePrediction? {
        guard let history else { return nil }
        return FarePredictor.predict(history: history, target: target)
    }

    func refresh() async {
        let settings = AppSettings.load()
        isLoading = true
        defer { isLoading = false }
        do {
            let history = try await Self.download(settings: settings)
            self.history = history
            errorMessage = nil
            lastRefreshed = .now
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Fetch, cache, and notify. Shared by foreground refresh and the background task.
    nonisolated static func download(settings: AppSettings) async throws -> FareHistory {
        let history = try await HistoryClient.fetch()
        await Notifier.evaluate(history, settings: settings)
        return history
    }
}

nonisolated enum BackgroundRefresh {
    static let identifier = "co.danpayne.AirfareTrack.refresh"

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }

    static func run() async {
        schedule()
        _ = try? await FareStore.download(settings: AppSettings.load())
    }
}
