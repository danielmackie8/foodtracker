import SwiftUI

enum ActivityTab: String, Hashable {
    case workouts, steps
}

/// Week "Activity" card: a Workouts / Steps switch over one shared card.
struct WeekActivityCard: View {
    let monday: Date
    /// Daily step totals for the week (YYYY-MM-DD → steps).
    let steps: [String: Double]

    @Environment(AppState.self) private var app
    @Environment(HealthKitManager.self) private var health
    @AppStorage("weekActivityTab") private var tab: ActivityTab = .workouts
    @State private var showWorkouts = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Activity").font(.manrope(17, .bold))
                Spacer()
                Text("from Apple Health").font(.manrope(13, .medium)).foregroundStyle(Theme.muted)
            }
            PillPicker(options: [(ActivityTab.workouts, "Workouts"), (.steps, "Steps")], selection: $tab)

            switch tab {
            case .workouts:
                if app.readWorkouts {
                    Button { showWorkouts = true } label: { WeekWorkoutsSummary(monday: monday) }
                        .buttonStyle(PressableStyle())
                        .accessibilityHint("Shows the week's workouts by type")
                } else {
                    off("Workouts")
                }
            case .steps:
                if app.readSteps {
                    WeekStepsSummary(monday: monday, steps: steps, goal: app.stepGoal)
                } else {
                    off("Steps")
                }
            }
        }
        .card()
        .sheet(isPresented: $showWorkouts) {
            WeekWorkoutsSheet(monday: monday)
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(28)
                .presentationBackground(Theme.background)
        }
        .task(id: monday) {
            guard app.readWorkouts else { return }
            try? await health.requestAuthorization()
            await health.loadWorkouts(from: monday, days: 7)
        }
    }

    private func off(_ what: String) -> some View {
        Text("\(what) reading is off. Turn it on in Profile › Apple Health.")
            .font(.manrope(14)).foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
    }
}

/// Shared big-number line used by both tabs.
private struct ActivityHeadline: View {
    var icon: String
    var value: String
    var unit: String
    var sub: String
    var chevron = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 48, height: 48)
                .background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 0) {
                (Text(value) + Text(" \(unit)").font(.manrope(15, .semibold)).foregroundColor(Theme.muted))
                    .bigNumber(30)
                Text(sub).font(.manrope(13, .medium)).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.muted)
            }
        }
    }
}

/// Seven day bars with weekday letters. `nil` values draw as dashed outlines.
private struct DayBars: View {
    var days: [Date]
    var values: [Double?]
    var scale: Double
    var goal: Double? = nil
    var color: (Double) -> Color = { _ in Theme.accent }
    private let height: CGFloat = 96

    var body: some View {
        let today = DayKey.todayKey
        VStack(spacing: 8) {
            ZStack(alignment: .bottom) {
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(0..<days.count, id: \.self) { i in
                        Group {
                            if let v = values[i], v >= 1 {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(color(v))
                                    .frame(height: max(6, min(v, scale) / scale * height))
                            } else {
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(Theme.dashed, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                                    .frame(height: height)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                if let goal {
                    Path { p in p.move(to: .zero); p.addLine(to: CGPoint(x: 1000, y: 0)) }
                        .stroke(Theme.text.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .frame(height: 1)
                        .clipped()
                        .offset(y: -min(goal, scale) / scale * height)
                        .accessibilityHidden(true)
                }
            }
            .frame(height: height, alignment: .bottom)
            HStack(spacing: 10) {
                ForEach(0..<days.count, id: \.self) { i in
                    let key = DayKey.key(days[i])
                    Text(DayKey.initial(days[i]))
                        .font(.manrope(12, key == today ? .heavy : .medium))
                        .foregroundStyle(key == today ? Theme.text : Theme.muted)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

/// Workouts tab: week total burnt and a bar per day.
struct WeekWorkoutsSummary: View {
    let monday: Date
    @Environment(HealthKitManager.self) private var health

    var body: some View {
        let today = DayKey.todayKey
        let days = (0..<7).map { DayKey.add($0, to: monday) }
        let keys = days.map(DayKey.key)
        let perDay = keys.map { health.burnt(on: $0) }
        let workouts = keys.flatMap { health.workoutsByDay[$0] ?? [] }
        let total = perDay.reduce(0, +)
        let duration = workouts.reduce(0) { $0 + $1.duration }
        let elapsed = keys.filter { $0 <= today }.count

        VStack(alignment: .leading, spacing: 16) {
            ActivityHeadline(
                icon: "flame", value: total.kcalString, unit: "kcal",
                sub: workouts.isEmpty
                    ? "No workouts this week yet"
                    : "\(workouts.count) workout\(workouts.count == 1 ? "" : "s") · \(WorkoutSummary.durationLabel(duration)) · avg \((total / Double(max(elapsed, 1))).kcalString) a day",
                chevron: true)
            DayBars(days: days, values: perDay.map { $0 >= 1 ? $0 : nil }, scale: max(perDay.max() ?? 0, 1))
        }
        .contentShape(Rectangle())
    }
}

/// Steps tab: daily average, weekly total and bars against the step goal.
struct WeekStepsSummary: View {
    let monday: Date
    let steps: [String: Double]
    let goal: Double

    var body: some View {
        let today = DayKey.todayKey
        let days = (0..<7).map { DayKey.add($0, to: monday) }
        let keys = days.map(DayKey.key)
        let values: [Double?] = keys.map { $0 <= today ? steps[$0] : nil }
        let logged = values.compactMap { $0 }
        let total = logged.reduce(0, +)
        let avg = logged.isEmpty ? 0 : total / Double(logged.count)
        let hits = logged.filter { $0 >= goal }.count
        let scale = max((logged.max() ?? 0), goal) * 1.08

        VStack(alignment: .leading, spacing: 16) {
            ActivityHeadline(
                icon: "figure.walk", value: logged.isEmpty ? "—" : Int(avg.rounded()).formatted(), unit: "steps a day",
                sub: logged.isEmpty
                    ? "No steps in Apple Health this week"
                    : "\(Int(total).formatted()) this week · \(hits) day\(hits == 1 ? "" : "s") over \(Int(goal).formatted())")
            DayBars(days: days, values: values, scale: scale, goal: goal,
                    color: { $0 >= goal ? Theme.accent : Theme.softAccent })
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(zip(days, values).map { d, v in
                    "\(DayKey.weekday(d)): \(v.map { Int($0).formatted() } ?? "no data") steps"
                }.joined(separator: ", "))
        }
    }
}

/// Breakdown of a week's workouts grouped by type, plus the days trained.
struct WeekWorkoutsSheet: View {
    let monday: Date
    @Environment(HealthKitManager.self) private var health
    @Environment(\.dismiss) private var dismiss

    private struct WorkoutGroup: Identifiable {
        var name: String
        var icon: String
        var sessions = 0
        var duration: TimeInterval = 0
        var km: Double = 0
        var kcal: Double = 0
        var id: String { name }

        var detail: String {
            var parts = ["\(sessions) session\(sessions == 1 ? "" : "s")", WorkoutSummary.durationLabel(duration)]
            if km >= 0.05 { parts.append(String(format: "%.1f km", km)) }
            return parts.joined(separator: " · ")
        }
    }

    var body: some View {
        let today = DayKey.todayKey
        let days = (0..<7).map { DayKey.add($0, to: monday) }
        let keys = days.map(DayKey.key)
        let workouts = keys.flatMap { health.workoutsByDay[$0] ?? [] }
        let total = workouts.reduce(0) { $0 + $1.kcal }
        let groups = Self.group(workouts)
        let trained = keys.map { !(health.workoutsByDay[$0] ?? []).isEmpty }
        let elapsed = keys.filter { $0 <= today }.count

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Workouts").font(.manrope(24, .heavy))
                        Text("\(DayKey.short(monday)) – \(DayKey.short(DayKey.add(6, to: monday))) · from Apple Health")
                            .font(.manrope(13, .medium)).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Button("Done") { dismiss() }
                        .font(.manrope(16, .bold))
                        .foregroundStyle(Theme.accent)
                        .frame(minHeight: Theme.minTouch)
                }

                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        (Text(total.kcalString) + Text(" kcal burnt").font(.manrope(15, .semibold)).foregroundColor(Theme.muted))
                            .bigNumber(32)
                        Spacer()
                        Text("\(workouts.count) workout\(workouts.count == 1 ? "" : "s")")
                            .font(.manrope(13, .medium)).foregroundStyle(Theme.muted)
                    }
                    .padding(.bottom, groups.isEmpty ? 0 : 10)

                    if groups.isEmpty {
                        Text("No workouts in Apple Health this week.")
                            .font(.manrope(14)).foregroundStyle(Theme.muted)
                            .padding(.top, 4)
                    }
                    ForEach(groups) { g in
                        Divider().overlay(Theme.border)
                        HStack(spacing: 12) {
                            Image(systemName: g.icon)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                                .frame(width: 36, height: 36)
                                .background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(g.name).font(.manrope(15, .semibold))
                                Text(g.detail).font(.manrope(12, .medium)).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            (Text(g.kcal.kcalString).font(.manrope(15, .bold))
                             + Text(" kcal").font(.manrope(13, .medium)).foregroundColor(Theme.muted))
                                .monospacedDigit()
                        }
                        .frame(minHeight: 58)
                        .accessibilityElement(children: .combine)
                    }

                    Divider().overlay(Theme.border).padding(.top, groups.isEmpty ? 12 : 0)
                    // Days trained
                    HStack {
                        ForEach(0..<7, id: \.self) { i in
                            VStack(spacing: 4) {
                                Circle()
                                    .fill(trained[i] ? Theme.accent : .clear)
                                    .overlay(Circle().strokeBorder(trained[i] ? .clear : (keys[i] > today ? Theme.dashed : Theme.muted), lineWidth: 1.5))
                                    .frame(width: 16, height: 16)
                                Text(DayKey.initial(days[i])).font(.manrope(11, .medium)).foregroundStyle(Theme.muted)
                            }
                            .frame(maxWidth: .infinity)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(DayKey.weekday(days[i])): \(trained[i] ? "worked out" : "no workout")")
                        }
                    }
                    .padding(.top, 14)
                    Text("Worked out on \(trained.filter { $0 }.count) of \(elapsed) day\(elapsed == 1 ? "" : "s")")
                        .font(.manrope(13, .semibold))
                        .padding(.top, 8)
                }
                .card()
            }
            .padding(Theme.pagePadding)
        }
        .task(id: monday) { await health.loadWorkouts(from: monday, days: 7) }
    }

    /// Groups by workout name, biggest burn first.
    private static func group(_ workouts: [WorkoutSummary]) -> [WorkoutGroup] {
        var byName: [String: WorkoutGroup] = [:]
        for w in workouts {
            var g = byName[w.name] ?? WorkoutGroup(name: w.name, icon: w.icon)
            g.sessions += 1
            g.duration += w.duration
            g.km += w.distanceKm ?? 0
            g.kcal += w.kcal
            byName[w.name] = g
        }
        return byName.values.sorted { $0.kcal > $1.kcal }
    }
}
