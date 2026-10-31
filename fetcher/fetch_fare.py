#!/usr/bin/env python3
"""Fetch today's fare for the tracked trip from SerpApi (Google Flights)
and append it to data/history.json.

Run daily by .github/workflows/track-fare.yml. Uses only the standard library.

Environment:
  SERPAPI_KEY   required. Also read from a .env file in the repo root.
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

def build_snapshot(trip: dict, search=serpapi_search, api_key: str = "") -> tuple[dict, list[dict]]:
    """Returns (snapshot, google_price_history). Raises FetchError."""
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

    price = outbound["price"]
    match = "outbound_only"
    return_flight = None

    token = outbound.get("departure_token")
    if token:
        return_data = search({**params, "departure_token": token})
        ret = find_option(return_data, trip["returnFlight"])
        if ret is not None:
            price = ret["price"]
            match = "exact"
            return_flight = trip["returnFlight"]

    snapshot = {
        "timestamp": now_iso(),
        "price": price,
        "match": match,
        "outboundFlight": trip["outboundFlight"],
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
    return snapshot, google_history


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
    try:
        snapshot, google_history = build_snapshot(trip, api_key=api_key)
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
    history["lastError"] = None
    history["updatedAt"] = now_iso()
    save_history(history)

    print(f"{snapshot['timestamp']}: ${snapshot['price']:,} ({snapshot['match']}), "
          f"cheapest round trip ${snapshot['cheapestRoundTrip']}, level {snapshot['priceLevel']}")

    topic = os.environ.get("NTFY_TOPIC", "").strip()
    if topic and message:
        send_ntfy(topic, message)
    return 0


if __name__ == "__main__":
    sys.exit(main())
