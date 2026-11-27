import SwiftUI
import SwiftData
import Charts

// MARK: - Week card

/// Week › Maintenance: real maintenance, current target and pace, goal date. Tap for details.
struct MaintenanceCard: View {
    let estimate: AdaptiveEstimate
    @Environment(AppState.self) private var app
    @State private var showDetails = false

    var body: some View {
        Button { showDetails = true } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Maintenance").font(.manrope(17, .bold))
                    Spacer()
                    ConfidenceChip(confidence: estimate.confidence)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
                }
                if let maintenance = estimate.maintenance {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(maintenance.kcalString).bigNumber(36)
                        Text("kcal / day").font(.manrope(13, .bold)).foregroundStyle(Theme.muted)
                    }
                    if estimate.history.count > 1 {
                        Sparkline(values: estimate.history).frame(height: 40)
                    }
                    VStack(spacing: 0) {
                        row("Target", value: "\(app.goals.kcal.kcalString)", detail: paceLabel(app.adaptivePace))
                        if let date = estimate.goalDate(goal: app.goalWeight, pace: app.adaptivePace),
                           let goal = app.goalWeight {
                            Divider().overlay(Theme.border)
                            row("On track for \(goal.clean) kg", value: DayKey.short(date), detail: nil)
                        }
                    }
                } else {
                    LearningView(estimate: estimate)
                }
            }
            .card()
            .foregroundStyle(Theme.text)
        }
        .buttonStyle(PressableStyle())
        .sheet(isPresented: $showDetails) {
            NavigationStack { MaintenanceView(estimate: estimate) }
                .presentationBackground(Theme.background)
        }
    }

    private func row(_ title: String, value: String, detail: String?) -> some View {
        HStack {
            Text(title).font(.manrope(14, .semibold))
            Spacer()
            Text(value).font(.manrope(15, .bold)).monospacedDigit()
            if let detail { Text("· \(detail)").font(.manrope(12, .medium)).foregroundStyle(Theme.muted) }
        }
        .frame(minHeight: 40)
    }
}

func paceLabel(_ pace: Double) -> String {
    pace == 0 ? "maintain" : "lose \(pace.clean) kg/wk"
}

private struct ConfidenceChip: View {
    let confidence: AdaptiveEstimate.Confidence
    var body: some View {
        let (text, color): (String, Color) = {
            switch confidence {
            case .good: return ("● Good estimate", Theme.accent)
            case .rough: return ("● Rough estimate", Theme.carbs)
            case .learning: return ("Learning", Theme.carbs)
            }
        }()
        Text(text)
            .font(.manrope(11.5, .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
    }
}

private struct LearningView: View {
    let estimate: AdaptiveEstimate
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(estimate.unusual
                 ? "The numbers so far don't add up to a realistic maintenance, usually because some days weren't fully logged or weigh-ins are jumping around. Keep logging everything and weighing in, and Sage will try again."
                 : "Keep logging and weighing in, and Sage will work out how much you really burn.")
                .font(.manrope(13, .medium)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.track)
                    Capsule().fill(Theme.accent)
                        .frame(width: geo.size.width * min(1, Double(estimate.loggedDays) / Double(AdaptiveEstimate.minDays)))
                }
            }
            .frame(height: 8)
            HStack {
                Text("\(min(estimate.loggedDays, AdaptiveEstimate.minDays)) of \(AdaptiveEstimate.minDays) days logged")
                Spacer()
                Text("\(estimate.weighIns) of \(estimate.loggedDays >= 21 ? AdaptiveEstimate.minWeighIns : 8)+ weigh-ins")
            }
            .font(.manrope(12, .medium)).foregroundStyle(Theme.muted)
        }
    }
}

private struct Sparkline: View {
    let values: [Double]
    var body: some View {
        Chart {
            ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                LineMark(x: .value("Week", i), y: .value("kcal", v))
                    .foregroundStyle(Theme.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.monotone)
            }
            if let last = values.last {
                PointMark(x: .value("Week", values.count - 1), y: .value("kcal", last))
                    .foregroundStyle(Theme.accent)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: (values.min()! - 40)...(values.max()! + 40))
        .accessibilityLabel("Maintenance over recent weeks")
    }
}

// MARK: - Detail

/// Maintenance details: weight trend, the maths in plain English, pace and goal weight.
struct MaintenanceView: View {
    let estimate: AdaptiveEstimate
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    private let paces: [(Double, String)] = [(0.25, "Lose 0.25 kg / week"), (0.5, "Lose 0.5 kg / week"),
                                             (0.75, "Lose 0.75 kg / week"), (0, "Maintain")]

    var body: some View {
        @Bindable var app = app
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let maintenance = estimate.maintenance {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(maintenance.kcalString).bigNumber(38)
                            Text("kcal / day before workouts").font(.manrope(13, .bold)).foregroundStyle(Theme.muted)
                        }
                        Text("Last \(estimate.windowDays) days · \(estimate.loggedDays) days logged · \(estimate.weighIns) weigh-ins")
                            .font(.manrope(12, .medium)).foregroundStyle(Theme.muted)
                    }
                    .card()

                    WeightTrendCard(estimate: estimate)

                    Text(explanation(maintenance))
                        .font(.manrope(13, .medium))
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.chip, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    // Pace
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Your pace").font(.manrope(15, .bold))
                            Spacer()
                            if let t = estimate.trendWeight {
                                Text("now \(String(format: "%.1f", t)) kg").font(.manrope(12, .medium)).foregroundStyle(Theme.muted)
                            }
                        }
                        ForEach(paces.indices, id: \.self) { i in
                            let pace = paces[i].0
                            let label = paces[i].1
                            let target = estimate.target(pace: pace) ?? 0
                            let on = app.adaptivePace == pace
                            Button { app.adaptivePace = pace } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(label).font(.manrope(14, .bold))
                                        Text(paceDetail(pace)).font(.manrope(11.5, .medium)).foregroundStyle(Theme.muted)
                                    }
                                    Spacer()
                                    Text(target.kcalString).font(.manrope(16, .heavy)).monospacedDigit()
                                }
                                .padding(.horizontal, 13).padding(.vertical, 11)
                                .background(on ? Theme.accent.opacity(0.07) : Theme.field,
                                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(on ? Theme.accent : Theme.border, lineWidth: 1.5))
                                .foregroundStyle(Theme.text)
                            }
                            .buttonStyle(PressableStyle())
                        }
                        GoalWeightRow()
                            .padding(.top, 4)
                    }
                    .card(padding: 14)

                    if let target = estimate.target(pace: app.adaptivePace) {
                        if abs(target - app.goals.kcal) < 1 {
                            Label("Your target is \(target.kcalString) kcal", systemImage: "checkmark.circle.fill")
                                .font(.manrope(15, .bold)).foregroundStyle(Theme.accent)
                                .frame(maxWidth: .infinity, minHeight: 52)
                        } else {
                            Button("Set target to \(target.kcalString) kcal") {
                                AdaptiveData.accept(target, app: app)
                                dismiss()
                            }
                            .buttonStyle(PrimaryButtonStyle())
                        }
                    }
                    Text("Sage never suggests less than 1,500 kcal or more than 25% below your maintenance. Protein stays at \(app.goals.p.grams) g; carbs and fat adjust to fit. Workouts are still added on the days you train.")
                        .font(.manrope(12, .medium)).foregroundStyle(Theme.muted)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Still learning").font(.manrope(17, .bold))
                        LearningView(estimate: estimate)
                    }
                    .card()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your pace").font(.manrope(15, .bold))
                        PillPicker(options: paces.map { ($0.0, $0.0 == 0 ? "Maintain" : "\($0.0.clean) kg") }, selection: $app.adaptivePace)
                        GoalWeightRow()
                    }
                    .card(padding: 14)
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .navigationTitle("Maintenance")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
    }

    private func paceDetail(_ pace: Double) -> String {
        if pace == 0 { return "hold your weight" }
        var parts: [String] = []
        if let goal = app.goalWeight, let date = estimate.goalDate(goal: goal, pace: pace) {
            parts.append("\(goal.clean) kg around \(DayKey.short(date))")
        }
        if estimate.isLimited(pace: pace) {
            parts.append("limited to a safe \(estimate.effectivePace(pace: pace).clean2) kg/wk")
        } else if pace >= 0.75 { parts.append("hard to sustain") }
        if pace == 0.25 { parts.append("gentle") }
        return parts.isEmpty ? "\(Int((pace * AdaptiveEstimate.kcalPerKg / 7).rounded())) kcal a day below maintenance" : parts.joined(separator: " · ")
    }

    private func explanation(_ maintenance: Double) -> String {
        let change = estimate.kgPerWeek * Double(estimate.windowDays) / 7
        let stored = -estimate.kgPerWeek / 7 * AdaptiveEstimate.kcalPerKg
        let direction = change < 0 ? "fell" : "rose"
        var text = "You ate \(estimate.avgIntake.kcalString) a day and your weight trend \(direction) \(String(format: "%.1f", abs(change))) kg. "
        if stored >= 0 {
            text += "That's about \(stored.kcalString) kcal a day taken from your body's stores, "
        } else {
            text += "That's about \(abs(stored).kcalString) kcal a day stored, "
        }
        text += "so you burn roughly \((maintenance + estimate.avgWorkout).kcalString)"
        if estimate.avgWorkout >= 1 {
            text += ", or \(maintenance.kcalString) before your workouts (\(estimate.avgWorkout.kcalString) a day on average). Workouts are added on top on the days you train."
        } else {
            text += "."
        }
        return text
    }
}

/// Goal weight stepper (optional).
private struct GoalWeightRow: View {
    @Environment(AppState.self) private var app
    var body: some View {
        HStack(spacing: 10) {
            Text("Goal weight").font(.manrope(14, .semibold))
            Spacer()
            if let goal = app.goalWeight {
                Button { app.goalWeight = max(30, goal - 0.5) } label: { Image(systemName: "minus") }
                    .buttonStyle(CircleIconButtonStyle())
                    .accessibilityLabel("Lower goal weight")
                Text("\(String(format: "%.1f", goal)) kg").font(.manrope(15, .bold)).monospacedDigit().frame(minWidth: 70)
                Button { app.goalWeight = goal + 0.5 } label: { Image(systemName: "plus") }
                    .buttonStyle(CircleIconButtonStyle())
                    .accessibilityLabel("Raise goal weight")
            } else {
                Button("Set") { app.goalWeight = 80 }
                    .font(.manrope(14, .bold)).foregroundStyle(Theme.accent)
                    .frame(minHeight: Theme.minTouch)
            }
        }
    }
}

private struct WeightTrendCard: View {
    let estimate: AdaptiveEstimate
    @Environment(\.modelContext) private var context
    @State private var points: [(date: Date, kg: Double)] = []

    var body: some View {
        let trend = AdaptiveEstimate.trendSeries(points)
        let all = points.map { $0.kg } + trend.map { $0.kg }
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Weight trend").font(.manrope(15, .bold))
                Spacer()
                Text("\(estimate.kgPerWeek >= 0 ? "+" : "−")\(String(format: "%.2f", abs(estimate.kgPerWeek))) kg/wk")
                    .font(.manrope(13, .bold)).foregroundStyle(Theme.accent)
            }
            if points.count > 1, let lo = all.min(), let hi = all.max() {
                Chart {
                    ForEach(Array(points.enumerated()), id: \.offset) { _, p in
                        PointMark(x: .value("Date", p.date), y: .value("kg", p.kg))
                            .foregroundStyle(Theme.softAccent)
                            .symbolSize(28)
                    }
                    ForEach(Array(trend.enumerated()), id: \.offset) { _, p in
                        LineMark(x: .value("Date", p.date), y: .value("Trend", p.kg))
                            .foregroundStyle(Theme.accent)
                            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                            .interpolationMethod(.monotone)
                    }
                }
                .chartYScale(domain: (lo - 0.3)...(hi + 0.3))
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                        AxisGridLine().foregroundStyle(Theme.border)
                        AxisValueLabel().font(.manrope(10, .medium)).foregroundStyle(Theme.muted)
                    }
                }
                .frame(height: 140)
                HStack(spacing: 14) {
                    Label("daily weigh-ins", systemImage: "circle.fill").foregroundStyle(Theme.softAccent)
                    Label("smoothed trend", systemImage: "line.diagonal").foregroundStyle(Theme.accent)
                }
                .font(.manrope(11, .semibold))
                .labelStyle(.titleAndIcon)
            }
        }
        .card(padding: 14)
        .task {
            let start = DayKey.add(-estimate.windowDays, to: DayKey.today)
            let all = (try? context.fetch(FetchDescriptor<WeightReading>(sortBy: [SortDescriptor(\.timestamp)]))) ?? []
            points = all.filter { $0.timestamp >= start }.map { (date: $0.timestamp, kg: $0.kg) }
        }
    }
}

// MARK: - Monday check-in (Day)

struct CheckInCard: View {
    let estimate: AdaptiveEstimate
    @Environment(AppState.self) private var app

    var body: some View {
        if let target = AdaptiveData.checkInTarget(estimate, app: app), let maintenance = estimate.maintenance {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(app.lastCheckIn == nil ? "Your maintenance is ready" : "Weekly check-in").font(.manrope(17, .bold))
                    Spacer()
                    Button { app.lastCheckIn = AdaptiveData.thisMonday } label: {
                        Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.muted)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss check-in")
                }
                Text(summary(maintenance))
                    .font(.manrope(13, .medium)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Suggested target").font(.manrope(13.5, .semibold))
                    Text("\(target.kcalString) kcal").font(.manrope(17, .heavy))
                    Text("(now \(app.goals.kcal.kcalString))").font(.manrope(12.5, .medium)).foregroundStyle(Theme.muted)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.chip, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                HStack(spacing: 8) {
                    Button("Update") { AdaptiveData.accept(target, app: app) }
                        .buttonStyle(PrimaryButtonStyle())
                    Button { app.lastCheckIn = AdaptiveData.thisMonday } label: {
                        Text("Keep \(app.goals.kcal.kcalString)")
                            .font(.manrope(16, .bold)).foregroundStyle(Theme.accent)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .card()
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.accent, lineWidth: 1.5))
        }
    }

    private func summary(_ maintenance: Double) -> String {
        var s = "You burn about \(maintenance.kcalString) kcal a day before workouts. Your weight trend is \(estimate.kgPerWeek >= 0 ? "+" : "−")\(String(format: "%.2f", abs(estimate.kgPerWeek))) kg a week."
        if let goal = app.goalWeight, let date = estimate.goalDate(goal: goal, pace: app.adaptivePace) {
            s += " At \(paceLabel(app.adaptivePace)) you'd reach \(goal.clean) kg around \(DayKey.short(date))."
        }
        return s
    }
}

private extension Double {
    /// 0.37 → "0.37", 0.5 → "0.5"
    var clean2: String {
        let r = (self * 100).rounded() / 100
        return r.clean
    }
}
