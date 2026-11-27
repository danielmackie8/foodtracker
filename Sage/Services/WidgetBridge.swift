import Foundation
import SwiftData
import WidgetKit

/// Keeps the home-screen widget in step with the app: writes today's totals and budget
/// to the shared App Group container and asks WidgetKit to redraw when they change.
@MainActor
enum WidgetBridge {
    static func update(context: ModelContext, app: AppState, health: HealthKitManager) {
        let key = DayKey.todayKey
        let entries = (try? context.fetch(FetchDescriptor<Entry>(predicate: #Predicate<Entry> { $0.date == key }))) ?? []
        let catalog = Catalog(foods: (try? context.fetch(FetchDescriptor<Food>())) ?? [],
                              meals: (try? context.fetch(FetchDescriptor<Meal>())) ?? [])
        let total = entries.reduce(into: Macros()) { $0 += catalog.macros(of: $1) }
        let snap = WidgetSnapshot(date: key, eaten: total.kcal, p: total.p, c: total.c, f: total.f,
                                  goalKcal: app.goals.kcal, goalP: app.goals.p, goalC: app.goals.c, goalF: app.goals.f,
                                  bonus: app.workoutBonus(on: key, health: health))
        guard snap != WidgetSnapshot.load() else { return }
        snap.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
