import SwiftUI
import SwiftData

struct WeightDetailView: View {
    @Environment(AppState.self) private var app
    @Query(sort: \WeightReading.timestamp) private var weights: [WeightReading]

    var body: some View {
        @Bindable var app = app
        let inRange = WeightStats.inRange(weights, app.weightRange)
        let newestFirst = Array(weights.reversed())

        ScrollView {
            VStack(alignment: .leading, spacing: Theme.gap) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .lastTextBaseline) {
                        if let latest = weights.last {
                            (Text(String(format: "%.1f", latest.kg)) + Text(" kg").font(.manrope(16, .semibold)).foregroundColor(Theme.muted))
                                .bigNumber(40)
                        } else {
                            Text("—").bigNumber(40)
                        }
                        Spacer()
                        Text("\(WeightStats.changeLabel(inRange)) · \(app.weightRange.label)")
                            .font(.manrope(14, .semibold)).foregroundStyle(Theme.accent)
                    }
                    PillPicker(options: WeightRange.allCases.map { ($0, $0.rawValue) }, selection: $app.weightRange, filled: true)
                    if inRange.count > 1 {
                        WeightChart(readings: inRange, large: true)
                        HStack {
                            Text(DayKey.short(inRange.first!.timestamp))
                            Spacer()
                            Text(DayKey.short(inRange.last!.timestamp))
                        }
                        .font(.manrope(11, .medium)).foregroundStyle(Theme.muted)
                    } else {
                        Text("Not enough readings in this range to draw a chart.")
                            .font(.manrope(14)).foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity, minHeight: 120)
                    }
                }
                .card()

                if !newestFirst.isEmpty {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(newestFirst.enumerated()), id: \.element.id) { i, w in
                            let prev = i + 1 < newestFirst.count ? newestFirst[i + 1] : nil
                            ReadingRow(reading: w, previous: prev)
                            if i < newestFirst.count - 1 { Divider().overlay(Theme.border).padding(.leading, 52) }
                        }
                    }
                    .card(padding: 0)
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background)
        .navigationTitle("Weight")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { SyncButton() }
        }
    }
}

private struct ReadingRow: View {
    var reading: WeightReading
    var previous: WeightReading?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "heart.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: 0xFF2D55))
                .frame(width: 28, height: 28)
                .background(Color(hex: 0xFF2D55).opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(reading.timestamp.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .font(.manrope(15, .semibold))
                Text("Apple Health · \(reading.time)").font(.manrope(12, .medium)).foregroundStyle(Theme.muted)
            }
            Spacer()
            Text(String(format: "%.1f kg", reading.kg)).font(.manrope(15, .bold)).monospacedDigit()
            if let previous {
                let d = reading.kg - previous.kg
                Text(WeightStats.signed(d))
                    .font(.manrope(13, .semibold)).monospacedDigit()
                    .foregroundStyle(d > 0.05 ? Theme.over : Theme.accent)
                    .frame(width: 48, alignment: .trailing)
            } else {
                Color.clear.frame(width: 48)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 60)
        .accessibilityElement(children: .combine)
    }
}
