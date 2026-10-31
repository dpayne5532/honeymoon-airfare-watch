import unittest

import fetch_fare as ff

TRIP = {
    "origin": "DEN", "destination": "FCO",
    "outboundDate": "2027-04-19", "returnDate": "2027-04-29",
    "outboundFlight": "UA177", "returnFlight": "UA178",
    "adults": 2, "travelClass": "economy", "currency": "USD", "fare": "Economy",
}


def option(price, *numbers, token=None):
    o = {"price": price, "flights": [{"flight_number": n} for n in numbers]}
    if token:
        o["departure_token"] = token
    return o


OUTBOUND = {
    "best_flights": [option(1400, "LH 481", "LH 232", token="lh")],
    "other_flights": [
        {"price": 1900, "departure_token": "ua",
         "flights": [{"flight_number": "UA 177", "airline": "United",
                      "departure_airport": {"id": "DEN", "time": "2027-04-19 16:40"}}]},
        option(1750, "UA 700", "UA 177", token="conn"),
    ],
    "price_insights": {
        "price_level": "typical",
        "typical_price_range": [1300, 1800],
        "price_history": [[1761955200, 1500], [1762041600, 1520]],
    },
}
RETURN = {"best_flights": [{**option(2050, "UA 178"), "booking_token": "bk"}],
          "other_flights": [option(1980, "UA 1", "UA 2")]}
BOOKING = {"booking_options": [
    {"together": {"book_with": "United", "option_title": "Economy", "price": 2400}},
    {"together": {"book_with": "United", "option_title": "Basic Economy", "price": 2050}},
    {"together": {"book_with": "Lufthansa", "price": 2400}},
    {"together": {"book_with": "Gotogate", "price": 2300}},
]}


class FakeSearch:
    def __init__(self, *responses):
        self.responses = list(responses)
        self.calls = []

    def __call__(self, params):
        self.calls.append(params)
        return self.responses.pop(0)


class FetchFareTests(unittest.TestCase):
    def test_prefers_nonstop_match(self):
        self.assertEqual(ff.find_option(OUTBOUND, "UA177")["price"], 1900)

    def test_missing_flight(self):
        self.assertIsNone(ff.find_option(OUTBOUND, "UA999"))

    def test_exact_snapshot(self):
        search = FakeSearch(OUTBOUND, RETURN, BOOKING)
        snap, google, alts = ff.build_snapshot(TRIP, search=search)
        self.assertEqual(search.calls[2]["booking_token"], "bk")
        self.assertEqual((snap["price"], snap["fareName"]), (2400, "Economy"))
        self.assertEqual(snap["fares"], [{"name": "Basic Economy", "price": 2050}, {"name": "Economy", "price": 2400}])
        self.assertEqual(snap["match"], "exact")
        self.assertEqual(snap["cheapestRoundTrip"], 1400)
        self.assertEqual(snap["outboundDeparture"], "2027-04-19 16:40")
        self.assertEqual((snap["typicalLow"], snap["typicalHigh"]), (1300, 1800))
        self.assertEqual(search.calls[1]["departure_token"], "ua")
        self.assertEqual(len(google), 2)
        self.assertEqual(google[0]["timestamp"], "2025-11-01T00:00:00Z")
        # Tracked nonstop excluded; 1-stop options sorted by price.
        self.assertEqual([a["flights"] for a in alts], [["LH 481", "LH 232"], ["UA 700", "UA 177"]])

    def test_alternatives_put_nonstops_first(self):
        data = {"best_flights": [option(900, "AA 1", "AA 2"), option(2500, "DL 66"), option(1100, "BA 9", "BA 10", "BA 11")],
                "other_flights": [option(2000, "UA 177")]}
        alts = ff.summarize_alternatives(data, "UA177")
        self.assertEqual([(a["stops"], a["price"]) for a in alts], [(0, 2500), (1, 900), (2, 1100)])

    def test_falls_back_to_outbound_price(self):
        snap, _, _ = ff.build_snapshot(TRIP, search=FakeSearch(OUTBOUND, {"best_flights": []}))
        self.assertEqual((snap["price"], snap["match"], snap["fareName"]), (1900, "outbound_only", "Basic Economy"))

    def test_retries_with_airline_filter(self):
        search = FakeSearch({"best_flights": [option(900, "AA 1")]}, OUTBOUND, RETURN, BOOKING)
        snap, _, _ = ff.build_snapshot(TRIP, search=search)
        self.assertEqual(search.calls[1]["include_airlines"], "UA")
        self.assertEqual(snap["price"], 2400)

    def test_falls_back_to_cheapest_when_fare_missing(self):
        only_basic = {"booking_options": [{"together": {"book_with": "United", "option_title": "Basic Economy", "price": 2050}}]}
        snap, _, _ = ff.build_snapshot(TRIP, search=FakeSearch(OUTBOUND, RETURN, only_basic))
        self.assertEqual((snap["price"], snap["fareName"]), (2050, "Basic Economy"))

    def test_not_found_raises(self):
        empty = {"best_flights": []}
        with self.assertRaises(ff.FetchError):
            ff.build_snapshot(TRIP, search=FakeSearch(empty, empty))

    def test_alerts(self):
        prev = [{"price": 2000}, {"price": 1900}]
        self.assertIn("target", ff.alert_message({"price": 1800}, prev, 1850))
        self.assertIn("New lowest", ff.alert_message({"price": 1850}, prev, None))
        self.assertIsNone(ff.alert_message({"price": 1950}, prev, None))
        self.assertIsNone(ff.alert_message({"price": 1800}, [], None))


class GateTests(unittest.TestCase):
    def test_hours_since_counts_errors(self):
        now = ff.now_iso()
        self.assertIsNone(ff.hours_since_last_run({"snapshots": []}))
        h = {"snapshots": [{"timestamp": "2020-01-01T00:00:00Z"}], "lastError": {"timestamp": now}}
        self.assertLess(ff.hours_since_last_run(h), 0.1)


if __name__ == "__main__":
    unittest.main()
