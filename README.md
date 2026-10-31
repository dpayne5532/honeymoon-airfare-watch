# Honeymoon Fare Tracker

Tracks the round-trip fare for **UA 177 DEN→FCO (Apr 19, 2027)** and **UA 178 FCO→DEN (Apr 29, 2027)**, economy, 2 adults. It keeps the price history and gives a buy/wait signal.

```
GitHub Action (daily) ──► SerpApi / Google Flights ──► data/history.json (committed)
                                                            │
iPhone app ◄── GitHub contents API ◄────────────────────────┘
  chart · stats · prediction · local alerts
```

## Layout

| Path | What |
|---|---|
| `fetcher/fetch_fare.py` | Python script (stdlib only). Finds UA 177 and then UA 178 in Google Flights results and appends a snapshot. |
| `fetcher/trip.json` | The trip being tracked. Edit this to change flights or dates. |
| `data/history.json` | All recorded prices, plus Google's route price history. |
| `.github/workflows/track-fare.yml` | Ticks every 2 hours; the fetcher only searches when ~10 hours have passed since the last check, and commits each new snapshot. |
| `FareKit/` | Swift package with the models and the prediction engine (`swift test`). |
| `AirfareTrack/` | SwiftUI iOS app. |

## Setup

1. **Push to GitHub.** The repo must stay public, because the app reads it without a token.
2. **Add secrets** (Settings → Secrets and variables → Actions):
   - `SERPAPI_KEY` (required)
   - `NTFY_TOPIC` (optional): sends instant pushes via [ntfy.sh](https://ntfy.sh). Install the ntfy app and subscribe to the same hard-to-guess topic name.
   - Variable `TARGET_PRICE` (optional): your target fare, used for ntfy alerts.
3. **Run the workflow once** from the Actions tab (**Track fare → Run workflow**) to record the first data point.
4. **App:** open `AirfareTrack.xcodeproj` and run it on your phone. The repo (`dpayne5532/honeymoon-airfare-watch`, branch `master`) is hardcoded in `AirfareTrack/AppSettings.swift`, so there's nothing to configure.

## Each daily run

- Costs 3 SerpApi searches: outbound options, returns paired with UA 177, and United's fare options (Basic Economy → Premium) for UA 177 + UA 178. If UA 177 isn't in the results, one extra search restricted to United nonstops is used. Checks are ~10 hours apart, about 220 searches a month, to stay under the 240/month plan. Before each check it reads the account's remaining searches (free) and skips if there aren't enough.
- The main tracked price is the **Economy** fare (`fare` in `trip.json`). Every check also records all fare options. If Economy isn't offered, it records the cheapest fare under its own name, and the app leaves it off the main chart.
- Records the price for the exact UA 177 + UA 178 itinerary (`match: "exact"`). If UA 178 isn't listed, it records UA 177 with the cheapest return instead (`outbound_only`).
- Also saves the cheapest DEN–FCO round trip, Google's low/typical/high rating for the route, Google's recent route price history, and the top other itineraries for the same dates (nonstops first).
- Stops automatically after the departure date.

## Prediction

`FareKit/Sources/FareKit/Predictor.swift` scores four signals:

- **This flight's history:** where today's price falls between the lowest and highest prices seen, and whether it's at or below your target.
- **Trend:** the 14-day regression slope. Until there's enough of the app's own data, it falls back to Google's route-wide price history.
- **Booking curve:** fares tend to rise inside about 60 days and sharply inside about 30.
- **Google's rating:** whether Google rates the route low, typical, or high right now.

The score maps to **Buy now / Good price / Keep watching / Wait**, with a rough 14-day projection. Confidence rises with the number of days of data. These are heuristics, not a forecast.

## Local commands

```sh
echo 'SERPAPI_KEY=...' > .env           # gitignored
python3 fetcher/fetch_fare.py           # one live fetch (2 searches)
cd fetcher && python3 -m unittest       # fetcher tests
cd FareKit && swift test                # prediction engine tests
```
