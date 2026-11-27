import SwiftUI
import SwiftData

struct WeekView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        let monday = DayKey.add(app.weekOffset * 7, to: DayKey.monday(of: .now))
        if app.weekMode == .month {
            MonthContent()
        } else {
            WeekContent(monday: monday).id(app.weekOffset)
        }
    }
}

private struct WeekContent: View {
    @Environment(AppState.self) private var app
    @Environment(HealthKitManager.self) private var health
    @State private var steps: [String: Double] = [:]
    let monday: Date
    @Query private var allEntries: [Entry]
    @Query private var foods: [Food]
    @Query private var meals: [Meal]
    @Query(sort: \WeightReading.timestamp) private var allWeights: [WeightReading]

    init(monday: Date) {
        self.monday = monday
    }

    private var from: String { DayKey.key(monday) }
    private var to: String { DayKey.key(DayKey.add(6, to: monday)) }
    private var entries: [Entry] { allEntries.filter { $0.date >= from && $0.date <= to } }
    private var weekWeights: [WeightReading] { allWeights.filter { $0.date >= from && $0.date <= to } }

    private struct DayStat {
        var date: Date
        var key: String
        var totals: DayTotals
        var future: Bool
        var isToday: Bool
    }

    var body: some View {
        let goals = app.goals
        let ledger = Ledger(entries: entries, catalog: Catalog(foods: foods, meals: meals))
        let today = DayKey.todayKey
        let days: [DayStat] = (0..<7).map { i in
            let d = DayKey.add(i, to: monday)
            let k = DayKey.key(d)
            return DayStat(date: d, key: k, totals: ledger.totals(k), future: k > today, isToday: k == today)
        }
        let logged = days.filter { !$0.future && $0.totals.count > 0 }
        let n = Double(max(logged.count, 1))
        let avg = logged.reduce(into: Macros()) { $0 += $1.totals.macros } * (1 / n)
        // Steps: average over the week's days so far that have step data.
        let elapsedKeys = days.filter { !$0.future }.map(\.key)
        let stepDays = elapsedKeys.compactMap { steps[$0] }
        let avgSteps = stepDays.isEmpty ? nil : stepDays.reduce(0, +) / Double(stepDays.count)
        let proteinHits = logged.filter { $0.totals.macros.p >= goals.p }.count

        ScrollView {
            VStack(spacing: Theme.gap) {
                PageHeader(eyebrow: rangeLabel, title: title) {
                    PrevNextButtons(canGoNext: app.weekOffset < 0, prevLabel: "Previous week", nextLabel: "Next week",
                                    prev: { app.weekOffset -= 1 },
                                    next: { if app.weekOffset < 0 { app.weekOffset += 1 } })
                }
                PillPicker(options: [(WeekMode.week, "Week"), (.month, "Month")],
                           selection: Binding(get: { app.weekMode }, set: { app.weekMode = $0 }))

                LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.gap), GridItem(.flexible(), spacing: Theme.gap)], spacing: Theme.gap) {
                    let diff = avg.kcal - goals.kcal
                    StatTile(label: "Avg calories",
                             value: logged.isEmpty ? "—" : avg.kcal.kcalString,
                             sub: logged.isEmpty ? "No data" : "\(diff >= 0 ? "+" : "−")\(abs(diff).kcalString) a day vs \(goals.kcal.kcalString)")
                    StatTile(label: "Avg protein", value: logged.isEmpty ? "—" : "\(avg.p.grams) g", sub: "target \(goals.p.grams) g")
                    StatTile(label: "Avg steps",
                             value: avgSteps.map { Int($0.rounded()).formatted() } ?? "—",
                             sub: stepsSub(days: stepDays.count),
                             subColor: Theme.accent)
                    StatTile(label: "Weight", value: weightChange, sub: weightSub, subColor: Theme.accent)
                }

                if app.adaptiveOn {
                    MaintenanceCard(estimate: AdaptiveData.estimate(entries: allEntries, catalog: Catalog(foods: foods, meals: meals),
                                                                    weights: allWeights, app: app, health: health))
                }

                CaloriesChartCard(days: days.map { (date: $0.date, totals: $0.totals, future: $0.future, isToday: $0.isToday) }, goal: goals.kcal)

                if app.healthEnabled { WeekActivityCard(monday: monday, steps: steps) }

                MacroSplitCard(avg: avg, hasData: !logged.isEmpty,
                               dots: days.map { (date: $0.date, hit: !$0.future && $0.totals.count > 0 && $0.totals.macros.p >= goals.p, future: $0.future) },
                               proteinLabel: "Protein ≥\(goals.p.grams) g · \(proteinHits)/\(logged.count)")
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .task(id: app.healthEnabled && app.readSteps) { await loadSteps() }
        .task { await AdaptiveData.loadWorkouts(app: app, health: health) }
    }

    private func stepsSub(days: Int) -> String {
        if !app.healthEnabled || !app.readSteps { return "Connect Apple Health" }
        if days == 0 { return "from Apple Health" }
        return "a day · \(days) day\(days == 1 ? "" : "s")"
    }

    private func loadSteps() async {
        guard app.healthEnabled, app.readSteps else { steps = [:]; return }
        // Shows the Health sheet only for types not asked about yet (Steps, for existing users).
        try? await health.requestAuthorization()
        let end = min(DayKey.add(7, to: monday), Date())
        steps = await health.dailySteps(from: monday, to: end)
    }

    private var title: String {
        switch app.weekOffset {
        case 0: return "This week"
        case -1: return "Last week"
        default: return "Week"
        }
    }

    private var rangeLabel: String {
        "\(DayKey.short(monday)) – \(DayKey.short(DayKey.add(6, to: monday)))"
    }

    private var weightChange: String {
        guard weekWeights.count > 1, let a = weekWeights.first, let b = weekWeights.last else { return "—" }
        return WeightStats.signed(b.kg - a.kg).replacingOccurrences(of: "±", with: "") + " kg"
    }

    private var weightSub: String {
        guard weekWeights.count > 1, let a = weekWeights.first, let b = weekWeights.last else { return "from Apple Health" }
        return String(format: "%.1f → %.1f kg", a.kg, b.kg)
    }
}

private struct StatTile: View {
    var label: String
    var value: String
    var sub: String
    var subColor: Color = Theme.muted

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.manrope(13, .semibold)).foregroundStyle(Theme.muted)
            Text(value).bigNumber(26).lineLimit(1).minimumScaleFactor(0.7)
            Text(sub).font(.manrope(12, .medium)).foregroundStyle(subColor).lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .card(padding: 14)
        .accessibilityElement(children: .combine)
    }
}

private struct CaloriesChartCard: View {
    var days: [(date: Date, totals: DayTotals, future: Bool, isToday: Bool)]
    var goal: Double
    private let height: CGFloat = 128

    var body: some View {
        let maxK = max(2600, goal * 1.4)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Calories").font(.manrope(17, .bold))
                Spacer()
                HStack(spacing: 6) {
                    DashedLine().stroke(Theme.text.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .frame(width: 16, height: 2)
                    Text("\(goal.kcalString) target").font(.manrope(12, .medium)).foregroundStyle(Theme.muted)
                }
            }
            ZStack(alignment: .bottom) {
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(days.indices, id: \.self) { i in
                        let d = days[i]
                        let empty = d.future || d.totals.count == 0
                        let k = d.totals.macros.kcal
                        Group {
                            if empty {
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(Theme.dashed, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                                    .frame(height: height)
                            } else {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(k > goal + 100 ? Theme.over : Theme.accent)
                                    .frame(height: max(6, min(k, maxK) / maxK * height))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("\(DayKey.weekday(d.date)): \(empty ? "nothing logged" : "\(k.kcalString) kcal")")
                    }
                }
                DashedLine()
                    .stroke(Theme.text.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .frame(height: 2)
                    .offset(y: -goal / maxK * height + 1)
                    .accessibilityHidden(true)
            }
            .frame(height: height, alignment: .bottom)
            HStack(spacing: 10) {
                ForEach(days.indices, id: \.self) { i in
                    Text(DayKey.initial(days[i].date))
                        .font(.manrope(12, days[i].isToday ? .heavy : .medium))
                        .foregroundStyle(days[i].isToday ? Theme.text : Theme.muted)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .card()
    }
}

private struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

private struct MacroSplitCard: View {
    var avg: Macros
    var hasData: Bool
    var dots: [(date: Date, hit: Bool, future: Bool)]
    var proteinLabel: String

    var body: some View {
        let kp = avg.p * 4, kc = avg.c * 4, kf = avg.f * 9
        let kt = max(kp + kc + kf, 1)
        let parts: [(String, Double, Double, Color)] = [
            ("Protein", avg.p, kp / kt, Theme.accent),
            ("Carbs", avg.c, kc / kt, Theme.carbs),
            ("Fat", avg.f, kf / kt, Theme.fat),
        ]
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Macros").font(.manrope(17, .bold))
                Spacer()
                Text("daily average").font(.manrope(12, .medium)).foregroundStyle(Theme.muted)
            }
            GeometryReader { geo in
                HStack(spacing: 3) {
                    if hasData {
                        ForEach(parts.indices, id: \.self) { i in
                            let p = parts[i]
                            RoundedRectangle(cornerRadius: 4).fill(p.3)
                                .frame(width: max(0, (geo.size.width - 6) * p.2))
                        }
                    } else {
                        Capsule().fill(Theme.track)
                    }
                }
            }
            .frame(height: 12)
            .clipShape(Capsule())

            VStack(spacing: 8) {
                ForEach(parts.indices, id: \.self) { i in
                    let p = parts[i]
                    HStack {
                        Circle().fill(p.3).frame(width: 8, height: 8)
                        Text(p.0).font(.manrope(14, .semibold))
                        Spacer()
                        (Text("\(p.1.grams) g ").font(.manrope(14, .bold))
                         + Text("\(Int((p.2 * 100).rounded()))%").font(.manrope(13, .medium)).foregroundColor(Theme.muted))
                            .monospacedDigit()
                    }
                }
            }

            Divider().overlay(Theme.border)

            VStack(alignment: .leading, spacing: 10) {
                Text(proteinLabel).font(.manrope(14, .semibold))
                HStack {
                    ForEach(dots.indices, id: \.self) { i in
                        let d = dots[i]
                        VStack(spacing: 4) {
                            Circle()
                                .fill(d.hit ? Theme.accent : .clear)
                                .overlay(Circle().strokeBorder(d.hit ? .clear : (d.future ? Theme.dashed : Theme.muted), lineWidth: 1.5))
                                .frame(width: 16, height: 16)
                            Text(DayKey.initial(d.date)).font(.manrope(11, .medium)).foregroundStyle(Theme.muted)
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(DayKey.weekday(d.date)): protein \(d.hit ? "hit" : "missed")")
                    }
                }
            }
        }
        .card()
    }
}
