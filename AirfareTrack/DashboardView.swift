import FareKit
import SwiftUI

struct DashboardView: View {
    @Environment(FareStore.self) private var store
    @AppStorage(SettingsKey.targetPrice) private var targetPrice: Double = 0
    @State private var showingSettings = false

    private var target: Double? { targetPrice > 0 ? targetPrice : nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let history = store.history {
                        content(history)
                    } else if store.isLoading {
                        ProgressView().padding(.top, 120)
                    }

                    if let error = store.errorMessage {
                        Banner(text: error, systemImage: "exclamationmark.triangle.fill", tint: .orange)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Honeymoon Fare")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") { showingSettings = true }
                }
            }
            .refreshable { await store.refresh() }
            .task { await store.refresh() }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
                    .onDisappear { Task { await store.refresh() } }
            }
        }
    }

    @ViewBuilder
    private func content(_ history: FareHistory) -> some View {
        if let wheelsUp = history.wheelsUp {
            CountdownCard(wheelsUp: wheelsUp, flight: history.trip.outboundFlight)
        }

        TripHeader(trip: history.trip)

        if let failure = history.lastError {
            Banner(
                text: "Last fetch failed \(failure.timestamp.formatted(.relative(presentation: .named))): \(failure.message)",
                systemImage: "exclamationmark.icloud.fill", tint: .red
            )
        }

        if let prediction = FarePredictor.predict(history: history, target: target), let latest = history.latest {
            PriceCard(latest: latest, stats: prediction.stats, currency: history.trip.currency, adults: history.trip.adults)
            PredictionCard(prediction: prediction, currency: history.trip.currency)
            Card {
                PriceChartView(history: history, target: target)
            }
            StatsGrid(stats: prediction.stats, cheapestRoute: latest.cheapestRoundTrip, currency: history.trip.currency)
            NavigationLink {
                HistoryListView(history: history)
            } label: {
                HStack {
                    Label("Price history", systemImage: "list.bullet.rectangle")
                    Spacer()
                    Text("\(history.snapshots.count) checks").foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            Text("Predictions are heuristics based on this flight's price history, Google's route rating, and typical booking curves. They aren't guarantees.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        } else {
            ContentUnavailableView(
                "No prices yet",
                systemImage: "clock.arrow.circlepath",
                description: Text("The daily GitHub Action hasn't recorded a fare yet. Run it manually from the Actions tab to get the first data point.")
            )
        }
    }
}

// MARK: - Components

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
    }
}

struct Banner: View {
    let text: String
    let systemImage: String
    let tint: Color
    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.footnote)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(tint.opacity(0.15), in: .rect(cornerRadius: 12))
            .foregroundStyle(tint)
    }
}

private struct TripHeader: View {
    let trip: Trip

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(trip.origin).font(.title.bold())
                    Image(systemName: "arrow.left.arrow.right").foregroundStyle(.secondary)
                    Text(trip.destination).font(.title.bold())
                    Spacer()
                    Text("\(trip.adults) adults · \(trip.travelClass.capitalized)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                leg(icon: "airplane.departure", flight: trip.outboundFlight, date: trip.departure)
                leg(icon: "airplane.arrival", flight: trip.returnFlight, date: trip.returning)
            }
        }
    }

    private func leg(icon: String, flight: String, date: Date?) -> some View {
        HStack {
            Image(systemName: icon).foregroundStyle(.tint).frame(width: 24)
            Text(flight.replacingOccurrences(of: "UA", with: "UA ")).monospacedDigit()
            Spacer()
            if let date {
                Text(date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
    }
}

private struct PriceCard: View {
    let latest: FareSnapshot
    let stats: FareStats
    let currency: String
    let adults: Int

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Text("Current round-trip fare").font(.subheadline).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline) {
                    Text(latest.price, format: .currency(code: currency).precision(.fractionLength(0)))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                    if let previous = stats.previous {
                        change(latest.price - previous)
                    }
                }
                if adults > 1 {
                    Text("\((latest.price / Double(adults)).formatted(.currency(code: currency).precision(.fractionLength(0)))) per person · total for \(adults)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text("Updated \(latest.timestamp.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !latest.isExactMatch {
                    Label("Return flight wasn't listed. Price uses the cheapest return.", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private func change(_ delta: Double) -> some View {
        let color: Color = delta < 0 ? .green : (delta > 0 ? .red : .secondary)
        let icon = delta < 0 ? "arrow.down" : (delta > 0 ? "arrow.up" : "equal")
        return Label(abs(delta).formatted(.currency(code: currency).precision(.fractionLength(0))), systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(color)
    }
}

private struct PredictionCard: View {
    let prediction: FarePrediction
    let currency: String

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(color, in: .circle)
                    VStack(alignment: .leading) {
                        Text(prediction.signal.title).font(.title2.bold())
                        Text("\(prediction.confidence.rawValue.capitalized) confidence")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                HStack {
                    Image(systemName: directionIcon).foregroundStyle(directionColor)
                    Text(directionText)
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("In \(FarePredictor.projectionDays) days").font(.caption2).foregroundStyle(.secondary)
                        Text("≈ \(prediction.projectedPrice.formatted(.currency(code: currency).precision(.fractionLength(0))))")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .font(.subheadline)

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(prediction.reasons, id: \.self) { reason in
                        Label(reason, systemImage: "circle.fill")
                            .labelStyle(BulletLabelStyle())
                            .font(.footnote)
                    }
                }
            }
        }
    }

    private var icon: String {
        switch prediction.signal {
        case .buyNow: "cart.fill"
        case .goodPrice: "hand.thumbsup.fill"
        case .watch: "eye.fill"
        case .wait: "hourglass"
        }
    }

    private var color: Color {
        switch prediction.signal {
        case .buyNow: .green
        case .goodPrice: .teal
        case .watch: .blue
        case .wait: .orange
        }
    }

    private var directionIcon: String {
        switch prediction.direction {
        case .rising: "chart.line.uptrend.xyaxis"
        case .falling: "chart.line.downtrend.xyaxis"
        case .flat: "chart.line.flattrend.xyaxis"
        }
    }

    private var directionColor: Color {
        switch prediction.direction {
        case .rising: .red
        case .falling: .green
        case .flat: .secondary
        }
    }

    private var directionText: String {
        switch prediction.direction {
        case .rising: "Likely to rise"
        case .falling: "Likely to fall"
        case .flat: "Likely to hold steady"
        }
    }
}

private struct BulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            configuration.icon.font(.system(size: 5)).foregroundStyle(.secondary)
            configuration.title
        }
    }
}

private struct StatsGrid: View {
    let stats: FareStats
    let cheapestRoute: Double?
    let currency: String

    var body: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                tile("Lowest", money(stats.lowest), "arrow.down.to.line")
                tile("Highest", money(stats.highest), "arrow.up.to.line")
            }
            GridRow {
                tile("7-day avg", stats.average7Day.map(money) ?? "–", "chart.bar")
                tile("Cheapest DEN–FCO", cheapestRoute.map(money) ?? "–", "tag")
            }
        }
    }

    private func money(_ v: Double) -> String {
        v.formatted(.currency(code: currency).precision(.fractionLength(0)))
    }

    private func tile(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
    }
}
