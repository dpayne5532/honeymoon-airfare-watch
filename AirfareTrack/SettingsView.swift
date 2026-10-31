import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.targetPrice) private var targetPrice: Double = 0
    @AppStorage(SettingsKey.notificationsEnabled) private var notificationsEnabled = false

    var body: some View {
        NavigationStack {
            Form {
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
