import Foundation
import Testing
@testable import FareKit

private let trip = Trip(
    origin: "DEN", destination: "FCO",
    outboundDate: "2027-04-19", returnDate: "2027-04-29",
    outboundFlight: "UA177", returnFlight: "UA178",
    adults: 2, travelClass: "economy", currency: "USD"
)
private let cal = Calendar.current
private let departure = trip.departure!

/// Builds a history with one snapshot per day, ending `daysOut` days before departure.
private func history(_ prices: [Double], daysOut: Int, level: String? = nil) -> (FareHistory, Date) {
    let now = cal.date(byAdding: .day, value: -daysOut, to: departure)!.addingTimeInterval(13 * 3600)
    let snaps = prices.enumerated().map { i, p in
        FareSnapshot(
            timestamp: cal.date(byAdding: .day, value: i - (prices.count - 1), to: now)!,
            price: p, priceLevel: level
        )
    }
    return (FareHistory(trip: trip, snapshots: snaps), now)
}

@Test func emptyHistoryHasNoPrediction() {
    #expect(FarePredictor.predict(history: FareHistory(trip: trip), target: nil) == nil)
}

@Test func fallingPricesFarOutSaysWait() throws {
    let (h, now) = history([2400, 2350, 2300, 2280, 2250, 2200, 2150], daysOut: 170)
    let p = try #require(FarePredictor.predict(history: h, target: nil, now: now))
    #expect(p.direction == .falling)
    #expect(p.signal == .wait || p.signal == .watch)
    #expect(p.projectedPrice < 2150)
    #expect(p.stats.daysToDeparture == 170)
}

@Test func belowTargetCloseToDepartureSaysBuy() throws {
    let (h, now) = history([2100, 2050, 2000, 1950, 1900], daysOut: 40, level: "low")
    let p = try #require(FarePredictor.predict(history: h, target: 2000, now: now))
    #expect(p.signal == .buyNow)
    #expect(p.reasons.contains { $0.contains("target") })
}

@Test func risingTrendIsDetected() throws {
    let (h, now) = history([1800, 1850, 1900, 1960, 2000, 2050], daysOut: 100)
    let p = try #require(FarePredictor.predict(history: h, target: nil, now: now))
    #expect(p.direction == .rising)
    #expect(p.projectedPrice > 2050)
    #expect(p.stats.lowest == 1800)
    #expect(p.stats.highest == 2050)
    #expect(p.stats.percentile == 1)
}

@Test func confidenceGrowsWithData() throws {
    let (few, n1) = history([2000, 2000], daysOut: 150)
    let (many, n2) = history(Array(repeating: 2000, count: 20), daysOut: 150)
    #expect(FarePredictor.predict(history: few, target: nil, now: n1)?.confidence == .low)
    #expect(FarePredictor.predict(history: many, target: nil, now: n2)?.confidence == .high)
}

@Test func multipleSnapshotsPerDayCollapse() {
    let base = Date(timeIntervalSince1970: 1_800_000_000)
    let snaps = [
        FareSnapshot(timestamp: base, price: 100),
        FareSnapshot(timestamp: base.addingTimeInterval(60), price: 120),
        FareSnapshot(timestamp: base.addingTimeInterval(86_400), price: 130),
    ]
    let daily = FarePredictor.dailyPrices(snaps, calendar: cal)
    #expect(daily.map(\.price) == [120, 130])
}

@Test func slopeOfLine() {
    let base = Date(timeIntervalSince1970: 0)
    let points = (0..<5).map { FarePredictor.DailyPrice(date: base.addingTimeInterval(Double($0) * 86_400), price: 100 + 10 * Double($0)) }
    #expect(abs(FarePredictor.slopePerDay(points) - 10) < 0.0001)
}

@Test func decodesFetcherOutput() throws {
    let json = """
    {
      "trip": {"origin":"DEN","destination":"FCO","outboundDate":"2027-04-19","returnDate":"2027-04-29",
               "outboundFlight":"UA177","returnFlight":"UA178","adults":2,"travelClass":"economy","currency":"USD"},
      "updatedAt": "2026-10-31T13:23:05Z",
      "snapshots": [{"timestamp":"2026-10-31T13:23:05Z","price":2134,"match":"exact","outboundFlight":"UA177",
                     "returnFlight":"UA178","cheapestRoundTrip":1480,"priceLevel":"typical","typicalLow":1300,"typicalHigh":1900}],
      "googlePriceHistory": [{"timestamp":"2026-10-01T00:00:00Z","price":1500}],
      "lastError": null
    }
    """
    let h = try FareHistory.decode(Data(json.utf8))
    #expect(h.snapshots.first?.price == 2134)
    #expect(h.snapshots.first?.isExactMatch == true)
    #expect(h.googlePriceHistory.count == 1)
    #expect(h.lastError == nil)
}

@Test func decodesSeedFileWithNulls() throws {
    let json = #"{"trip":{"origin":"DEN","destination":"FCO","outboundDate":"2027-04-19","returnDate":"2027-04-29","outboundFlight":"UA177","returnFlight":"UA178","adults":2,"travelClass":"economy","currency":"USD"},"updatedAt":null,"snapshots":[],"googlePriceHistory":[],"lastError":null}"#
    let h = try FareHistory.decode(Data(json.utf8))
    #expect(h.snapshots.isEmpty)
    #expect(h.updatedAt == nil)
}

@Test func wheelsUpUsesRecordedDepartureTime() throws {
    var h = FareHistory(trip: trip)
    let dateOnly = try #require(h.wheelsUp)
    #expect(dateOnly.hasTime == false)

    h.snapshots = [FareSnapshot(timestamp: .now, price: 2670, outboundDeparture: "2027-04-19 16:40")]
    let timed = try #require(h.wheelsUp)
    #expect(timed.hasTime)
    // 16:40 MDT (UTC-6) == 22:40 UTC
    #expect(timed.date == ISO8601DateFormatter().date(from: "2027-04-19T22:40:00Z"))
}

@Test func onlyTrackedFareIsCharted() throws {
    var economyTrip = trip
    economyTrip.fare = "Economy"
    let t = Date(timeIntervalSince1970: 1_800_000_000)
    let h = FareHistory(trip: economyTrip, snapshots: [
        FareSnapshot(timestamp: t, price: 2670),   // legacy Basic Economy
        FareSnapshot(timestamp: t.addingTimeInterval(3600), price: 3150, fareName: "Economy",
                     fares: [FareOption(name: "Basic Economy", price: 2670), FareOption(name: "Economy", price: 3150)]),
    ])
    #expect(h.sortedSnapshots.map(\.price) == [3150])
    #expect(h.latestFares.count == 2)
}

@Test func decodesAlternatives() throws {
    let json = #"{"trip":{"origin":"DEN","destination":"FCO","outboundDate":"2027-04-19","returnDate":"2027-04-29","outboundFlight":"UA177","returnFlight":"UA178","adults":2,"travelClass":"economy","currency":"USD","fare":"Economy"},"snapshots":[],"alternatives":[{"price":1797,"stops":1,"airlines":["Turkish Airlines"],"flights":["TK 202","TK 1361"],"departure":"2027-04-19 20:25","arrival":"2027-04-20 22:35","durationMinutes":1090,"layovers":[{"airport":"IST","minutes":245,"overnight":false}]}]}"#
    let h = try FareHistory.decode(Data(json.utf8))
    #expect(h.trip.trackedFare == "Economy")
    #expect(h.alternatives.first?.layovers.first?.airport == "IST")
}
