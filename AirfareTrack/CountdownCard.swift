import FareKit
import SwiftUI

/// Live countdown to UA 177 leaving Denver.
struct CountdownCard: View {
    let wheelsUp: WheelsUp
    let flight: String

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            card(now: context.date)
        }
    }

    private struct Remaining {
        var days: Int
        var hours: Int
        var minutes: Int
        var seconds: Int
    }

    private func remaining(at now: Date) -> Remaining? {
        guard wheelsUp.date > now else { return nil }
        if wheelsUp.hasTime {
            let total = Int(wheelsUp.date.timeIntervalSince(now))
            return Remaining(days: total / 86_400, hours: total % 86_400 / 3_600,
                             minutes: total % 3_600 / 60, seconds: total % 60)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = wheelsUp.timeZone
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: wheelsUp.date).day ?? 0
        return Remaining(days: days, hours: 0, minutes: 0, seconds: 0)
    }

    private var departureLine: String {
        var style = Date.FormatStyle.dateTime.weekday(.abbreviated).month(.abbreviated).day().year()
        style.timeZone = wheelsUp.timeZone
        let flightName = flight.replacingOccurrences(of: "UA", with: "UA ")
        guard wheelsUp.hasTime else { return "\(flightName) · \(wheelsUp.date.formatted(style))" }
        var time = Date.FormatStyle.dateTime.hour().minute()
        time.timeZone = wheelsUp.timeZone
        let zone = wheelsUp.timeZone.abbreviation(for: wheelsUp.date) ?? ""
        return "\(flightName) · \(wheelsUp.date.formatted(style)) at \(wheelsUp.date.formatted(time)) \(zone)"
    }

    private func card(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Wheels up", systemImage: "airplane.departure")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))

            if let left = remaining(at: now) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(left.days)")
                        .font(.system(size: 68, weight: .bold, design: .rounded))
                        .contentTransition(.numericText(countsDown: true))
                    Text(left.days == 1 ? "day" : "days")
                        .font(.title2.weight(.semibold))
                }
                if wheelsUp.hasTime {
                    Text(String(format: "%02d hr  %02d min  %02d sec", left.hours, left.minutes, left.seconds))
                        .font(.system(.title3, design: .rounded).weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(Self.gold)
                }
            } else {
                Text("Buon viaggio!")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                Text("Congratulations, you two.")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(Self.gold)
            }

            Text(departureLine)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.75))
                .padding(.top, 4)
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .topTrailing) {
            ZStack(alignment: .topTrailing) {
                LinearGradient(
                    colors: [Self.midnight, Self.plum, Self.wine, Self.coral],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                // Interlocked rings, echoing the app icon
                HStack(spacing: -22) {
                    Circle().stroke(Self.gold.opacity(0.35), lineWidth: 5)
                    Circle().stroke(Self.gold.opacity(0.35), lineWidth: 5)
                }
                .frame(width: 118, height: 70)
                .padding(18)
            }
        }
        .clipShape(.rect(cornerRadius: 20))
    }

    private static let midnight = Color(red: 0.07, green: 0.05, blue: 0.17)
    private static let plum = Color(red: 0.24, green: 0.10, blue: 0.30)
    private static let wine = Color(red: 0.61, green: 0.18, blue: 0.33)
    private static let coral = Color(red: 0.88, green: 0.48, blue: 0.37)
    private static let gold = Color(red: 0.97, green: 0.85, blue: 0.55)
}
