import SwiftUI

/// Week card: total burnt in workouts and a bar per day. Tapping opens the breakdown by type.
struct WeekWorkoutsCard: View {
    let monday: Date
    @Environment(HealthKitManager.self) private var health
    @State private var showDetails = false

    private var days: [Date] { (0..<7).map { DayKey.add($0, to: monday) } }

    var body: some View {
        let today = DayKey.todayKey
        let keys = days.map(DayKey.key)
        let perDay = keys.map { health.burnt(on: $0) }
        let workouts = keys.flatMap { health.workoutsByDay[$0] ?? [] }
        let total = perDay.reduce(0, +)
        let duration = workouts.reduce(0) { $0 + $1.duration }
        let elapsed = keys.filter { $0 <= today }.count
        let maxBurn = max(perDay.max() ?? 0, 1)

        Button { showDetails = true } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Workouts").font(.manrope(17, .bold))
                    Spacer()
                    if !workouts.isEmpty {
                        Text(WorkoutSummary.durationLabel(duration))
                            .font(.manrope(13, .medium)).foregroundStyle(Theme.muted)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                }

                HStack(spacing: 14) {
                    Image(systemName: "flame")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 48, height: 48)
                        .background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 0) {
                        (Text(total.kcalString) + Text(" kcal").font(.manrope(15, .semibold)).foregroundColor(Theme.muted))
                            .bigNumber(30)
                        Text(workouts.isEmpty
                             ? "No workouts this week yet"
                             : "\(workouts.count) workout\(workouts.count == 1 ? "" : "s") · avg \((total / Double(max(elapsed, 1))).kcalString) kcal a day")
                            .font(.manrope(13, .medium)).foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 0)
                }

                // One bar per day; rest days and future days are dashed outlines.
                VStack(spacing: 8) {
                    HStack(alignment: .bottom, spacing: 10) {
                        ForEach(0..<7, id: \.self) { i in
                            Group {
                                if perDay[i] >= 1 {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Theme.accent)
                                        .frame(height: max(6, perDay[i] / maxBurn * 96))
                                } else {
                                    RoundedRectangle(cornerRadius: 6)
                                        .strokeBorder(Theme.dashed, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                                        .frame(height: 96)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel("\(DayKey.weekday(days[i])): \(perDay[i] >= 1 ? "\(perDay[i].kcalString) kcal" : "no workout")")
                        }
                    }
                    .frame(height: 96, alignment: .bottom)
                    HStack(spacing: 10) {
                        ForEach(0..<7, id: \.self) { i in
                            Text(DayKey.initial(days[i]))
                                .font(.manrope(12, keys[i] == today ? .heavy : .medium))
                                .foregroundStyle(keys[i] == today ? Theme.text : Theme.muted)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .card()
        }
        .buttonStyle(PressableStyle())
        .accessibilityHint("Shows the week's workouts by type")
        .sheet(isPresented: $showDetails) {
            WeekWorkoutsSheet(monday: monday)
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(28)
                .presentationBackground(Theme.background)
        }
        .task(id: monday) {
            try? await health.requestAuthorization()
            await health.loadWorkouts(from: monday, days: 7)
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
