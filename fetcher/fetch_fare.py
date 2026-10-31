#!/usr/bin/env python3
"""Fetch today's fare for the tracked trip from SerpApi (Google Flights)
and append it to data/history.json.

Run daily by .github/workflows/track-fare.yml. Uses only the standard library.

Each run costs 3 SerpApi searches (outbound list, return list, fare/booking
options), plus 1 if UA 177 has to be re-searched. Runs are spaced
MIN_INTERVAL_HOURS apart to stay under the account's monthly limit.

Environment:
  SERPAPI_KEY   required. Also read from a .env file in the repo root.
  FORCE         if "1", ignore the interval gate (manual runs).
  NTFY_TOPIC    optional. If set, sends a push via ntfy.sh on notable drops.
  TARGET_PRICE  optional. Sends a push when the fare is at or below this.
"""
from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import date, datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TRIP_PATH = ROOT / "fetcher" / "trip.json"
HISTORY_PATH = ROOT / "data" / "history.json"
ENV_PATH = ROOT / ".env"

SERPAPI_URL = "https://serpapi.com/search.json"
SERPAPI_ACCOUNT_URL = "https://serpapi.com/account.json"
SEARCHES_PER_RUN = 3
MIN_INTERVAL_HOURS = 9.5   # cron ticks every 2h, so runs land ~10h apart (~220 searches/month)
TRAVEL_CLASS = {"economy": 1, "premium_economy": 2, "business": 3, "first": 4}


class FetchError(Exception):
    pass


# ---------------------------------------------------------------- helpers

def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).strftime("%Y-%m-%dT%H:%M:%SZ")


def load_dotenv(path: Path = ENV_PATH) -> None:
    """Minimal .env loader: KEY=VALUE lines; existing env vars win."""
    if not path.exists():
        return
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))


def normalize_flight(number: str) -> str:
    return number.replace(" ", "").upper()


def all_options(data: dict) -> list[dict]:
    return list(data.get("best_flights") or []) + list(data.get("other_flights") or [])


def find_option(data: dict, flight_number: str) -> dict | None:
    """Cheapest itinerary option whose segments include `flight_number`.
    Prefers options where it is the only segment (i.e. the nonstop)."""
    target = normalize_flight(flight_number)
    matches = []
    for option in all_options(data):
        segments = option.get("flights") or []
        numbers = [normalize_flight(s.get("flight_number", "")) for s in segments]
        if target in numbers and isinstance(option.get("price"), (int, float)):
            matches.append((len(segments) != 1, option["price"], option))
    if not matches:
        return None
    matches.sort(key=lambda m: (m[0], m[1]))
    return matches[0][2]


def departure_time(option: dict, flight_number: str) -> str | None:
    """Local departure time ("YYYY-MM-DD HH:MM") of the matching segment."""
    target = normalize_flight(flight_number)
    for segment in option.get("flights") or []:
        if normalize_flight(segment.get("flight_number", "")) == target:
            return (segment.get("departure_airport") or {}).get("time")
    return None


def summarize_alternatives(data: dict, tracked_flight: str, limit: int = 15) -> list[dict]:
    """Other itineraries for the same dates: nonstops first, then fewest stops, then price.
    Prices are round-trip totals for the party with that outbound's cheapest return."""
    tracked = normalize_flight(tracked_flight)
    results = []
    for option in all_options(data):
        segments = option.get("flights") or []
        price = option.get("price")
        if not segments or not isinstance(price, (int, float)):
            continue
        numbers = [normalize_flight(s.get("flight_number", "")) for s in segments]
        if numbers == [tracked]:
            continue  # that's the flight we already track
        airlines = []
        for seg in segments:
            name = seg.get("airline")
            if name and name not in airlines:
                airlines.append(name)
        results.append({
            "price": price,
            "stops": len(segments) - 1,
            "airlines": airlines,
            "flights": [s.get("flight_number", "") for s in segments],
            "departure": (segments[0].get("departure_airport") or {}).get("time"),
            "arrival": (segments[-1].get("arrival_airport") or {}).get("time"),
            "durationMinutes": option.get("total_duration"),
            "layovers": [
                {"airport": l.get("id"), "minutes": l.get("duration"), "overnight": bool(l.get("overnight"))}
                for l in (option.get("layovers") or [])
            ],
        })
    results.sort(key=lambda r: (r["stops"], r["price"]))
    return results[:limit]


def fare_options(booking_data: dict, airline_name: str) -> list[dict]:
    """The airline's own fare brands (Basic Economy, Economy, ...) for the itinerary."""
    fares = []
    for option in booking_data.get("booking_options") or []:
        together = option.get("together") or {}
        name, price = together.get("option_title"), together.get("price")
        if together.get("book_with") == airline_name and name and isinstance(price, (int, float)):
            if not any(f["name"] == name for f in fares):
                fares.append({"name": name, "price": price})
    fares.sort(key=lambda f: f["price"])
    return fares


def cheapest_price(data: dict) -> float | None:
    prices = [o["price"] for o in all_options(data) if isinstance(o.get("price"), (int, float))]
    return min(prices) if prices else None


def base_params(trip: dict, api_key: str) -> dict:
    return {
        "engine": "google_flights",
        "departure_id": trip["origin"],
        "arrival_id": trip["destination"],
        "outbound_date": trip["outboundDate"],
        "return_date": trip["returnDate"],
        "type": "1",  # round trip
        "adults": str(trip["adults"]),
        "travel_class": str(TRAVEL_CLASS[trip["travelClass"]]),
        "currency": trip["currency"],
        "hl": "en",
        "gl": "us",
        "api_key": api_key,
    }


def serpapi_search(params: dict) -> dict:
    url = SERPAPI_URL + "?" + urllib.parse.urlencode(params)
    try:
        with urllib.request.urlopen(url, timeout=90) as resp:
            data = json.load(resp)
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", "replace")
        try:
            message = json.loads(body).get("error", body)
        except json.JSONDecodeError:
            message = body
        raise FetchError(f"SerpApi HTTP {e.code}: {message[:300]}") from None
    except urllib.error.URLError as e:
        raise FetchError(f"Network error: {e.reason}") from None
    if "error" in data:
        raise FetchError(f"SerpApi: {data['error']}")
    return data


# ---------------------------------------------------------------- core

def build_snapshot(trip: dict, search=serpapi_search, api_key: str = "") -> tuple[dict, list[dict], list[dict]]:
    """Returns (snapshot, google_price_history, alternatives). Raises FetchError."""
    params = base_params(trip, api_key)
    outbound_data = search(params)
    outbound = find_option(outbound_data, trip["outboundFlight"])

    if outbound is None:
        # Retry restricted to the airline's nonstops in case the flight was
        # crowded out of the general results.
        airline = normalize_flight(trip["outboundFlight"])[:2]
        retry = search({**params, "include_airlines": airline, "stops": "1"})
        outbound = find_option(retry, trip["outboundFlight"])
        if outbound is None:
            raise FetchError(f"{trip['outboundFlight']} not found in Google Flights results")

    insights = outbound_data.get("price_insights") or {}
    typical = insights.get("typical_price_range") or [None, None]

    # Google's headline price is the cheapest fare (usually Basic Economy).
    price = outbound["price"]
    fare_name = "Basic Economy"
    match = "outbound_only"
    return_flight = None
    fares: list[dict] = []

    token = outbound.get("departure_token")
    if token:
        return_data = search({**params, "departure_token": token})
        ret = find_option(return_data, trip["returnFlight"])
        if ret is not None:
            price = ret["price"]
            match = "exact"
            return_flight = trip["returnFlight"]
            if ret.get("booking_token"):
                airline = (outbound.get("flights") or [{}])[0].get("airline") or "United"
                fares = fare_options(search({**params, "booking_token": ret["booking_token"]}), airline)
                wanted = next((f for f in fares if f["name"] == trip.get("fare")), None)
                if wanted:
                    price, fare_name = wanted["price"], wanted["name"]

    snapshot = {
        "timestamp": now_iso(),
        "price": price,
        "fareName": fare_name,
        "fares": fares,
        "match": match,
        "outboundFlight": trip["outboundFlight"],
        "outboundDeparture": departure_time(outbound, trip["outboundFlight"]),
        "returnFlight": return_flight,
        "cheapestRoundTrip": cheapest_price(outbound_data),
        "priceLevel": insights.get("price_level"),
        "typicalLow": typical[0] if len(typical) > 0 else None,
        "typicalHigh": typical[1] if len(typical) > 1 else None,
    }

    google_history = [
        {
            "timestamp": datetime.fromtimestamp(point[0], timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "price": point[1],
        }
        for point in (insights.get("price_history") or [])
        if isinstance(point, list) and len(point) == 2
    ]
    return snapshot, google_history, summarize_alternatives(outbound_data, trip["outboundFlight"])


def load_history(trip: dict) -> dict:
    if HISTORY_PATH.exists():
        history = json.loads(HISTORY_PATH.read_text())
    else:
        history = {"snapshots": [], "googlePriceHistory": []}
    history["trip"] = trip
    history.setdefault("snapshots", [])
    history.setdefault("googlePriceHistory", [])
    return history


def save_history(history: dict) -> None:
    HISTORY_PATH.parent.mkdir(parents=True, exist_ok=True)
    HISTORY_PATH.write_text(json.dumps(history, indent=2) + "\n")


def alert_message(snapshot: dict, previous: list[dict], target: float | None) -> str | None:
    price = snapshot["price"]
    prior = [s["price"] for s in previous]
    if target is not None and price <= target:
        return f"Fare is ${price:,.0f}, at or below your ${target:,.0f} target."
    if prior and price < min(prior):
        return f"New lowest fare: ${price:,.0f} (previous low ${min(prior):,.0f})."
    if prior and price <= prior[-1] * 0.95:
        return f"Fare dropped to ${price:,.0f} from ${prior[-1]:,.0f}."
    return None


def send_ntfy(topic: str, message: str) -> None:
    req = urllib.request.Request(
        f"https://ntfy.sh/{urllib.parse.quote(topic)}",
        data=message.encode(),
        headers={"Title": "Honeymoon fare", "Tags": "airplane"},
        method="POST",
    )
    try:
        urllib.request.urlopen(req, timeout=30).close()
    except urllib.error.URLError as e:
        print(f"ntfy failed: {e}", file=sys.stderr)


def searches_left(api_key: str) -> int | None:
    """Remaining searches on the SerpApi account (this lookup is free)."""
    try:
        url = SERPAPI_ACCOUNT_URL + "?" + urllib.parse.urlencode({"api_key": api_key})
        with urllib.request.urlopen(url, timeout=30) as resp:
            data = json.load(resp)
        left = data.get("total_searches_left", data.get("plan_searches_left"))
        return int(left) if left is not None else None
    except (urllib.error.URLError, ValueError, json.JSONDecodeError):
        return None


def hours_since_last_run(history: dict) -> float | None:
    # Failed attempts count too, so an outage can't burn searches every 2 hours.
    stamps = [s["timestamp"] for s in history.get("snapshots", [])]
    if (history.get("lastError") or {}).get("timestamp"):
        stamps.append(history["lastError"]["timestamp"])
    if not stamps:
        return None
    last = datetime.strptime(max(stamps), "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    return (datetime.now(timezone.utc) - last).total_seconds() / 3600


def main() -> int:
    load_dotenv()
    trip = json.loads(TRIP_PATH.read_text())

    if date.today() > date.fromisoformat(trip["outboundDate"]):
        print("Trip has departed; nothing to track. Enjoy the honeymoon!")
        return 0

    api_key = os.environ.get("SERPAPI_KEY", "").strip()
    if not api_key:
        print("SERPAPI_KEY is not set (env or .env).", file=sys.stderr)
        return 1

    history = load_history(trip)

    if os.environ.get("FORCE") != "1":
        since = hours_since_last_run(history)
        if since is not None and since < MIN_INTERVAL_HOURS:
            print(f"Last check was {since:.1f}h ago; next one after {MIN_INTERVAL_HOURS}h. Skipping.")
            return 0

    left = searches_left(api_key)
    if left is not None and left < SEARCHES_PER_RUN + 1:
        print(f"Only {left} SerpApi searches left this month; skipping to stay under the limit.")
        return 0

    try:
        snapshot, google_history, alternatives = build_snapshot(trip, api_key=api_key)
    except FetchError as e:
        history["lastError"] = {"timestamp": now_iso(), "message": str(e)}
        history["updatedAt"] = now_iso()
        save_history(history)
        print(f"Fetch failed: {e}", file=sys.stderr)
        return 1

    previous = history["snapshots"]
    target_raw = os.environ.get("TARGET_PRICE", "").strip()
    target = float(target_raw) if target_raw else None
    message = alert_message(snapshot, previous, target)

    history["snapshots"].append(snapshot)
    if google_history:
        history["googlePriceHistory"] = google_history
    if alternatives:
        history["alternatives"] = alternatives
    history["lastError"] = None
    history["updatedAt"] = now_iso()
    save_history(history)

    print(f"{snapshot['timestamp']}: ${snapshot['price']:,} {snapshot['fareName']} ({snapshot['match']}), "
          f"cheapest round trip ${snapshot['cheapestRoundTrip']}, level {snapshot['priceLevel']}")

    topic = os.environ.get("NTFY_TOPIC", "").strip()
    if topic and message:
        send_ntfy(topic, message)
    return 0


if __name__ == "__main__":
    sys.exit(main())
