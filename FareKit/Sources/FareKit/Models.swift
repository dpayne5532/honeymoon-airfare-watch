import Foundation

/// Mirrors data/history.json, written by fetcher/fetch_fare.py.
public struct FareHistory: Codable, Sendable, Equatable {
    public var trip: Trip
    public var updatedAt: Date?
    public var snapshots: [FareSnapshot]
    public var googlePriceHistory: [PricePoint]
    public var lastError: FetchFailure?

    public init(
        trip: Trip,
        updatedAt: Date? = nil,
        snapshots: [FareSnapshot] = [],
        googlePriceHistory: [PricePoint] = [],
        lastError: FetchFailure? = nil
    ) {
        self.trip = trip
        self.updatedAt = updatedAt
        self.snapshots = snapshots
        self.googlePriceHistory = googlePriceHistory
        self.lastError = lastError
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        trip = try c.decode(Trip.self, forKey: .trip)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
        snapshots = try c.decodeIfPresent([FareSnapshot].self, forKey: .snapshots) ?? []
        googlePriceHistory = try c.decodeIfPresent([PricePoint].self, forKey: .googlePriceHistory) ?? []
        lastError = try c.decodeIfPresent(FetchFailure.self, forKey: .lastError)
    }

    /// Snapshots sorted oldest → newest.
    public var sortedSnapshots: [FareSnapshot] {
        snapshots.sorted { $0.timestamp < $1.timestamp }
    }

    public var latest: FareSnapshot? { sortedSnapshots.last }

    public static func decode(_ data: Data) throws -> FareHistory {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(FareHistory.self, from: data)
    }
}

public struct Trip: Codable, Sendable, Equatable {
    public var origin: String
    public var destination: String
    public var outboundDate: String
    public var returnDate: String
    public var outboundFlight: String
    public var returnFlight: String
    public var adults: Int
    public var travelClass: String
    public var currency: String

    public init(
        origin: String, destination: String,
        outboundDate: String, returnDate: String,
        outboundFlight: String, returnFlight: String,
        adults: Int, travelClass: String, currency: String
    ) {
        self.origin = origin
        self.destination = destination
        self.outboundDate = outboundDate
        self.returnDate = returnDate
        self.outboundFlight = outboundFlight
        self.returnFlight = returnFlight
        self.adults = adults
        self.travelClass = travelClass
        self.currency = currency
    }

    public var departure: Date? { Self.parseDay(outboundDate) }
    public var returning: Date? { Self.parseDay(returnDate) }

    /// Parses yyyy-MM-dd as midnight in the user's current time zone.
    static func parseDay(_ string: String) -> Date? {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

public struct FareSnapshot: Codable, Sendable, Equatable, Identifiable {
    public var timestamp: Date
    /// Round-trip price as reported by Google Flights for the configured travelers.
    public var price: Double
    /// "exact": UA 177 + UA 178 itinerary. "outbound_only": cheapest return paired with UA 177.
    public var match: String
    public var cheapestRoundTrip: Double?
    /// Google's assessment of the whole route right now: "low", "typical" or "high".
    public var priceLevel: String?
    public var typicalLow: Double?
    public var typicalHigh: Double?

    public var id: Date { timestamp }
    public var isExactMatch: Bool { match == "exact" }

    public init(
        timestamp: Date, price: Double, match: String = "exact",
        cheapestRoundTrip: Double? = nil, priceLevel: String? = nil,
        typicalLow: Double? = nil, typicalHigh: Double? = nil
    ) {
        self.timestamp = timestamp
        self.price = price
        self.match = match
        self.cheapestRoundTrip = cheapestRoundTrip
        self.priceLevel = priceLevel
        self.typicalLow = typicalLow
        self.typicalHigh = typicalHigh
    }
}

public struct PricePoint: Codable, Sendable, Equatable, Identifiable {
    public var timestamp: Date
    public var price: Double
    public var id: Date { timestamp }

    public init(timestamp: Date, price: Double) {
        self.timestamp = timestamp
        self.price = price
    }
}

public struct FetchFailure: Codable, Sendable, Equatable {
    public var timestamp: Date
    public var message: String
}
