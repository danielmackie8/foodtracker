import SwiftUI

/// Home card: calories burnt in today's workouts. Tapping it opens the breakdown.
struct WorkoutsCard: View {
    @Environment(AppState.self) private var app
    @Environment(HealthKitManager.self) private var health
    @State private var showDetails = false

    private let day = DayKey.todayKey

    var body: some View {
        let workouts = health.workoutsByDay[day] ?? []
        let total = health.burnt(on: day)
        let duration = workouts.reduce(0) { $0 + $1.duration }

        Button { showDetails = true } label: {
            VStack(alignment: .leading, spacing: 12) {
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
                    if workouts.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("No workouts yet today").font(.manrope(16, .bold))
                            Text("Workouts from Apple Health appear here")
                                .font(.manrope(13, .medium)).foregroundStyle(Theme.muted)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            (Text(total.kcalString) + Text(" kcal").font(.manrope(15, .semibold)).foregroundColor(Theme.muted))
                                .bigNumber(30)
                            Text("burnt in workouts today")
                                .font(.manrope(13, .medium)).foregroundStyle(Theme.muted)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .card()
        }
        .buttonStyle(PressableStyle())
        .accessibilityHint("Shows today's workouts")
        .sheet(isPresented: $showDetails) {
            WorkoutsSheet(day: day)
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(28)
                .presentationBackground(Theme.background)
        }
        .task {
            // Asks for workout access once (existing users), then loads today's workouts.
            try? await health.requestAuthorization()
            await health.loadWorkouts(on: day)
        }
    }
}

/// Pop-up breakdown: total burnt and each workout.
struct WorkoutsSheet: View {
    let day: String
    @Environment(AppState.self) private var app
    @Environment(HealthKitManager.self) private var health
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let workouts = health.workoutsByDay[day] ?? []
        let total = health.burnt(on: day)
        let duration = workouts.reduce(0) { $0 + $1.duration }
        let isToday = day == DayKey.todayKey

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Workouts").font(.manrope(24, .heavy))
                        Text("\(isToday ? "Today" : DayKey.short(DayKey.date(day))) · from Apple Health")
                            .font(.manrope(13, .medium)).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Button("Done") { dismiss() }
                        .font(.manrope(16, .bold))
                        .foregroundStyle(Theme.accent)
                        .frame(minHeight: Theme.minTouch)
                }

                VStack(alignment: .leading, spacing: 0) {
                    (Text(total.kcalString) + Text(" kcal burnt").font(.manrope(15, .semibold)).foregroundColor(Theme.muted))
                        .bigNumber(36)
                    Text(workouts.isEmpty ? "No workouts logged in Apple Health"
                                          : "\(workouts.count) workout\(workouts.count == 1 ? "" : "s") · \(WorkoutSummary.durationLabel(duration))")
                        .font(.manrope(13, .medium)).foregroundStyle(Theme.muted)
                        .padding(.bottom, workouts.isEmpty ? 0 : 12)

                    ForEach(Array(workouts.enumerated()), id: \.element.id) { i, w in
                        Divider().overlay(Theme.border)
                        HStack(spacing: 12) {
                            Image(systemName: w.icon)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                                .frame(width: 36, height: 36)
                                .background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(w.name).font(.manrope(15, .semibold))
                                Text(w.detail).font(.manrope(12, .medium)).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            (Text(w.kcal.kcalString).font(.manrope(15, .bold))
                             + Text(" kcal").font(.manrope(13, .medium)).foregroundColor(Theme.muted))
                                .monospacedDigit()
                        }
                        .frame(minHeight: 58)
                        .accessibilityElement(children: .combine)
                    }
                }
                .card()

                Text(budgetNote(total: total))
                    .font(.manrope(13, .medium)).foregroundStyle(Theme.muted)
                    .padding(.horizontal, 4)
            }
            .padding(Theme.pagePadding)
        }
        .task { await health.loadWorkouts(on: day) }
    }

    private func budgetNote(total: Double) -> String {
        guard total >= 1 else { return "Calories burnt in workouts are added to that day's calorie budget." }
        if app.addWorkoutCalories {
            return "Added to \(day == DayKey.todayKey ? "today's" : "that day's") budget: \(app.goals.kcal.kcalString) + \(total.kcalString) = \((app.goals.kcal + total).kcalString) kcal. You can turn this off in Profile."
        }
        return "Not added to your budget. You can turn this on in Profile."
    }
}
