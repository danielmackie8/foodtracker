import SwiftUI
import UIKit
import SwiftData

enum AppTab: Hashable {
    case home, day, week, profile
}

enum WeightRange: String, CaseIterable, Identifiable {
    case oneMonth = "1M", threeMonths = "3M"
    var id: String { rawValue }
    var days: Int { self == .oneMonth ? 30 : 90 }
    var label: String { self == .oneMonth ? "30 days" : "90 days" }
}

/// What the log sheet should open on.
struct LogRequest: Identifiable {
    let id = UUID()
    var slot: Slot
    var date: String
    var editing: Entry?
    /// Food estimated by Claude, opened from a sage:// link.
    var imported: ClaudeImport? = nil
    /// Open the barcode scanner straight away (from the widget's Scan button).
    var startScan: Bool = false
}

/// UI state plus persisted settings (goals, Health toggles).
@MainActor
@Observable
final class AppState {
    var tab: AppTab = .day
    var dayOffset = 0
    var weekOffset = 0
    var monthOffset = 0
    var weekMode: WeekMode = .week
    var logRequest: LogRequest?
    var toast: String?
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    // Persisted
    var goals: Goals {
        didSet {
            save(goals, "goals")
            if goals.kcal != oldValue.kcal && !applyingRemote { recordGoalChange(from: oldValue.kcal) }
        }
    }
    /// Calorie goal over time, so past days are judged against the target they had.
    var goalHistory: [GoalChange] { didSet { save(goalHistory, "goalHistory") } }
    /// Weight when the goal weight was first set (for the progress bar).
    var goalStartWeight: Double? { didSet { defaults.set(goalStartWeight, forKey: "goalStartWeight") } }
    var goalStartDate: String? { didSet { defaults.set(goalStartDate, forKey: "goalStartDate") } }
    @ObservationIgnored private var applyingRemote = false
    var healthEnabled: Bool { didSet { defaults.set(healthEnabled, forKey: "healthEnabled") } }
    var readWeight: Bool { didSet { defaults.set(readWeight, forKey: "readWeight") } }
    var readSteps: Bool { didSet { defaults.set(readSteps, forKey: "readSteps") } }
    var readWorkouts: Bool { didSet { defaults.set(readWorkouts, forKey: "readWorkouts") } }
    var stepGoal: Double { didSet { defaults.set(stepGoal, forKey: "stepGoal") } }
    var appearance: Appearance { didSet { defaults.set(appearance.rawValue, forKey: "appearance") } }
    /// Adaptive calorie target: weekly suggestions from real maintenance.
    var adaptiveOn: Bool { didSet { defaults.set(adaptiveOn, forKey: "adaptiveOn") } }
    /// Planned weight change, kg per week (0 = maintain).
    var adaptivePace: Double { didSet { defaults.set(adaptivePace, forKey: "adaptivePace") } }
    var goalWeight: Double? { didSet { defaults.set(goalWeight, forKey: "goalWeight") } }
    /// Monday (YYYY-MM-DD) of the last week whose check-in was answered.
    var lastCheckIn: String? { didSet { defaults.set(lastCheckIn, forKey: "lastCheckIn") } }
    /// Open Claude's copied estimate automatically when switching to Sage.
    var autoClaudePaste: Bool { didSet { defaults.set(autoClaudePaste, forKey: "autoClaudePaste") } }
    /// Calories burnt in workouts raise that day's calorie budget.
    var addWorkoutCalories: Bool { didSet { defaults.set(addWorkoutCalories, forKey: "addWorkoutCalories") } }
    var writeNutrition: Bool { didSet { defaults.set(writeNutrition, forKey: "writeNutrition") } }
    var lastSync: Date? { didSet { defaults.set(lastSync, forKey: "lastSync") } }
    var weightRange: WeightRange { didSet { defaults.set(weightRange.rawValue, forKey: "weightRange") } }

    @ObservationIgnored private let defaults = UserDefaults.standard

    init() {
        let d = UserDefaults.standard
        goals = (d.data(forKey: "goals")).flatMap { try? JSONDecoder().decode(Goals.self, from: $0) } ?? Goals()
        goalHistory = (d.data(forKey: "goalHistory")).flatMap { try? JSONDecoder().decode([GoalChange].self, from: $0) } ?? []
        goalStartWeight = d.object(forKey: "goalStartWeight") as? Double
        goalStartDate = d.string(forKey: "goalStartDate")
        healthEnabled = d.bool(forKey: "healthEnabled")
        readWeight = d.object(forKey: "readWeight") as? Bool ?? true
        readSteps = d.object(forKey: "readSteps") as? Bool ?? true
        readWorkouts = d.object(forKey: "readWorkouts") as? Bool ?? true
        stepGoal = d.object(forKey: "stepGoal") as? Double ?? 10_000
        appearance = Appearance(rawValue: d.string(forKey: "appearance") ?? "") ?? .system
        adaptiveOn = d.object(forKey: "adaptiveOn") as? Bool ?? true
        adaptivePace = d.object(forKey: "adaptivePace") as? Double ?? 0.5
        goalWeight = d.object(forKey: "goalWeight") as? Double
        lastCheckIn = d.string(forKey: "lastCheckIn")
        autoClaudePaste = d.object(forKey: "autoClaudePaste") as? Bool ?? true
        addWorkoutCalories = d.object(forKey: "addWorkoutCalories") as? Bool ?? true
        writeNutrition = d.object(forKey: "writeNutrition") as? Bool ?? true
        lastSync = d.object(forKey: "lastSync") as? Date
        weightRange = WeightRange(rawValue: d.string(forKey: "weightRange") ?? "") ?? .threeMonths
    }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }

    // MARK: Opening the app

    @ObservationIgnored var backgroundedAt: Date?

    /// Every time the app comes back from the background it opens on Day, showing today.
    func returnToTodayIfAway() {
        guard backgroundedAt != nil else { return }
        backgroundedAt = nil
        tab = .day
        dayOffset = 0
        weekOffset = 0
        monthOffset = 0
    }

    // MARK: Claude estimates on the clipboard

    /// When Sage comes to the front, opens the review screen if something new on the clipboard
    /// is a Claude estimate. Each copy is looked at once (tracked by the pasteboard's change count),
    /// and nothing is read while a log sheet is already open.
    func checkClipboardForClaude() {
        guard autoClaudePaste else { return }
        let board = UIPasteboard.general
        let change = board.changeCount
        let key = "lastPasteboardChange"
        guard let last = defaults.object(forKey: key) as? Int else {
            defaults.set(change, forKey: key) // first launch: ignore whatever was already copied
            return
        }
        guard change != last, logRequest == nil, board.hasStrings else { return }
        defaults.set(change, forKey: key)
        guard let text = board.string,
              text.contains("\"items\"") || text.contains("sage://"),
              let payload = ClaudeImport.parse(text) else { return }
        openImport(payload)
    }

    // MARK: Calorie budget

    var showsWorkouts: Bool { healthEnabled && readWorkouts }

    /// Workout calories added to a day's budget (0 when that's switched off).
    /// The calorie goal that applied on a given day (today's goal for today and later).
    func goalKcal(on day: String) -> Double {
        if day >= DayKey.todayKey { return goals.kcal }
        if let change = goalHistory.last(where: { $0.from <= day }) { return change.kcal }
        if let first = goalHistory.first { return first.before }
        return goals.kcal
    }

    private func recordGoalChange(from old: Double) {
        let today = DayKey.todayKey
        // Several changes on one day count as one, keeping the goal from before that day.
        let before = goalHistory.first(where: { $0.from == today })?.before ?? old
        goalHistory.removeAll { $0.from == today }
        goalHistory.append(GoalChange(from: today, kcal: goals.kcal, before: before))
    }

    func workoutBonus(on day: String, health: HealthKitManager) -> Double {
        showsWorkouts && addWorkoutCalories ? health.burnt(on: day) : 0
    }

    /// The calorie goal plus any workout bonus for that day.
    func budget(on day: String, health: HealthKitManager) -> Double {
        goalKcal(on: day) + workoutBonus(on: day, health: health)
    }

    // MARK: Settings sync

    /// Settings that follow you between devices (not device-specific ones like Health access).
    func settingsDocument() -> [String: Any] {
        var d: [String: Any] = [
            "goals": ["kcal": goals.kcal, "p": goals.p, "c": goals.c, "f": goals.f],
            "goalHistory": goalHistory.map { ["from": $0.from, "kcal": $0.kcal, "before": $0.before] },
            "stepGoal": stepGoal,
            "adaptiveOn": adaptiveOn, "adaptivePace": adaptivePace,
            "addWorkoutCalories": addWorkoutCalories,
            "readWeight": readWeight, "readSteps": readSteps, "readWorkouts": readWorkouts,
            "writeNutrition": writeNutrition,
            "appearance": appearance.rawValue, "autoClaudePaste": autoClaudePaste,
        ]
        d["goalWeight"] = goalWeight ?? NSNull()
        d["goalStartWeight"] = goalStartWeight ?? NSNull()
        d["goalStartDate"] = goalStartDate ?? NSNull()
        d["lastCheckIn"] = lastCheckIn ?? NSNull()
        return d
    }

    /// Applies settings pulled from the server.
    func apply(settings d: [String: Any]) {
        func num(_ k: String) -> Double? { (d[k] as? NSNumber)?.doubleValue }
        func flag(_ k: String) -> Bool? { (d[k] as? NSNumber)?.boolValue }
        applyingRemote = true
        defer { applyingRemote = false }
        if let h = d["goalHistory"] as? [[String: Any]] {
            goalHistory = h.compactMap { r in
                guard let from = r["from"] as? String, let kcal = (r["kcal"] as? NSNumber)?.doubleValue else { return nil }
                return GoalChange(from: from, kcal: kcal, before: (r["before"] as? NSNumber)?.doubleValue ?? kcal)
            }
        }
        if let g = d["goals"] as? [String: Any] {
            func gv(_ k: String) -> Double? { (g[k] as? NSNumber)?.doubleValue }
            goals = Goals(kcal: gv("kcal") ?? goals.kcal, p: gv("p") ?? goals.p, c: gv("c") ?? goals.c, f: gv("f") ?? goals.f)
        }
        if let v = num("stepGoal") { stepGoal = v }
        if let v = flag("adaptiveOn") { adaptiveOn = v }
        if let v = num("adaptivePace") { adaptivePace = v }
        if let v = flag("addWorkoutCalories") { addWorkoutCalories = v }
        if let v = flag("readWeight") { readWeight = v }
        if let v = flag("readSteps") { readSteps = v }
        if let v = flag("readWorkouts") { readWorkouts = v }
        if let v = flag("writeNutrition") { writeNutrition = v }
        if let v = d["appearance"] as? String, let a = Appearance(rawValue: v) { appearance = a }
        if let v = flag("autoClaudePaste") { autoClaudePaste = v }
        goalWeight = num("goalWeight")
        goalStartWeight = num("goalStartWeight")
        goalStartDate = d["goalStartDate"] as? String
        lastCheckIn = d["lastCheckIn"] as? String
    }

    // MARK: Navigation helpers

    var dayDate: Date { DayKey.add(dayOffset, to: DayKey.today) }

    /// Logging from the Day tab goes to the day on screen; everywhere else logs to today.
    var logDateKey: String { tab == .day ? DayKey.key(dayDate) : DayKey.todayKey }

    func openLog(slot: Slot? = nil, scan: Bool = false) {
        logRequest = LogRequest(slot: slot ?? .suggested(), date: logDateKey, startScan: scan)
    }

    /// Handles sage:// links from the widget (day, log, scan, claude) and from Claude (food to add).
    func handle(url: URL) {
        switch url.host?.lowercased() {
        case "day":
            tab = .day
            dayOffset = 0
        case "scan":
            tab = .day
            dayOffset = 0
            openLog(scan: true)
        case "claude":
            tab = .day
            dayOffset = 0
            if let text = UIPasteboard.general.string, let payload = ClaudeImport.parse(text) {
                openImport(payload)
            } else {
                openLog()
                showToast("Copy Claude's estimate first, then tap ✦")
            }
        default:
            if let payload = ClaudeImport.parse(url: url) {
                openImport(payload)
            } else {
                tab = .day
                dayOffset = 0
                openLog()
            }
        }
    }

    /// Opens the log sheet on Claude's estimate (from a sage:// link).
    func openImport(_ payload: ClaudeImport) {
        logRequest = LogRequest(slot: payload.slot ?? .suggested(), date: payload.date ?? logDateKey, imported: payload)
    }

    func openEdit(_ entry: Entry) {
        logRequest = LogRequest(slot: entry.slot, date: entry.date, editing: entry)
    }

    /// After adding from Week or Profile, show the Day the item went into.
    func didLog(on dateKey: String) {
        if tab == .week || tab == .profile {
            tab = .day
            dayOffset = DayKey.cal.dateComponents([.day], from: DayKey.today, to: DayKey.date(dateKey)).day ?? 0
        }
    }

    func showToast(_ message: String) {
        toastTask?.cancel()
        withAnimation(.spring(duration: 0.3)) { toast = message }
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { self?.toast = nil }
        }
    }

    var syncAgoLabel: String {
        guard let lastSync else { return "never" }
        let mins = Int(Date().timeIntervalSince(lastSync) / 60)
        if mins < 1 { return "just now" }
        if mins < 60 { return "\(mins) min ago" }
        if mins < 60 * 24 { return "\(mins / 60) h ago" }
        return DayKey.short(lastSync)
    }
}

/// Shared write path for entries, so Apple Health stays in step with the log.
@MainActor
enum EntryActions {
    static func add(_ entry: Entry, catalog: Catalog, context: ModelContext, app: AppState, health: HealthKitManager) {
        context.insert(entry)
        try? context.save()
        pushToHealth(entry, catalog: catalog, app: app, health: health)
    }

    static func update(_ entry: Entry, catalog: Catalog, context: ModelContext, app: AppState, health: HealthKitManager) {
        try? context.save()
        pushToHealth(entry, catalog: catalog, app: app, health: health)
    }

    /// Logs copies of `entries` on another day/slot (e.g. yesterday's lunch for today).
    static func copy(_ entries: [Entry], to date: String, slot: Slot, catalog: Catalog,
                     context: ModelContext, app: AppState, health: HealthKitManager) {
        let time = DayKey.time(.now)
        for e in entries {
            let copy = Entry(date: date, slot: slot, kind: e.kind, ref: e.ref, amount: e.amount, time: time,
                             quick: e.kind == .quick ? e.quickMacros : nil)
            copy.note = e.note
            add(copy, catalog: catalog, context: context, app: app, health: health)
        }
    }

    static func delete(_ entry: Entry, context: ModelContext, app: AppState, health: HealthKitManager) {
        let id = entry.id
        context.delete(entry)
        try? context.save()
        if app.healthEnabled && app.writeNutrition {
            Task { await health.delete(entryId: id) }
        }
    }

    private static func pushToHealth(_ entry: Entry, catalog: Catalog, app: AppState, health: HealthKitManager) {
        guard app.healthEnabled && app.writeNutrition else { return }
        let macros = catalog.macros(of: entry)
        let name = catalog.name(of: entry)
        let date = DayKey.date(entry.date, time: entry.time)
        let id = entry.id
        Task { await health.write(entryId: id, name: name, date: date, macros: macros) }
    }
}
