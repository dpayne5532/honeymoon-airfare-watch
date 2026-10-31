import Charts
import FareKit
import SwiftUI
import WidgetKit

// MARK: - Entry

struct FareEntry: TimelineEntry {
    var date: Date
    var fareName: String
    var price: Double?
    var previous: Double?
    var adults: Int
    var currency: String
    var updated: Date?
    var daysToGo: Int?
    var series: [Double]
    var signal: String?

    var change: Double? {
        guard let price, let previous else { return nil }
        return price - previous
    }

    static let sample = FareEntry(
        date: .now, fareName: "Economy", price: 3150, previous: 3190, adults: 2, currency: "USD",
        updated: .now.addingTimeInterval(-3 * 3600), daysToGo: 170,
        series: [3240, 3220, 3260, 3200, 3190, 3150], signal: "Keep watching"
    )

    static func from(_ history: FareHistory, now: Date = .now) -> FareEntry {
        let snapshots = history.sortedSnapshots
        let latest = snapshots.last
        let previous = snapshots.dropLast().last

        var daysToGo: Int?
        if let wheelsUp = history.wheelsUp {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = wheelsUp.timeZone
            daysToGo = max(0, calendar.dateComponents(
                [.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: wheelsUp.date)
            ).day ?? 0)
        }

        return FareEntry(
            date: now,
            fareName: history.trip.trackedFare,
            price: latest?.price,
            previous: previous?.price,
            adults: history.trip.adults,
            currency: history.trip.currency,
            updated: latest?.timestamp,
            daysToGo: daysToGo,
            series: snapshots.suffix(30).map(\.price),
            signal: FarePredictor.predict(history: history, target: nil, now: now)?.signal.title
        )
    }
}

// MARK: - Provider

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> FareEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (FareEntry) -> Void) {
        if context.isPreview {
            completion(.sample)
            return
        }
        Task { completion(await Self.load()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FareEntry>) -> Void) {
        Task {
            let entry = await Self.load()
            // The fare is checked about every 10 hours; refreshing every 2 hours keeps the widget current.
            completion(Timeline(entries: [entry], policy: .after(Date.now.addingTimeInterval(2 * 3600))))
        }
    }

    static func load() async -> FareEntry {
        if let (history, data) = try? await HistoryRemote.fetch() {
            HistoryRemote.saveCache(data)
            return .from(history)
        }
        if let cached = HistoryRemote.loadCache() {
            return .from(cached)
        }
        var empty = FareEntry.sample
        empty.price = nil
        empty.previous = nil
        empty.series = []
        empty.signal = nil
        empty.updated = nil
        return empty
    }
}

// MARK: - Views

private enum Palette {
    static let midnight = Color(red: 0.07, green: 0.05, blue: 0.17)
    static let plum = Color(red: 0.24, green: 0.10, blue: 0.30)
    static let wine = Color(red: 0.61, green: 0.18, blue: 0.33)
    static let coral = Color(red: 0.88, green: 0.48, blue: 0.37)
    static let gold = Color(red: 0.97, green: 0.85, blue: 0.55)

    static let background = LinearGradient(
        colors: [midnight, plum, wine, coral], startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

private func money(_ value: Double, _ currency: String) -> String {
    value.formatted(.currency(code: currency).precision(.fractionLength(0)))
}

struct HoneymoonWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FareEntry

    var body: some View {
        switch family {
        case .accessoryInline: inline
        case .accessoryRectangular: rectangular
        case .systemMedium: medium
        default: small
        }
    }

    // Home screen, small

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            Spacer(minLength: 0)
            priceBlock
            Spacer(minLength: 0)
            footer
        }
        .foregroundStyle(.white)
        .containerBackground(for: .widget) { Palette.background }
    }

    // Home screen, medium

    private var medium: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                header
                Spacer(minLength: 0)
                priceBlock
                Spacer(minLength: 0)
                footer
            }
            VStack(alignment: .leading, spacing: 6) {
                if let signal = entry.signal {
                    Text(signal)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.15), in: .capsule)
                }
                if entry.series.count >= 2 {
                    sparkline
                } else {
                    Spacer()
                    Text("Trend appears after a few checks")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                }
                if let updated = entry.updated {
                    Text("Checked \(updated, style: .relative) ago")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.white)
        .containerBackground(for: .widget) { Palette.background }
    }

    private var header: some View {
        HStack(spacing: 4) {
            Image(systemName: "airplane.departure")
            Text("UA 177 · \(entry.fareName)")
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.white.opacity(0.8))
    }

    @ViewBuilder private var priceBlock: some View {
        if let price = entry.price {
            VStack(alignment: .leading, spacing: 2) {
                Text(money(price, entry.currency))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                HStack(spacing: 6) {
                    if entry.adults > 1 {
                        Text("\(money(price / Double(entry.adults), entry.currency)) each")
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    changeLabel
                }
                .font(.caption2.weight(.medium))
            }
        } else {
            Text("No fare yet")
                .font(.headline)
        }
    }

    @ViewBuilder private var changeLabel: some View {
        if let change = entry.change, change != 0 {
            HStack(spacing: 1) {
                Image(systemName: change < 0 ? "arrow.down" : "arrow.up")
                Text(money(abs(change), entry.currency))
            }
            .foregroundStyle(change < 0 ? Color.green : Palette.gold)
        }
    }

    @ViewBuilder private var footer: some View {
        if let days = entry.daysToGo {
            Text(days == 0 ? "Wheels up today!" : "\(days) days to Rome")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Palette.gold)
        }
    }

    private var sparkline: some View {
        let low = (entry.series.min() ?? 0)
        let high = (entry.series.max() ?? 0)
        let pad = max((high - low) * 0.15, 1)
        return Chart(Array(entry.series.enumerated()), id: \.offset) { point in
            LineMark(x: .value("Check", point.offset), y: .value("Price", point.element))
                .interpolationMethod(.monotone)
                .foregroundStyle(Palette.gold)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
            AreaMark(x: .value("Check", point.offset), yStart: .value("Low", low - pad), yEnd: .value("Price", point.element))
                .interpolationMethod(.monotone)
                .foregroundStyle(LinearGradient(colors: [Palette.gold.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: (low - pad)...(high + pad))
    }

    // Lock screen

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label("Honeymoon fare", systemImage: "airplane.departure")
                .font(.caption2.weight(.semibold))
                .widgetAccentable()
            if let price = entry.price {
                HStack(spacing: 4) {
                    Text(money(price, entry.currency)).font(.headline)
                    if let change = entry.change, change != 0 {
                        Text((change < 0 ? "↓" : "↑") + money(abs(change), entry.currency))
                            .font(.caption)
                    }
                }
            } else {
                Text("No fare yet").font(.headline)
            }
            if let days = entry.daysToGo {
                Text("\(entry.fareName) · \(days) days to go").font(.caption2)
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    private var inline: some View {
        let price = entry.price.map { money($0, entry.currency) } ?? "–"
        let days = entry.daysToGo.map { " · \($0)d" } ?? ""
        return Label("\(price)\(days)", systemImage: "airplane")
            .containerBackground(for: .widget) { Color.clear }
    }
}

// MARK: - Widget

struct HoneymoonFareWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HoneymoonFare", provider: Provider()) { entry in
            HoneymoonWidgetView(entry: entry)
        }
        .configurationDisplayName("Honeymoon Fare")
        .description("Latest UA 177/178 fare and days until wheels up.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct HoneymoonWidgetBundle: WidgetBundle {
    var body: some Widget {
        HoneymoonFareWidget()
    }
}

#Preview(as: .systemSmall) {
    HoneymoonFareWidget()
} timeline: {
    FareEntry.sample
}

#Preview(as: .systemMedium) {
    HoneymoonFareWidget()
} timeline: {
    FareEntry.sample
}
