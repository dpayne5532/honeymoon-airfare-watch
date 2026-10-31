import FareKit
import Foundation
import UserNotifications

/// Posts a local notification when a newly-seen snapshot is worth knowing about.
nonisolated enum Notifier {
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func evaluate(_ history: FareHistory, settings: AppSettings, defaults: UserDefaults = .standard) async {
        let snapshots = history.sortedSnapshots
        guard let latest = snapshots.last else { return }

        let lastSeen = defaults.double(forKey: SettingsKey.lastSeenSnapshot)
        let latestTime = latest.timestamp.timeIntervalSince1970
        guard latestTime > lastSeen else { return }
        defaults.set(latestTime, forKey: SettingsKey.lastSeenSnapshot)

        // First launch: record the baseline, don't notify about old data.
        guard lastSeen > 0, settings.notificationsEnabled else { return }

        let previous = snapshots.dropLast().map(\.price)
        guard let body = message(price: latest.price, previous: Array(previous),
                                 target: settings.targetPrice, currency: history.trip.currency)
        else { return }

        let content = UNMutableNotificationContent()
        content.title = "Honeymoon fare update"
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: "fare-\(Int(latestTime))", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    static func message(price: Double, previous: [Double], target: Double?, currency: String) -> String? {
        let fmt = { (v: Double) in v.formatted(.currency(code: currency).precision(.fractionLength(0))) }
        if let target, price <= target {
            return "Fare is \(fmt(price)), at or below your \(fmt(target)) target."
        }
        if let low = previous.min(), price < low {
            return "New lowest fare: \(fmt(price)) (previous low \(fmt(low)))."
        }
        if let last = previous.last, price <= last * 0.95 {
            return "Fare dropped to \(fmt(price)) from \(fmt(last))."
        }
        return nil
    }
}
