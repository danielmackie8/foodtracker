import SwiftUI
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
}

/// UI state plus persisted settings (goals, Health toggles).
@MainActor
@Observable
final class AppState {
    var tab: AppTab = .home
    var dayOffset = 0
    var weekOffset = 0
    var logRequest: LogRequest?
    var toast: String?
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    // Persisted
    var goals: Goals { didSet { save(goals, "goals") } }
    var healthEnabled: Bool { didSet { defaults.set(healthEnabled, forKey: "healthEnabled") } }
    var readWeight: Bool { didSet { defaults.set(readWeight, forKey: "readWeight") } }
    var readSteps: Bool { didSet { defaults.set(readSteps, forKey: "readSteps") } }
    var readWorkouts: Bool { didSet { defaults.set(readWorkouts, forKey: "readWorkouts") } }
    /// Calories burnt in workouts raise that day's calorie budget.
    var addWorkoutCalories: Bool { didSet { defaults.set(addWorkoutCalories, forKey: "addWorkoutCalories") } }
    var writeNutrition: Bool { didSet { defaults.set(writeNutrition, forKey: "writeNutrition") } }
    var lastSync: Date? { didSet { defaults.set(lastSync, forKey: "lastSync") } }
    var weightRange: WeightRange { didSet { defaults.set(weightRange.rawValue, forKey: "weightRange") } }

    @ObservationIgnored private let defaults = UserDefaults.standard

    init() {
        let d = UserDefaults.standard
        goals = (d.data(forKey: "goals")).flatMap { try? JSONDecoder().decode(Goals.self, from: $0) } ?? Goals()
        healthEnabled = d.bool(forKey: "healthEnabled")
        readWeight = d.object(forKey: "readWeight") as? Bool ?? true
        readSteps = d.object(forKey: "readSteps") as? Bool ?? true
        readWorkouts = d.object(forKey: "readWorkouts") as? Bool ?? true
        addWorkoutCalories = d.object(forKey: "addWorkoutCalories") as? Bool ?? true
        writeNutrition = d.object(forKey: "writeNutrition") as? Bool ?? true
        lastSync = d.object(forKey: "lastSync") as? Date
        weightRange = WeightRange(rawValue: d.string(forKey: "weightRange") ?? "") ?? .threeMonths
    }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }

    // MARK: Calorie budget

    var showsWorkouts: Bool { healthEnabled && readWorkouts }

    /// Workout calories added to a day's budget (0 when that's switched off).
    func workoutBonus(on day: String, health: HealthKitManager) -> Double {
        showsWorkouts && addWorkoutCalories ? health.burnt(on: day) : 0
    }

    /// The calorie goal plus any workout bonus for that day.
    func budget(on day: String, health: HealthKitManager) -> Double {
        goals.kcal + workoutBonus(on: day, health: health)
    }

    // MARK: Navigation helpers

    var dayDate: Date { DayKey.add(dayOffset, to: DayKey.today) }

    /// Logging from the Day tab goes to the day on screen; everywhere else logs to today.
    var logDateKey: String { tab == .day ? DayKey.key(dayDate) : DayKey.todayKey }

    func openLog(slot: Slot? = nil) {
        logRequest = LogRequest(slot: slot ?? .suggested(), date: logDateKey)
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
