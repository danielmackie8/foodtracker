import Foundation

/// Builds the adaptive estimate from the app's data, and handles the weekly check-in.
@MainActor
enum AdaptiveData {
    static func estimate(entries: [Entry], catalog: Catalog, weights: [WeightReading],
                         app: AppState, health: HealthKitManager) -> AdaptiveEstimate {
        let ledger = Ledger(entries: entries, catalog: catalog)
        var intake: [String: Double] = [:]
        for key in ledger.byDate.keys { intake[key] = ledger.totals(key).macros.kcal }
        // Workouts only come off maintenance when they're added back to the daily budget.
        let counted = app.showsWorkouts && app.addWorkoutCalories
        return AdaptiveEstimate.compute(
            intakeByDay: intake,
            weights: weights.map { (date: $0.timestamp, kg: $0.kg) },
            workoutByDay: { counted ? health.burnt(on: $0) : 0 })
    }

    /// Workouts for the last 6 weeks, so they can be taken out of the estimate.
    static func loadWorkouts(app: AppState, health: HealthKitManager) async {
        guard app.showsWorkouts && app.addWorkoutCalories else { return }
        await health.loadWorkouts(from: DayKey.add(-42, to: DayKey.today), days: 43)
    }

    static var thisMonday: String { DayKey.key(DayKey.monday(of: .now)) }

    /// Shown on Day (today) on Mondays, or as soon as the first estimate is ready.
    static func checkInDue(_ est: AdaptiveEstimate, app: AppState) -> Bool {
        guard app.adaptiveOn, est.isReady, est.target(pace: app.adaptivePace) != nil else { return false }
        guard app.lastCheckIn != thisMonday else { return false }
        let isMonday = DayKey.cal.component(.weekday, from: .now) == 2
        return isMonday || app.lastCheckIn == nil
    }

    static func accept(_ target: Double, app: AppState) {
        app.goals = app.goals.rebalanced(kcal: target)
        app.lastCheckIn = thisMonday
        app.showToast("Target set to \(target.kcalString) kcal")
    }
}
