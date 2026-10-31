import unittest

import fetch_fare as ff

TRIP = {
    "origin": "DEN", "destination": "FCO",
    "outboundDate": "2027-04-19", "returnDate": "2027-04-29",
    "outboundFlight": "UA177", "returnFlight": "UA178",
    "adults": 2, "travelClass": "economy", "currency": "USD",
}


def option(price, *numbers, token=None):
    o = {"price": price, "flights": [{"flight_number": n} for n in numbers]}
    if token:
        o["departure_token"] = token
    return o


OUTBOUND = {
    "best_flights": [option(1400, "LH 481", "LH 232", token="lh")],
    "other_flights": [
        option(1900, "UA 177", token="ua"),
        option(1750, "UA 700", "UA 177", token="conn"),
    ],
    "price_insights": {
        "price_level": "typical",
        "typical_price_range": [1300, 1800],
        "price_history": [[1761955200, 1500], [1762041600, 1520]],
    },
}
RETURN = {"best_flights": [option(2050, "UA 178")], "other_flights": [option(1980, "UA 1", "UA 2")]}


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
        search = FakeSearch(OUTBOUND, RETURN)
        snap, google = ff.build_snapshot(TRIP, search=search)
        self.assertEqual(snap["price"], 2050)
        self.assertEqual(snap["match"], "exact")
        self.assertEqual(snap["cheapestRoundTrip"], 1400)
        self.assertEqual((snap["typicalLow"], snap["typicalHigh"]), (1300, 1800))
        self.assertEqual(search.calls[1]["departure_token"], "ua")
        self.assertEqual(len(google), 2)
        self.assertEqual(google[0]["timestamp"], "2025-11-01T00:00:00Z")

    def test_falls_back_to_outbound_price(self):
        snap, _ = ff.build_snapshot(TRIP, search=FakeSearch(OUTBOUND, {"best_flights": []}))
        self.assertEqual((snap["price"], snap["match"]), (1900, "outbound_only"))

    def test_retries_with_airline_filter(self):
        search = FakeSearch({"best_flights": [option(900, "AA 1")]}, OUTBOUND, RETURN)
        snap, _ = ff.build_snapshot(TRIP, search=search)
        self.assertEqual(search.calls[1]["include_airlines"], "UA")
        self.assertEqual(snap["price"], 2050)

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


if __name__ == "__main__":
    unittest.main()
