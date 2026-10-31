import FareKit
import SwiftUI

struct HistoryListView: View {
    let history: FareHistory

    private var rows: [(snapshot: FareSnapshot, delta: Double?)] {
        let sorted = history.sortedSnapshots
        return sorted.enumerated().map { i, snap in
            (snap, i > 0 ? snap.price - sorted[i - 1].price : nil)
        }.reversed()
    }

    var body: some View {
        List(rows, id: \.snapshot.id) { row in
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.snapshot.timestamp, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                    HStack(spacing: 6) {
                        if let level = row.snapshot.priceLevel {
                            Text("Route: \(level)")
                        }
                        if let cheapest = row.snapshot.cheapestRoundTrip {
                            Text("Cheapest \(money(cheapest))")
                        }
                        if !row.snapshot.isExactMatch {
                            Text("Outbound only").foregroundStyle(.orange)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(money(row.snapshot.price)).font(.body.weight(.semibold)).monospacedDigit()
                    if let delta = row.delta, delta != 0 {
                        Text((delta > 0 ? "+" : "−") + money(abs(delta)))
                            .font(.caption)
                            .foregroundStyle(delta < 0 ? .green : .red)
                    }
                }
            }
        }
        .navigationTitle("Price History")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func money(_ v: Double) -> String {
        v.formatted(.currency(code: history.trip.currency).precision(.fractionLength(0)))
    }
}
