import Foundation

/// UserDefaults keys shared by @AppStorage in views and by background code.
nonisolated enum SettingsKey {
    static let targetPrice = "targetPrice"
    static let notificationsEnabled = "notificationsEnabled"
    static let lastSeenSnapshot = "lastSeenSnapshot"
}

nonisolated struct AppSettings: Sendable {
    var targetPrice: Double?
    var notificationsEnabled: Bool

    static func load(_ defaults: UserDefaults = .standard) -> AppSettings {
        let target = defaults.double(forKey: SettingsKey.targetPrice)
        return AppSettings(
            targetPrice: target > 0 ? target : nil,
            notificationsEnabled: defaults.bool(forKey: SettingsKey.notificationsEnabled)
        )
    }
}
