import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.repoOwner) private var repoOwner = ""
    @AppStorage(SettingsKey.repoName) private var repoName = ""
    @AppStorage(SettingsKey.branch) private var branch = "main"
    @AppStorage(SettingsKey.targetPrice) private var targetPrice: Double = 0
    @AppStorage(SettingsKey.notificationsEnabled) private var notificationsEnabled = false
    @State private var token = Keychain.token ?? ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Owner (GitHub username)", text: $repoOwner)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Repository (e.g. airfare-track)", text: $repoName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Branch", text: $branch)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Token (private repos only)", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("GitHub data source")
                } footer: {
                    Text("The app reads data/history.json from this repo. For a private repo, use a fine-grained token with read-only Contents access to just this repo. It's stored in the Keychain.")
                }

                Section {
                    HStack {
                        Text("Target fare")
                        Spacer()
                        TextField("None", value: $targetPrice, format: .number.precision(.fractionLength(0)))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 120)
                    }
                    Toggle("Price alerts", isOn: $notificationsEnabled)
                        .onChange(of: notificationsEnabled) { _, enabled in
                            guard enabled else { return }
                            Task {
                                if await !Notifier.requestAuthorization() { notificationsEnabled = false }
                            }
                        }
                } header: {
                    Text("Alerts")
                } footer: {
                    Text("Round-trip total, as Google Flights reports it for your party. You'll get an alert when the app sees a new price at or below the target, a new low, or a drop of 5% or more. iOS decides when background checks run, so alerts can be delayed until you open the app.")
                }
            }
            .onChange(of: token) { _, value in Keychain.setToken(value) }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
