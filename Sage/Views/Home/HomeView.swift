import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(AppState.self) private var app
    @Environment(HealthKitManager.self) private var health
    @Query private var entries: [Entry]
    @Query private var foods: [Food]
    @Query private var meals: [Meal]
    @Query(sort: \WeightReading.timestamp) private var weights: [WeightReading]

    var body: some View {
        let cutoff = DayKey.key(DayKey.add(-7, to: DayKey.today))
        let ledger = Ledger(entries: entries.filter { $0.date >= cutoff }, catalog: Catalog(foods: foods, meals: meals))
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.gap) {
                    PageHeader(eyebrow: DayKey.long(.now), title: greeting) {
                        Button { app.tab = .profile } label: { Image(systemName: "person") }
                            .buttonStyle(CircleIconButtonStyle())
                            .accessibilityLabel("Profile")
                    }
                    SummaryCard(title: "Today", totals: ledger.totals(DayKey.todayKey).macros, goals: app.goals,
                                bonus: app.workoutBonus(on: DayKey.todayKey, health: health))
                    if app.showsWorkouts { WorkoutsCard() }
                    WeightCard(weights: weights)
                    Last7DaysCard(ledger: ledger, goals: app.goals)
                }
                .padding(.horizontal, Theme.pagePadding)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { route in
                if route == "weight" { WeightDetailView() }
            }
        }
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: .now)
        return h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening"
    }
}

// MARK: - Weight card

struct WeightCard: View {
    @Environment(AppState.self) private var app
    @Environment(HealthKitManager.self) private var health
    @Environment(\.modelContext) private var context
    var weights: [WeightReading]

    var body: some View {
        @Bindable var app = app
        let inRange = WeightStats.inRange(weights, app.weightRange)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Weight").font(.manrope(17, .bold))
                Spacer()
                if app.healthEnabled { SyncButton() }
            }
            if app.healthEnabled {
                if let latest = weights.last {
                    HStack(alignment: .lastTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            (Text(String(format: "%.1f", latest.kg)) + Text(" kg").font(.manrope(15, .semibold)).foregroundColor(Theme.muted))
                                .bigNumber(34)
                            Text("\(latest.date == DayKey.todayKey ? "Today" : DayKey.short(latest.timestamp)) · Apple Health")
                                .font(.manrope(12, .medium)).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(WeightStats.changeLabel(inRange)).font(.manrope(17, .bold)).foregroundStyle(Theme.accent)
                            Text(app.weightRange.label).font(.manrope(12, .medium)).foregroundStyle(Theme.muted)
                        }
                    }
                    if inRange.count > 1 {
                        WeightChart(readings: inRange)
                    }
                    HStack {
                        PillPicker(options: WeightRange.allCases.map { ($0, $0.rawValue) }, selection: $app.weightRange, filled: true)
                        Spacer()
                        NavigationLink(value: "weight") {
                            Text("All readings").font(.manrope(14, .bold)).foregroundStyle(Theme.accent)
                                .frame(minHeight: Theme.minTouch)
                        }
                    }
                } else {
                    Text(health.isSyncing ? "Looking for weigh-ins…" : "No weight readings in Apple Health yet. Weigh in with your scales or add one in the Health app.")
                        .font(.manrope(14)).foregroundStyle(Theme.muted)
                }
            } else {
                Text("Connect Apple Health to pull in your weigh-ins automatically from your scales or the Health app.")
                    .font(.manrope(14)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Connect Apple Health") {
                    Task { await health.connect(app: app, context: context) }
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .card()
    }
}

struct SyncButton: View {
    @Environment(AppState.self) private var app
    @Environment(HealthKitManager.self) private var health
    @Environment(\.modelContext) private var context

    var body: some View {
        Button {
            Task { await health.sync(app: app, context: context) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .rotationEffect(.degrees(health.isSyncing ? 360 : 0))
                    .animation(health.isSyncing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: health.isSyncing)
                Text(health.isSyncing ? "Syncing…" : "Synced \(app.syncAgoLabel)")
            }
            .font(.manrope(12, .semibold))
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .background(Theme.chip, in: Capsule())
            .frame(minHeight: Theme.minTouch)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(health.isSyncing)
        .accessibilityLabel("Sync with Apple Health")
    }
}

enum WeightStats {
    static func inRange(_ weights: [WeightReading], _ range: WeightRange) -> [WeightReading] {
        let cutoff = DayKey.add(-range.days, to: DayKey.today)
        return weights.filter { $0.timestamp >= cutoff }
    }

    static func changeLabel(_ list: [WeightReading]) -> String {
        guard let first = list.first, let last = list.last, list.count > 1 else { return "±0.0 kg" }
        return signed(last.kg - first.kg) + " kg"
    }

    static func signed(_ d: Double) -> String {
        let r = (d * 10).rounded() / 10
        let sign = r > 0 ? "+" : r < 0 ? "−" : "±"
        return sign + String(format: "%.1f", abs(r))
    }
}

// MARK: - Last 7 days

struct Last7DaysCard: View {
    @Environment(AppState.self) private var app
    var ledger: Ledger
    var goals: Goals

    var body: some View {
        let days = (0..<7).reversed().map { DayKey.add(-$0, to: DayKey.today) }
        let totals = days.map { ledger.totals(DayKey.key($0)) }
        let logged = totals.filter { $0.count > 0 }
        let avg = logged.isEmpty ? nil : logged.map(\.macros.kcal).reduce(0, +) / Double(logged.count)
        let hits = logged.filter { $0.macros.p >= goals.p }.count

        Button { app.weekOffset = 0; app.tab = .week } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Last 7 days").font(.manrope(17, .bold))
                    Spacer()
                    (Text("avg ") + Text(avg?.kcalString ?? "—").font(.manrope(15, .bold)).foregroundColor(Theme.text) + Text(" kcal"))
                        .font(.manrope(13, .medium)).foregroundStyle(Theme.muted)
                }
                HStack(alignment: .bottom, spacing: 16) {
                    VStack(spacing: 6) {
                        HStack(alignment: .bottom, spacing: 6) {
                            ForEach(0..<days.count, id: \.self) { i in
                                let k = totals[i].macros.kcal
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(i == 6 ? Theme.accent : k > goals.kcal + 100 ? Theme.over : Theme.softAccent)
                                    .frame(height: max(4, min(k, 2600) / 2600 * 54))
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .frame(height: 54, alignment: .bottom)
                        HStack(spacing: 6) {
                            ForEach(days, id: \.self) { d in
                                Text(String(d.formatted(.dateTime.weekday(.narrow))))
                                    .font(.manrope(11, .medium)).foregroundStyle(Theme.muted)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(hits)/\(logged.count)").bigNumber(24, weight: .heavy).foregroundStyle(Theme.accent)
                        Text("days hit protein").font(.manrope(12, .medium)).foregroundStyle(Theme.muted)
                    }
                }
            }
            .card()
        }
        .buttonStyle(PressableStyle())
        .accessibilityHint("Opens the Week view")
    }
}
