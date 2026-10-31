import Foundation

/// Mirrors data/history.json, written by fetcher/fetch_fare.py.
public struct FareHistory: Codable, Sendable, Equatable {
    public var trip: Trip
    public var updatedAt: Date?
    public var snapshots: [FareSnapshot]
    public var googlePriceHistory: [PricePoint]
    public var lastError: FetchFailure?
    /// Other itineraries for the same dates from the latest check (nonstops first).
    public var alternatives: [AlternativeFlight]

    public init(
        trip: Trip,
        updatedAt: Date? = nil,
        snapshots: [FareSnapshot] = [],
        googlePriceHistory: [PricePoint] = [],
        lastError: FetchFailure? = nil,
        alternatives: [AlternativeFlight] = []
    ) {
        self.trip = trip
        self.updatedAt = updatedAt
        self.snapshots = snapshots
        self.googlePriceHistory = googlePriceHistory
        self.lastError = lastError
        self.alternatives = alternatives
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        trip = try c.decode(Trip.self, forKey: .trip)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
        snapshots = try c.decodeIfPresent([FareSnapshot].self, forKey: .snapshots) ?? []
        googlePriceHistory = try c.decodeIfPresent([PricePoint].self, forKey: .googlePriceHistory) ?? []
        lastError = try c.decodeIfPresent(FetchFailure.self, forKey: .lastError)
        alternatives = try c.decodeIfPresent([AlternativeFlight].self, forKey: .alternatives) ?? []
    }

    /// Snapshots of the tracked fare (e.g. Economy), sorted oldest → newest.
    /// Checks that only got a different fare are left out so the series stays comparable.
    public var sortedSnapshots: [FareSnapshot] {
        snapshots.filter { $0.fareLabel == trip.trackedFare }.sorted { $0.timestamp < $1.timestamp }
    }

    /// Every fare option for UA 177 + UA 178 from the most recent check that had them.
    public var latestFares: [FareOption] {
        snapshots.sorted { $0.timestamp < $1.timestamp }.last(where: { !($0.fares ?? []).isEmpty })?.fares ?? []
    }

    public var latest: FareSnapshot? { sortedSnapshots.last }

    /// When UA 177 leaves the gate. Uses the scheduled local time once the fetcher has
    /// recorded it; until then, midnight at the origin on the departure date.
    public var wheelsUp: WheelsUp? {
        let zone = trip.originTimeZone
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone

        if let stamp = snapshots.sorted(by: { $0.timestamp < $1.timestamp })
            .last(where: { $0.outboundDeparture != nil })?.outboundDeparture {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = zone
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            if let date = formatter.date(from: stamp) {
                return WheelsUp(date: date, hasTime: true, timeZone: zone)
            }
        }
        let parts = trip.outboundDate.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        else { return nil }
        return WheelsUp(date: date, hasTime: false, timeZone: zone)
    }

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
    /// Fare brand the app tracks, e.g. "Economy". Older data had none (Google's cheapest).
    public var fare: String?

    public init(
        origin: String, destination: String,
        outboundDate: String, returnDate: String,
        outboundFlight: String, returnFlight: String,
        adults: Int, travelClass: String, currency: String,
        fare: String? = nil
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
        self.fare = fare
    }

    public var trackedFare: String { fare ?? "Basic Economy" }

    public var departure: Date? { Self.parseDay(outboundDate) }

    /// Time zone of the origin airport (the trip only ever leaves from Denver).
    public var originTimeZone: TimeZone {
        let zones = ["DEN": "America/Denver", "FCO": "Europe/Rome"]
        return zones[origin].flatMap(TimeZone.init(identifier:)) ?? .current
    }
    public var returning: Date? { Self.parseDay(returnDate) }

    /// Parses yyyy-MM-dd as midnight in the user's current time zone.
    static func parseDay(_ string: String) -> Date? {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

public struct WheelsUp: Sendable, Equatable {
    public var date: Date
    /// False until the scheduled departure time is known (date-only countdown).
    public var hasTime: Bool
    public var timeZone: TimeZone
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
    /// Scheduled local departure of the outbound flight, "yyyy-MM-dd HH:mm".
    public var outboundDeparture: String?
    /// Fare brand `price` refers to. Missing on early data, which was Basic Economy.
    public var fareName: String?
    /// All of the airline's fare options for the itinerary at this check.
    public var fares: [FareOption]?

    public var id: Date { timestamp }
    public var fareLabel: String { fareName ?? "Basic Economy" }
    public var isExactMatch: Bool { match == "exact" }

    public init(
        timestamp: Date, price: Double, match: String = "exact",
        cheapestRoundTrip: Double? = nil, priceLevel: String? = nil,
        typicalLow: Double? = nil, typicalHigh: Double? = nil,
        outboundDeparture: String? = nil,
        fareName: String? = nil,
        fares: [FareOption]? = nil
    ) {
        self.timestamp = timestamp
        self.price = price
        self.match = match
        self.cheapestRoundTrip = cheapestRoundTrip
        self.priceLevel = priceLevel
        self.typicalLow = typicalLow
        self.typicalHigh = typicalHigh
        self.outboundDeparture = outboundDeparture
        self.fareName = fareName
        self.fares = fares
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

public struct FareOption: Codable, Sendable, Equatable, Identifiable {
    public var name: String
    public var price: Double
    public var id: String { name }

    public init(name: String, price: Double) {
        self.name = name
        self.price = price
    }
}

public struct AlternativeFlight: Codable, Sendable, Equatable, Identifiable {
    public struct Layover: Codable, Sendable, Equatable {
        public var airport: String?
        public var minutes: Int?
        public var overnight: Bool?
    }

    /// Round-trip total for the party: this outbound with its cheapest return (lowest fare).
    public var price: Double
    public var stops: Int
    public var airlines: [String]
    public var flights: [String]
    /// Local times, "yyyy-MM-dd HH:mm".
    public var departure: String?
    public var arrival: String?
    public var durationMinutes: Int?
    public var layovers: [Layover]

    public var id: String { flights.joined(separator: "-") }
    public var isNonstop: Bool { stops == 0 }
}
