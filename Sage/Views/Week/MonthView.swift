import SwiftUI
import SwiftData

enum WeekMode: String, Hashable {
    case week, month
}

/// Week › Month: calendar heat map of the month, month tiles, and streaks.
struct MonthContent: View {
    @Environment(AppState.self) private var app
    @Environment(HealthKitManager.self) private var health
    @Query private var entries: [Entry]
    @Query private var foods: [Food]
    @Query private var meals: [Meal]
    @Query(sort: \WeightReading.timestamp) private var weights: [WeightReading]

    private var firstOfMonth: Date {
        let cal = DayKey.cal
        let thisMonth = cal.date(from: cal.dateComponents([.year, .month], from: .now)) ?? .now
        return cal.date(byAdding: .month, value: app.monthOffset, to: thisMonth) ?? thisMonth
    }

    var body: some View {
        @Bindable var app = app
        let cal = DayKey.cal
        let first = firstOfMonth
        let daysInMonth = cal.range(of: .day, in: .month, for: first)?.count ?? 30
        let last = DayKey.add(daysInMonth - 1, to: first)
        let ledger = Ledger(entries: entries, catalog: Catalog(foods: foods, meals: meals))
        let stats = DayStats(ledger: ledger, app: app, health: health,
                             weighInDays: Set(weights.map(\.date)))

        ScrollView {
            VStack(spacing: Theme.gap) {
                PageHeader(eyebrow: "\(DayKey.short(first)) – \(DayKey.short(last))",
                           title: monthTitle(first)) {
                    PrevNextButtons(canGoNext: app.monthOffset < 0, prevLabel: "Previous month", nextLabel: "Next month",
                                    prev: { app.monthOffset -= 1 },
                                    next: { if app.monthOffset < 0 { app.monthOffset += 1 } })
                }
                PillPicker(options: [(WeekMode.week, "Week"), (.month, "Month")], selection: $app.weekMode)

                CalendarCard(first: first, days: daysInMonth, stats: stats)
                MonthTiles(first: first, days: daysInMonth, stats: stats, weights: weights)
                StreaksCard(stats: stats, weights: weights)
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .task(id: app.monthOffset) {
            if app.showsWorkouts {
                await health.loadWorkouts(from: first, days: daysInMonth)
            }
        }
    }
}

/// "November", or "November 2025" for another year.
private func monthTitle(_ date: Date) -> String {
    let sameYear = DayKey.cal.component(.year, from: date) == DayKey.cal.component(.year, from: .now)
    return sameYear ? date.formatted(.dateTime.month(.wide)) : date.formatted(.dateTime.month(.wide).year())
}

/// Per-day facts used by the calendar, tiles and streaks.
@MainActor
struct DayStats {
    let ledger: Ledger
    let app: AppState
    let health: HealthKitManager
    let weighInDays: Set<String>

    enum Status { case notLogged, under, onBudget, over, future }

    func totals(_ key: String) -> DayTotals { ledger.totals(key) }
    func budget(_ key: String) -> Double { app.budget(on: key, health: health) }
    func logged(_ key: String) -> Bool { totals(key).count > 0 }
    func proteinHit(_ key: String) -> Bool { logged(key) && totals(key).macros.p >= app.goals.p }
    func onBudget(_ key: String) -> Bool { logged(key) && totals(key).macros.kcal <= budget(key) * 1.05 }
    func weighedIn(_ key: String) -> Bool { weighInDays.contains(key) }

    func status(_ key: String) -> Status {
        if key > DayKey.todayKey { return .future }
        let t = totals(key)
        guard t.count > 0 else { return .notLogged }
        let ratio = t.macros.kcal / max(budget(key), 1)
        if ratio > 1.05 { return .over }
        if ratio >= 0.85 { return .onBudget }
        return .under
    }
}

// MARK: - Calendar

private struct CalendarCard: View {
    let first: Date
    let days: Int
    let stats: DayStats
    @Environment(AppState.self) private var app

    var body: some View {
        let lead = (DayKey.cal.component(.weekday, from: first) + 5) % 7
        let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: columns, spacing: 5) {
                ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, d in
                    Text(d).font(.manrope(11, .bold)).foregroundStyle(Theme.muted)
                }
                ForEach(0..<lead, id: \.self) { _ in Color.clear.frame(height: 1) }
                ForEach(0..<days, id: \.self) { i in
                    let date = DayKey.add(i, to: first)
                    DayCell(date: date, stats: stats) { open(date) }
                }
            }
            Legend()
        }
        .card(padding: 14)
    }

    private func open(_ date: Date) {
        guard date <= .now else { return }
        app.dayOffset = DayKey.cal.dateComponents([.day], from: DayKey.today, to: DayKey.cal.startOfDay(for: date)).day ?? 0
        app.tab = .day
    }
}

private struct DayCell: View {
    let date: Date
    let stats: DayStats
    var action: () -> Void

    var body: some View {
        let key = DayKey.key(date)
        let status = stats.status(key)
        let day = DayKey.cal.component(.day, from: date)
        let kcal = stats.totals(key).macros.kcal
        let (fill, text): (Color, Color) = {
            switch status {
            case .onBudget: return (Theme.accent, Theme.onAccent)
            case .under: return (Theme.softAccent, Theme.text)
            case .over: return (Theme.over, Color.white)
            case .notLogged, .future: return (.clear, Theme.muted)
            }
        }()
        Button(action: action) {
            VStack(spacing: 0) {
                Text("\(day)").font(.manrope(12, .bold))
                if status != .notLogged && status != .future {
                    Text(String(format: "%.1fk", kcal / 1000)).font(.manrope(8.5, .bold)).opacity(0.85)
                }
            }
            .foregroundStyle(status == .future ? Theme.dashed : text)
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .background(fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                if status == .notLogged {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Theme.dashed, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                }
                if key == DayKey.todayKey {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.text, lineWidth: 2)
                }
            }
            .overlay(alignment: .bottom) {
                if stats.proteinHit(key) {
                    Circle().fill(status == .under ? Theme.accent : Color.white)
                        .frame(width: 5, height: 5).padding(.bottom, 3)
                }
            }
        }
        .buttonStyle(PressableStyle())
        .disabled(status == .future)
        .accessibilityLabel(accessibility(key, status: status, day: day, kcal: kcal))
    }

    private func accessibility(_ key: String, status: DayStats.Status, day: Int, kcal: Double) -> String {
        switch status {
        case .future: return "\(day)"
        case .notLogged: return "\(day), not logged"
        default:
            let s = status == .over ? "over budget" : status == .under ? "well under budget" : "on budget"
            return "\(day), \(kcal.kcalString) kcal, \(s)\(stats.proteinHit(key) ? ", protein hit" : "")"
        }
    }
}

private struct Legend: View {
    var body: some View {
        HStack(spacing: 10) {
            item(Theme.accent, "on budget")
            item(Theme.softAccent, "well under")
            item(Theme.over, "over")
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.dashed, style: StrokeStyle(lineWidth: 1.2, dash: [2, 2]))
                    .frame(width: 11, height: 11)
                Text("not logged")
            }
            HStack(spacing: 4) { Circle().fill(Theme.accent).frame(width: 5, height: 5); Text("protein") }
        }
        .font(.manrope(10.5, .semibold))
        .foregroundStyle(Theme.muted)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private func item(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 11, height: 11)
            Text(label)
        }
    }
}

// MARK: - Tiles

private struct MonthTiles: View {
    let first: Date
    let days: Int
    let stats: DayStats
    let weights: [WeightReading]
    @Environment(AppState.self) private var app

    var body: some View {
        let keys = (0..<days).map { DayKey.key(DayKey.add($0, to: first)) }.filter { $0 <= DayKey.todayKey }
        let logged = keys.filter { stats.logged($0) }
        let n = Double(max(logged.count, 1))
        let avgK = logged.reduce(0) { $0 + stats.totals($1).macros.kcal } / n
        let avgP = logged.reduce(0) { $0 + stats.totals($1).macros.p } / n
        let onBudget = logged.filter { stats.onBudget($0) }.count
        let proteinDays = logged.filter { stats.proteinHit($0) }.count
        let monthWeights = weights.filter { keys.contains($0.date) }

        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            tile("Avg calories", logged.isEmpty ? "—" : avgK.kcalString, "\(logged.count) days logged")
            tile("On budget", "\(onBudget) / \(logged.count)", "days")
            tile("Avg protein", logged.isEmpty ? "—" : "\(avgP.grams) g", "\(proteinDays) days ≥ \(app.goals.p.grams) g")
            if let a = monthWeights.first, let b = monthWeights.last, monthWeights.count > 1 {
                tile("Weight", WeightStats.signed(b.kg - a.kg).replacingOccurrences(of: "±", with: "") + " kg",
                     String(format: "%.1f → %.1f kg", a.kg, b.kg))
            } else {
                tile("Weight", "—", "from Apple Health")
            }
        }
    }

    private func tile(_ label: String, _ value: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.manrope(12, .semibold)).foregroundStyle(Theme.muted)
            Text(value).bigNumber(22).lineLimit(1).minimumScaleFactor(0.7)
            Text(sub).font(.manrope(11, .semibold)).foregroundStyle(Theme.accent).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 12)
    }
}

// MARK: - Streaks

private struct StreaksCard: View {
    let stats: DayStats
    let weights: [WeightReading]
    @Environment(AppState.self) private var app

    var body: some View {
        let logging = Streak.compute(stats.logged)
        let protein = Streak.compute(stats.proteinHit)
        let budget = Streak.compute(stats.onBudget)
        let weighIns = Streak.compute(stats.weighedIn)
        VStack(alignment: .leading, spacing: 0) {
            Text("Streaks").font(.manrope(17, .bold)).padding(.bottom, 4)
            StreakRow(icon: "flame.fill", tint: Theme.accent, title: "Logging",
                      detail: logging.current > 0 ? "Every day for \(logging.current) day\(logging.current == 1 ? "" : "s")" : "Log today to start a streak",
                      streak: logging)
            Divider().overlay(Theme.border)
            StreakRow(icon: "bolt.heart.fill", tint: Theme.accent, title: "Protein ≥ \(app.goals.p.grams) g",
                      detail: protein.current > 0 ? "Hit it \(protein.current) day\(protein.current == 1 ? "" : "s") running" : "Hit your protein to start one",
                      streak: protein)
            Divider().overlay(Theme.border)
            StreakRow(icon: "target", tint: Theme.carbs, title: "On budget",
                      detail: "Within your calories, workouts included", streak: budget)
            Divider().overlay(Theme.border)
            StreakRow(icon: "scalemass.fill", tint: Theme.fat, title: "Weigh-ins",
                      detail: "Days in a row with a weigh-in", streak: weighIns)
            if let next = Streak.nextMilestone(after: logging.current) {
                HStack(spacing: 12) {
                    Image(systemName: "medal.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.onAccent)
                        .frame(width: 40, height: 40)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Next milestone").font(.manrope(14, .bold))
                        Text("\(next - logging.current) more day\(next - logging.current == 1 ? "" : "s") for a \(next)-day logging streak")
                            .font(.manrope(12, .medium)).foregroundStyle(Theme.muted)
                    }
                }
                .padding(.top, 12)
            }
        }
        .card()
    }
}

private struct StreakRow: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String
    let streak: Streak

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.manrope(14.5, .bold))
                Text(detail).font(.manrope(12, .medium)).foregroundStyle(Theme.muted).lineLimit(1).minimumScaleFactor(0.85)
                HStack(spacing: 4) {
                    ForEach(Array(streak.last10.enumerated()), id: \.offset) { i, hit in
                        Circle()
                            .fill(hit ? tint : .clear)
                            .overlay(Circle().strokeBorder(hit ? .clear : Theme.dashed, lineWidth: 1.5))
                            .frame(width: 9, height: 9)
                    }
                }
                .padding(.top, 2)
                .accessibilityHidden(true)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(streak.current)").bigNumber(24)
                Text("days · best \(streak.best)").font(.manrope(11, .semibold)).foregroundStyle(Theme.muted)
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

/// A run of days where a condition held.
struct Streak {
    var current: Int
    var best: Int
    /// The last 10 days, oldest first (today last).
    var last10: [Bool]

    /// Looks back up to two years. Today doesn't break a streak until it's over:
    /// if today isn't done yet, the current streak counts up to yesterday.
    @MainActor
    static func compute(_ hit: (String) -> Bool) -> Streak {
        let today = DayKey.today
        let span = 730
        var flags: [Bool] = []
        for i in stride(from: span - 1, through: 0, by: -1) {
            flags.append(hit(DayKey.key(DayKey.add(-i, to: today))))
        }
        var best = 0, run = 0
        for f in flags { run = f ? run + 1 : 0; best = max(best, run) }
        var current = 0
        var idx = flags.count - 1
        if !flags[idx] { idx -= 1 } // today not done yet
        while idx >= 0 && flags[idx] { current += 1; idx -= 1 }
        return Streak(current: current, best: max(best, current), last10: Array(flags.suffix(10)))
    }

    static func nextMilestone(after current: Int) -> Int? {
        [7, 14, 21, 30, 50, 75, 100, 150, 200, 365, 500, 730].first { $0 > current }
    }
}
