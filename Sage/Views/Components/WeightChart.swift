import SwiftUI
import Charts

/// Line chart of weight readings. `large` adds an area fill and y-axis labels.
struct WeightChart: View {
    var readings: [WeightReading]
    var large = false

    private var bounds: ClosedRange<Double> {
        let vals = readings.map(\.kg)
        guard let lo = vals.min(), let hi = vals.max() else { return 0...1 }
        return (lo - 0.3)...(hi + 0.3)
    }

    var body: some View {
        Chart {
            ForEach(readings) { r in
                if large {
                    AreaMark(x: .value("Date", r.timestamp),
                             yStart: .value("Base", bounds.lowerBound),
                             yEnd: .value("Weight", r.kg))
                        .foregroundStyle(Theme.accent.opacity(0.08))
                        .interpolationMethod(.monotone)
                }
                LineMark(x: .value("Date", r.timestamp), y: .value("Weight", r.kg))
                    .foregroundStyle(Theme.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }
            if let last = readings.last {
                PointMark(x: .value("Date", last.timestamp), y: .value("Weight", last.kg))
                    .symbol {
                        Circle().fill(Theme.accent)
                            .frame(width: large ? 11 : 10, height: large ? 11 : 10)
                            .overlay(Circle().stroke(Theme.card, lineWidth: 2))
                    }
            }
        }
        .chartYScale(domain: bounds)
        .chartXAxis(.hidden)
        .modifier(WeightYAxis(large: large))
        .frame(height: large ? 170 : 96)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        guard let first = readings.first, let last = readings.last else { return "No weight readings" }
        return String(format: "Weight from %.1f to %.1f kilograms", first.kg, last.kg)
    }
}

private struct WeightYAxis: ViewModifier {
    var large: Bool
    func body(content: Content) -> some View {
        if large {
            content.chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(Theme.border)
                    AxisValueLabel().font(.manrope(11, .medium)).foregroundStyle(Theme.muted)
                }
            }
        } else {
            content.chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(Theme.border)
                }
            }
        }
    }
}
