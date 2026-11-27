import AppIntents
import WidgetKit

/// The + button on the "Log a favourite" widget. Runs without opening the app:
/// it queues the meal for the app to log, and updates the widget's totals straight away.
struct LogFavouriteIntent: AppIntent {
    static var title: LocalizedStringResource = "Log a favourite meal"
    static var isDiscoverable: Bool = false

    @Parameter(title: "Meal")
    var mealId: String

    init() {}

    init(mealId: String) {
        self.mealId = mealId
    }

    func perform() async throws -> some IntentResult {
        let now = Date()
        let today = WidgetSnapshot.dayKey(now)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        PendingLogs.append(PendingLog(id: UUID(), mealId: mealId, date: today,
                                      slot: WidgetSlot.suggested(now), time: f.string(from: now)))

        if var snap = WidgetSnapshot.load()?.forDay(today),
           let meal = snap.favourites.first(where: { $0.id == mealId }) {
            snap.eaten += meal.kcal
            snap.p += meal.p
            snap.c += meal.c
            snap.f += meal.f
            snap.lastLogged = meal.name
            snap.updated = now
            snap.save()
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
