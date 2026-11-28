import Foundation

/// Works out real maintenance calories from what was eaten and how weight actually changed.
///
/// Method (energy balance over a window, normally the last 28 complete days):
///  - average intake over days that were properly logged (≥ 800 kcal);
///  - weight change per day = the least-squares slope through the weigh-ins in the window
///    (robust to day-to-day water swings);
///  - 1 kg of body weight ≈ 7,700 kcal, so maintenance = intake − slope × 7,700;
///  - the result already includes your usual workouts, so the target is one fixed daily number.
///    Only unusually big workout days (above your average) add extra, so nothing is counted twice
///    and Apple Watch's generous workout estimates aren't eaten back.
struct AdaptiveEstimate {
    enum Confidence { case learning, rough, good }

    /// Lowest target Sage will ever suggest. 1,200 is a common floor for women; for men
    /// 1,500 is the usual minimum, and Sage doesn't know which applies, so it uses the safer one.
    static let minimumTarget = 1500.0
    /// Never suggest eating more than 25% below maintenance.
    static let maxDeficitShare = 0.25
    /// Weight change faster than this over the window is treated as water/noise and capped.
    static let maxKgPerWeek = 1.0
    /// Maintenance outside this range is implausible for an adult: don't suggest.
    static let plausible = 1600.0...4500.0

    var confidence: Confidence
    /// Maintenance including your usual workouts (kcal/day), rounded to 10. Nil while learning.
    var maintenance: Double?
    var avgIntake: Double
    var avgWorkout: Double
    /// Trend weight change, kg per week (negative = losing).
    var kgPerWeek: Double
    /// Smoothed current weight.
    var trendWeight: Double?
    var loggedDays: Int
    var weighIns: Int
    var windowDays: Int
    /// Maintenance as it was at the end of each of the last few weeks (oldest first).
    var history: [Double]
    /// The estimate came out implausible (usually unlogged days or noisy weigh-ins).
    var unusual = false

    static let kcalPerKg = 7700.0
    static let minDays = 14
    static let minWeighIns = 5

    var isReady: Bool { confidence != .learning }

    /// Daily target for a pace in kg/week (0 = maintain). Never below 1,500 kcal and never
    /// more than 25% under maintenance.
    func target(pace: Double) -> Double? {
        guard let maintenance else { return nil }
        let wanted = maintenance - pace * Self.kcalPerKg / 7
        let floor = max(Self.minimumTarget, maintenance * (1 - Self.maxDeficitShare))
        return (max(floor, wanted) / 10).rounded() * 10
    }

    /// True when the safety limits stop `pace` from being reached.
    func isLimited(pace: Double) -> Bool {
        guard let maintenance, let t = target(pace: pace) else { return false }
        return t > maintenance - pace * Self.kcalPerKg / 7 + 5
    }

    /// The actual weekly loss the limited target gives.
    func effectivePace(pace: Double) -> Double {
        guard let maintenance, let t = target(pace: pace) else { return pace }
        return max(0, (maintenance - t) * 7 / Self.kcalPerKg)
    }

    /// When the trend reaches `goal` at `pace` kg/week, if it's below the current trend.
    func goalDate(goal: Double?, pace: Double, from today: Date = DayKey.today) -> Date? {
        let real = effectivePace(pace: pace)
        guard let goal, let trendWeight, real > 0.01, trendWeight > goal else { return nil }
        let weeks = (trendWeight - goal) / real
        return DayKey.add(Int((weeks * 7).rounded()), to: today)
    }

    // MARK: Calculation

    /// - Parameters:
    ///   - intakeByDay: kcal eaten per day (YYYY-MM-DD).
    ///   - weights: weigh-ins (any order).
    ///   - workoutByDay: workout kcal per day (0 if unknown or not counted).
    static func compute(intakeByDay: [String: Double], weights: [(date: Date, kg: Double)],
                        workoutByDay: (String) -> Double, today: Date = DayKey.today) -> AdaptiveEstimate {
        let sortedWeights = weights.sorted { $0.date < $1.date }
        let trend = smoothedTrend(sortedWeights)
        var est = window(end: today, intakeByDay: intakeByDay, weights: sortedWeights, workoutByDay: workoutByDay)
        est.trendWeight = trend
        // History: the estimate at the end of each of the previous 5 weeks, then now.
        var history: [Double] = []
        for back in stride(from: 5, through: 1, by: -1) {
            let w = window(end: DayKey.add(-7 * back, to: today), intakeByDay: intakeByDay,
                           weights: sortedWeights, workoutByDay: workoutByDay)
            if let m = w.maintenance { history.append(m) }
        }
        if let m = est.maintenance { history.append(m) }
        est.history = history
        return est
    }

    /// Estimate from the 28 complete days before `end` (or fewer, from the first logged day).
    private static func window(end: Date, intakeByDay: [String: Double], weights: [(date: Date, kg: Double)],
                               workoutByDay: (String) -> Double) -> AdaptiveEstimate {
        let firstLogged = intakeByDay.filter { $0.value >= 800 }.keys.min().map(DayKey.date)
        var start = DayKey.add(-28, to: end)
        if let firstLogged, firstLogged > start { start = firstLogged }
        let days = max(0, DayKey.cal.dateComponents([.day], from: start, to: end).day ?? 0)

        var intake: [Double] = []
        var workouts: [Double] = []
        for i in 0..<days {
            let key = DayKey.key(DayKey.add(i, to: start))
            if let kcal = intakeByDay[key], kcal >= 800 {
                intake.append(kcal)
                workouts.append(workoutByDay(key))
            }
        }
        let inWindow = weights.filter { $0.date >= start && $0.date < end }
        let cap = maxKgPerWeek / 7
        let slopePerDay = min(cap, max(-cap, regressionSlope(inWindow) ?? 0))
        let avgIntake = intake.isEmpty ? 0 : intake.reduce(0, +) / Double(intake.count)
        let avgWorkout = workouts.isEmpty ? 0 : workouts.reduce(0, +) / Double(workouts.count)

        let spanDays = inWindow.count > 1
            ? (inWindow.last!.date.timeIntervalSince(inWindow.first!.date) / 86400) : 0
        // With under three weeks of food logged, ask for more weigh-ins so a couple of
        // heavy or light readings can't swing the slope.
        let neededWeighIns = intake.count >= 21 ? minWeighIns : 8
        let enough = intake.count >= minDays && inWindow.count >= neededWeighIns && spanDays >= 10
        let confidence: Confidence = !enough ? .learning
            : (intake.count >= 21 && inWindow.count >= 10 ? .good : .rough)

        var maintenance: Double?
        var unusual = false
        var conf = confidence
        if enough {
            let total = avgIntake - slopePerDay * kcalPerKg
            let base = (total / 10).rounded() * 10
            if plausible.contains(base) {
                maintenance = base
            } else {
                unusual = true
                conf = .learning
            }
        }
        return AdaptiveEstimate(confidence: conf, maintenance: maintenance, avgIntake: avgIntake,
                                avgWorkout: avgWorkout, kgPerWeek: slopePerDay * 7, trendWeight: nil,
                                loggedDays: intake.count, weighIns: inWindow.count, windowDays: days,
                                history: [], unusual: unusual)
    }

    /// Least-squares slope (kg per day) through the weigh-ins.
    static func regressionSlope(_ points: [(date: Date, kg: Double)]) -> Double? {
        guard points.count >= 2, let t0 = points.first?.date else { return nil }
        let xs = points.map { $0.date.timeIntervalSince(t0) / 86400 }
        let ys = points.map { $0.kg }
        let n = Double(points.count)
        let mx = xs.reduce(0, +) / n, my = ys.reduce(0, +) / n
        let sxx = zip(xs, xs).map { ($0 - mx) * ($1 - mx) }.reduce(0, +)
        guard sxx > 0 else { return nil }
        let sxy = zip(xs, ys).map { ($0 - mx) * ($1 - my) }.reduce(0, +)
        return sxy / sxx
    }

    /// Exponentially smoothed weight (≈ 10-day memory), evaluated at the last reading.
    static func smoothedTrend(_ points: [(date: Date, kg: Double)]) -> Double? {
        trendSeries(points).last?.kg
    }

    /// Smoothed value at each reading, for charts.
    static func trendSeries(_ points: [(date: Date, kg: Double)]) -> [(date: Date, kg: Double)] {
        guard var trend = points.first?.kg, var last = points.first?.date else { return [] }
        var out: [(date: Date, kg: Double)] = []
        for p in points {
            let gapDays = max(1, p.date.timeIntervalSince(last) / 86400)
            let alpha = 1 - pow(0.9, gapDays)
            trend += alpha * (p.kg - trend)
            last = p.date
            out.append((date: p.date, kg: trend))
        }
        return out
    }
}

extension Goals {
    /// New calorie goal: protein stays, carbs and fat keep their current share of the rest.
    func rebalanced(kcal newKcal: Double) -> Goals {
        var g = self
        g.kcal = newKcal
        let carbKcal = c * 4, fatKcal = f * 9
        let share = carbKcal + fatKcal > 0 ? carbKcal / (carbKcal + fatKcal) : 0.55
        let rest = max(0, newKcal - p * 4)
        g.c = max(0, (rest * share / 4 / 5).rounded() * 5)
        g.f = max(0, (rest * (1 - share) / 9 / 5).rounded() * 5)
        return g
    }
}
