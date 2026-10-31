import Foundation
import Security

/// UserDefaults keys shared by @AppStorage in views and by background code.
nonisolated enum SettingsKey {
    static let repoOwner = "repoOwner"
    static let repoName = "repoName"
    static let branch = "branch"
    static let targetPrice = "targetPrice"
    static let notificationsEnabled = "notificationsEnabled"
    static let lastSeenSnapshot = "lastSeenSnapshot"
}

nonisolated struct AppSettings: Sendable {
    var repoOwner: String
    var repoName: String
    var branch: String
    var targetPrice: Double?
    var notificationsEnabled: Bool
    var token: String?

    static func load(_ defaults: UserDefaults = .standard) -> AppSettings {
        let target = defaults.double(forKey: SettingsKey.targetPrice)
        let branch = defaults.string(forKey: SettingsKey.branch) ?? ""
        return AppSettings(
            repoOwner: defaults.string(forKey: SettingsKey.repoOwner)?.trimmed ?? "",
            repoName: defaults.string(forKey: SettingsKey.repoName)?.trimmed ?? "",
            branch: branch.trimmed.isEmpty ? "main" : branch.trimmed,
            targetPrice: target > 0 ? target : nil,
            notificationsEnabled: defaults.bool(forKey: SettingsKey.notificationsEnabled),
            token: Keychain.token
        )
    }

    var isConfigured: Bool { !repoOwner.isEmpty && !repoName.isEmpty }
}

/// Stores the GitHub token (needed only if the repo is private).
nonisolated enum Keychain {
    private static let service = "co.danpayne.AirfareTrack"
    private static let account = "github-token"

    static var token: String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8), !value.isEmpty
        else { return nil }
        return value
    }

    static func setToken(_ value: String?) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        guard let value = value?.trimmed, !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
}

nonisolated extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
