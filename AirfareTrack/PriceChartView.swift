import Charts
import FareKit
import SwiftUI

struct PriceChartView: View {
    let history: FareHistory
    let target: Double?

    @State private var range: ChartRange = .all
    @State private var showRoute = false
    @State private var selectedDate: Date?

    enum ChartRange: String, CaseIterable, Identifiable {
        case month = "30D", quarter = "90D", all = "All"
        var id: Self { self }
        var days: Int? {
            switch self {
            case .month: 30
            case .quarter: 90
            case .all: nil
            }
        }
    }

    private var cutoff: Date {
        guard let days = range.days else { return .distantPast }
        return Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .distantPast
    }

    private var snapshots: [FareSnapshot] {
        history.sortedSnapshots.filter { $0.timestamp >= cutoff }
    }

    private var routePoints: [PricePoint] {
        history.googlePriceHistory.filter { $0.timestamp >= cutoff }.sorted { $0.timestamp < $1.timestamp }
    }

    private var selected: FareSnapshot? {
        guard let selectedDate else { return nil }
        return snapshots.min { abs($0.timestamp.timeIntervalSince(selectedDate)) < abs($1.timestamp.timeIntervalSince(selectedDate)) }
    }

    private var currency: String { history.trip.currency }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Price trend").font(.headline)
                Spacer()
                Picker("Range", selection: $range) {
                    ForEach(ChartRange.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }

            Chart {
                if showRoute {
                    ForEach(routePoints) { point in
                        LineMark(
                            x: .value("Date", point.timestamp),
                            y: .value("Price", point.price),
                            series: .value("Series", "Cheapest route")
                        )
                        .foregroundStyle(.gray)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    }
                }

                ForEach(snapshots) { snap in
                    LineMark(
                        x: .value("Date", snap.timestamp),
                        y: .value("Price", snap.price),
                        series: .value("Series", "UA 177/178")
                    )
                    .foregroundStyle(Color.accentColor)
                    .interpolationMethod(.monotone)

                    if snapshots.count < 40 {
                        PointMark(x: .value("Date", snap.timestamp), y: .value("Price", snap.price))
                            .foregroundStyle(Color.accentColor)
                            .symbolSize(20)
                    }
                }

                if let target {
                    RuleMark(y: .value("Target", target))
                        .foregroundStyle(.green)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [6, 4]))
                        .annotation(position: .top, alignment: .leading) {
                            Text("Target").font(.caption2).foregroundStyle(.green)
                        }
                }

                if let selected {
                    RuleMark(x: .value("Selected", selected.timestamp))
                        .foregroundStyle(.secondary.opacity(0.4))
                        .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                            VStack(spacing: 2) {
                                Text(selected.price, format: .currency(code: currency).precision(.fractionLength(0)))
                                    .font(.caption.bold())
                                Text(selected.timestamp, format: .dateTime.month(.abbreviated).day())
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(6)
                            .background(.regularMaterial, in: .rect(cornerRadius: 8))
                        }
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(v, format: .currency(code: currency).precision(.fractionLength(0)))
                        }
                    }
                }
            }
            .chartXSelection(value: $selectedDate)
            .frame(height: 220)

            if !history.googlePriceHistory.isEmpty {
                Toggle(isOn: $showRoute) {
                    Text("Show cheapest DEN–FCO fare (Google)").font(.footnote)
                }
                .tint(.gray)
            }
        }
    }
}
