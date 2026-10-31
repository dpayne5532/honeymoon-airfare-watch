import FareKit
import Foundation
import WidgetKit

/// Downloads the latest history, caches it for offline use, and tells the widget to refresh.
nonisolated enum HistoryClient {
    static func fetch() async throws -> FareHistory {
        let (history, data) = try await HistoryRemote.fetch()
        HistoryRemote.saveCache(data)
        WidgetCenter.shared.reloadAllTimelines()
        return history
    }
}
