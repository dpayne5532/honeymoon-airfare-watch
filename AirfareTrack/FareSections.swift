import FareKit
import SwiftUI

private func money(_ value: Double, _ currency: String) -> String {
    value.formatted(.currency(code: currency).precision(.fractionLength(0)))
}

// MARK: - United fare options for UA 177 + UA 178

struct FareOptionsCard: View {
    let fares: [FareOption]
    let tracked: String
    let currency: String
    let adults: Int

    private var trackedPrice: Double? { fares.first { $0.name == tracked }?.price }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Fare options").font(.headline)
                    Text("UA 177 + UA 178 · total for \(adults)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(fares) { fare in
                    row(fare)
                    if fare.id != fares.last?.id { Divider() }
                }
            }
        }
    }

    private func row(_ fare: FareOption) -> some View {
        let isTracked = fare.name == tracked
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(fare.name).fontWeight(isTracked ? .semibold : .regular)
                    if isTracked {
                        Text("Tracking")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15), in: .capsule)
                            .foregroundStyle(.tint)
                    }
                }
                if fare.name == "Basic Economy" {
                    Text("Seats assigned at check-in; you may not sit together")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(money(fare.price, currency)).monospacedDigit().fontWeight(isTracked ? .semibold : .regular)
                if let trackedPrice, !isTracked {
                    let diff = fare.price - trackedPrice
                    Text((diff > 0 ? "+" : "−") + money(abs(diff), currency))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if adults > 1 {
                    Text("\(money(fare.price / Double(adults), currency)) each")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.subheadline)
    }
}

// MARK: - Other itineraries for the same dates

struct AlternativesSection: View {
    let history: FareHistory

    private var currency: String { history.trip.currency }

    private var dateRange: String {
        guard let out = history.trip.departure, let back = history.trip.returning else { return "" }
        let style = Date.FormatStyle.dateTime.month(.abbreviated).day()
        return "\(out.formatted(style)) – \(back.formatted(style))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Other flights").font(.title3.bold())
                Text("\(history.trip.origin) ⇄ \(history.trip.destination) · \(dateRange) · nonstops first")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
            .padding(.top, 8)

            if !history.alternatives.contains(where: \.isNonstop) {
                Banner(text: "No other nonstops on these dates. UA 177/178 is the only one.",
                       systemImage: "info.circle.fill", tint: .blue)
            }

            ForEach(history.alternatives) { flight in
                AlternativeRow(flight: flight, currency: currency, adults: history.trip.adults)
            }

            Text("Round-trip totals for \(history.trip.adults), at each itinerary's lowest fare (often basic economy), with its cheapest return. From the latest check\(history.updatedAt.map { ", \($0.formatted(.relative(presentation: .named)))" } ?? "").")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }
}

private struct AlternativeRow: View {
    let flight: AlternativeFlight
    let currency: String
    let adults: Int

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(flight.airlines.joined(separator: " · "))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    Text(money(flight.price, currency))
                        .font(.headline)
                        .monospacedDigit()
                }

                HStack(spacing: 6) {
                    Text(Self.time(flight.departure))
                    Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
                    Text(Self.time(flight.arrival))
                    if let plus = Self.dayOffset(flight.departure, flight.arrival), plus > 0 {
                        Text("+\(plus)").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if adults > 1 {
                        Text("\(money(flight.price / Double(adults), currency)) each")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline)
                .monospacedDigit()

                HStack(spacing: 8) {
                    stopsBadge
                    if let minutes = flight.durationMinutes {
                        Label(Self.duration(minutes), systemImage: "clock")
                    }
                    Spacer()
                    Text(flight.flights.joined(separator: ", "))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var stopsBadge: some View {
        if flight.isNonstop {
            Text("Nonstop")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.18), in: .capsule)
                .foregroundStyle(.green)
        } else {
            let stops = flight.layovers.map { stop in
                [stop.airport, stop.minutes.map(Self.duration)].compactMap { $0 }.joined(separator: " ")
            }
            Text("\(flight.stops) stop\(flight.stops == 1 ? "" : "s")" + (stops.isEmpty ? "" : " · " + stops.joined(separator: ", ")))
                .lineLimit(1)
        }
    }

    // Times are airport-local wall-clock strings; parse and print them in GMT so they stay unchanged.
    private static let parser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    private static func time(_ stamp: String?) -> String {
        guard let stamp, let date = parser.date(from: stamp) else { return "–" }
        var style = Date.FormatStyle.dateTime.hour().minute()
        style.timeZone = TimeZone(identifier: "GMT")!
        return date.formatted(style)
    }

    private static func dayOffset(_ from: String?, _ to: String?) -> Int? {
        guard let from, let to, let a = parser.date(from: String(from.prefix(10)) + " 00:00"),
              let b = parser.date(from: String(to.prefix(10)) + " 00:00") else { return nil }
        return Int((b.timeIntervalSince(a) / 86_400).rounded())
    }

    private static func duration(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
}
