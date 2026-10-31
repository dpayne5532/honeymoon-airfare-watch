import Foundation

public enum FareSignal: String, Sendable {
    case buyNow, goodPrice, watch, wait

    public var title: String {
        switch self {
        case .buyNow: "Buy now"
        case .goodPrice: "Good price"
        case .watch: "Keep watching"
        case .wait: "Wait"
        }
    }
}

public enum FareDirection: String, Sendable {
    case rising, falling, flat
}

public enum Confidence: String, Sendable {
    case low, medium, high
}

public struct FareStats: Sendable, Equatable {
    public var current: Double
    public var previous: Double?
    public var lowest: Double
    public var highest: Double
    public var average7Day: Double?
    /// Linear-regression slope over the last 14 days, in currency units per day.
    public var dailyTrend: Double
    public var daysToDeparture: Int
    /// 0 = cheapest seen, 1 = most expensive seen. Nil until there are 3+ days of data.
    public var percentile: Double?
    public var dayCount: Int
}

public struct FarePrediction: Sendable, Equatable {
    public var signal: FareSignal
    public var direction: FareDirection
    public var confidence: Confidence
    /// Rough estimate of the fare 14 days from now.
    public var projectedPrice: Double
    public var reasons: [String]
    public var stats: FareStats
}

/// Heuristic buy/wait engine for a single itinerary.
///
/// It combines four inputs:
/// - where today's price sits in this flight's own history (and versus the target),
/// - the recent trend,
/// - typical booking-curve pressure as departure approaches (transatlantic fares
///   tend to climb inside ~60 days and sharply inside ~30),
/// - Google's low/typical/high rating for the route.
///
/// With one itinerary's history, these are signals, not a true forecast.
public enum FarePredictor {
    public static let projectionDays = 14

    public static func predict(
        history: FareHistory,
        target: Double?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> FarePrediction? {
        let daily = dailyPrices(history.sortedSnapshots, calendar: calendar)
        guard let current = daily.last?.price else { return nil }

        let prices = daily.map(\.price)
        let previous = daily.count >= 2 ? daily[daily.count - 2].price : nil

        // Trend: own data, or Google's route history while ours is thin.
        let cutoff = calendar.date(byAdding: .day, value: -14, to: now) ?? now
        var trendPoints = daily.filter { $0.date >= cutoff }
        var trendFromGoogle = false
        if trendPoints.count < 3 {
            let google = dailyPrices(history.googlePriceHistory.map {
                FareSnapshot(timestamp: $0.timestamp, price: $0.price)
            }, calendar: calendar).filter { $0.date >= cutoff }
            if google.count >= 3, let last = google.last?.price, last > 0 {
                // Scale the route-level slope to this itinerary's price.
                trendPoints = google.map { DailyPrice(date: $0.date, price: $0.price * current / last) }
                trendFromGoogle = true
            }
        }
        let trend = slopePerDay(trendPoints)

        let departure = history.trip.departure ?? now
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: departure)
        ).day ?? 0

        let percentile: Double? = prices.count >= 3
            ? Double(prices.filter { $0 < current }.count) / Double(prices.count - 1)
            : nil

        let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let lastWeek = daily.filter { $0.date >= weekAgo }.map(\.price)
        let average7 = lastWeek.isEmpty ? nil : lastWeek.reduce(0, +) / Double(lastWeek.count)

        let stats = FareStats(
            current: current,
            previous: previous,
            lowest: prices.min() ?? current,
            highest: prices.max() ?? current,
            average7Day: average7,
            dailyTrend: trend,
            daysToDeparture: days,
            percentile: percentile,
            dayCount: daily.count
        )

        // Direction & projection.
        let pressure = bookingPressure(daysToDeparture: days) * current
        let drift = 0.6 * trend + pressure
        let projected = max(0, current + drift * Double(projectionDays))
        let threshold = 0.0015 * current
        let direction: FareDirection = drift > threshold ? .rising : (drift < -threshold ? .falling : .flat)

        // Score: positive means buy.
        var score = 0
        var reasons: [String] = []
        let money = { (v: Double) in v.formatted(.currency(code: history.trip.currency).precision(.fractionLength(0))) }

        if let target, target > 0 {
            if current <= target {
                score += 3
                reasons.append("At or below your \(money(target)) target.")
            } else {
                reasons.append("\(money(current - target)) above your \(money(target)) target.")
            }
        }

        if let percentile {
            if percentile <= 0.1 {
                score += 2
                reasons.append("Lowest price seen in \(daily.count) days of tracking.")
            } else if percentile <= 0.33 {
                score += 1
                reasons.append("Cheaper than most prices seen so far.")
            } else if percentile >= 0.75 {
                score -= 1
                reasons.append("More expensive than most prices seen so far.")
            }
        } else {
            reasons.append("Not enough history yet. Signals sharpen after about a week.")
        }

        switch history.latest?.priceLevel?.lowercased() {
        case "low":
            score += 1
            reasons.append("Google rates fares on this route as low right now.")
        case "high":
            score -= 1
            reasons.append("Google rates fares on this route as high right now.")
        case "typical":
            reasons.append("Google rates fares on this route as typical.")
        default:
            break
        }

        let source = trendFromGoogle ? " (route-wide, from Google)" : ""
        switch direction {
        case .rising:
            score += 1
            reasons.append("Trend is rising\(source). Waiting will likely cost more.")
        case .falling:
            score -= 1
            reasons.append("Trend is falling\(source). It may get cheaper.")
        case .flat:
            reasons.append("Prices have been fairly stable\(source).")
        }

        if days <= 45 {
            score += 2
            reasons.append("\(days) days out: fares usually climb steeply from here.")
        } else if days <= 90 {
            score += 1
            reasons.append("\(days) days out: inside the window where Europe fares start rising.")
        } else {
            reasons.append("\(days) days out: still before the usual 2–4 month sweet spot for Europe.")
        }

        let signal: FareSignal = switch score {
        case 4...: .buyNow
        case 2...3: .goodPrice
        case ...(-1): .wait
        default: .watch
        }

        let confidence: Confidence = daily.count < 5 ? .low : (daily.count < 14 ? .medium : .high)

        return FarePrediction(
            signal: signal,
            direction: direction,
            confidence: confidence,
            projectedPrice: projected,
            reasons: reasons,
            stats: stats
        )
    }

    /// Expected organic rise as a fraction of price per day, by days to departure.
    static func bookingPressure(daysToDeparture days: Int) -> Double {
        switch days {
        case ..<30: 0.008
        case 30..<60: 0.004
        case 60..<120: 0.001
        default: 0
        }
    }

    struct DailyPrice: Equatable {
        var date: Date
        var price: Double
    }

    /// One price per calendar day (the last observation of that day).
    static func dailyPrices(_ snapshots: [FareSnapshot], calendar: Calendar) -> [DailyPrice] {
        var byDay: [Date: FareSnapshot] = [:]
        for s in snapshots {
            let day = calendar.startOfDay(for: s.timestamp)
            if let existing = byDay[day], existing.timestamp > s.timestamp { continue }
            byDay[day] = s
        }
        return byDay.sorted { $0.key < $1.key }.map { DailyPrice(date: $0.key, price: $0.value.price) }
    }

    /// Least-squares slope in price units per day.
    static func slopePerDay(_ points: [DailyPrice]) -> Double {
        guard points.count >= 2, let origin = points.first?.date else { return 0 }
        let xs = points.map { $0.date.timeIntervalSince(origin) / 86_400 }
        let ys = points.map(\.price)
        let n = Double(points.count)
        let meanX = xs.reduce(0, +) / n
        let meanY = ys.reduce(0, +) / n
        var num = 0.0, den = 0.0
        for (x, y) in zip(xs, ys) {
            num += (x - meanX) * (y - meanY)
            den += (x - meanX) * (x - meanX)
        }
        return den == 0 ? 0 : num / den
    }
}
