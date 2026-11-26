import SwiftUI
import SwiftData

@main
struct SageApp: App {
    let container: ModelContainer
    @State private var app = AppState()
    @State private var health = HealthKitManager()
    @State private var cloud: CloudSync

    init() {
        Manrope.register()
        _cloud = State(initialValue: CloudSync(auth: CloudAuth()))
        do {
            container = try ModelContainer(for: Food.self, Meal.self, Entry.self, WeightReading.self)
        } catch {
            fatalError("Could not open the food log: \(error)")
        }
        SeedData.ensureSeeded(container.mainContext)
        HistoryImport.runIfNeeded(container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(health)
                .environment(cloud)
        }
        .modelContainer(container)
    }
}
