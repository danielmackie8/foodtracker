import Foundation
import HealthKit
import SwiftData

/// Reads body mass from Apple Health and writes logged nutrition back.
///
/// Each logged entry is written as four quantity samples (energy, protein, carbs, fat)
/// tagged with a sync identifier derived from the entry id, so editing an entry replaces
/// its samples and deleting it removes them.
@MainActor
@Observable
final class HealthKitManager {
    private let store = HKHealthStore()
    var isSyncing = false
    var lastError: String?

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private let bodyMass = HKQuantityType(.bodyMass)
    private let stepCount = HKQuantityType(.stepCount)
    private let activeEnergy = HKQuantityType(.activeEnergyBurned)
    private let distanceTypes = [HKQuantityType(.distanceWalkingRunning), HKQuantityType(.distanceCycling)]

    /// Workouts per day (YYYY-MM-DD), filled by `loadWorkouts(on:)`.
    var workoutsByDay: [String: [WorkoutSummary]] = [:]
    private let nutrition: [(HKQuantityType, String, KeyPath<Macros, Double>, HKUnit)] = [
        (HKQuantityType(.dietaryEnergyConsumed), "kcal", \.kcal, .kilocalorie()),
        (HKQuantityType(.dietaryProtein), "p", \.p, .gram()),
        (HKQuantityType(.dietaryCarbohydrates), "c", \.c, .gram()),
        (HKQuantityType(.dietaryFatTotal), "f", \.f, .gram()),
    ]

    /// Shows the system Health permission sheet (only the first time for each type).
    func requestAuthorization() async throws {
        guard isAvailable else { return }
        let share = Set(nutrition.map { $0.0 as HKSampleType })
        var read: Set<HKObjectType> = [bodyMass, stepCount, activeEnergy, HKObjectType.workoutType()]
        distanceTypes.forEach { read.insert($0) }
        try await store.requestAuthorization(toShare: share, read: read)
    }

    // MARK: Weight

    /// Pulls body-mass samples for the past year into the local store.
    func syncWeights(into context: ModelContext, days: Int = 365) async {
        guard isAvailable, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let start = DayKey.add(-days, to: DayKey.today)
            let descriptor = HKSampleQueryDescriptor(
                predicates: [.quantitySample(type: bodyMass, predicate: HKQuery.predicateForSamples(withStart: start, end: nil))],
                sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
            )
            let samples = try await descriptor.result(for: store)

            let existing = (try? context.fetch(FetchDescriptor<WeightReading>())) ?? []
            var byId = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            var seen = Set<String>()
            for s in samples {
                let id = s.uuid.uuidString
                seen.insert(id)
                let kg = s.quantity.doubleValue(for: .gramUnit(with: .kilo))
                if let r = byId[id] {
                    r.kg = kg
                } else {
                    let r = WeightReading(id: id, timestamp: s.startDate, kg: kg)
                    context.insert(r)
                    byId[id] = r
                }
            }
            // Drop readings deleted in Health (within the synced window).
            for r in existing where r.timestamp >= start && !seen.contains(r.id) {
                context.delete(r)
            }
            try context.save()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: Workouts

    /// Total calories burnt in workouts on a day, from the last load (0 if not loaded).
    func burnt(on day: String) -> Double {
        workoutsByDay[day]?.reduce(0) { $0 + $1.kcal } ?? 0
    }

    /// Reads the workouts that started on `day` (YYYY-MM-DD).
    func loadWorkouts(on day: String) async {
        await loadWorkouts(from: DayKey.date(day), days: 1)
    }

    /// Reads workouts for `days` days starting at `start` in one query, filling every day
    /// in the range (an empty list means no workouts that day).
    func loadWorkouts(from start: Date, days: Int) async {
        guard isAvailable, days > 0 else { return }
        let first = DayKey.cal.startOfDay(for: start)
        let end = DayKey.add(days, to: first)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(HKQuery.predicateForSamples(withStart: first, end: end, options: .strictStartDate))],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
        )
        guard let workouts = try? await descriptor.result(for: store) else { return }
        var byDay: [String: [WorkoutSummary]] = [:]
        for i in 0..<days { byDay[DayKey.key(DayKey.add(i, to: first))] = [] }
        for w in workouts {
            let kcal = w.statistics(for: activeEnergy)?.sumQuantity()?.doubleValue(for: .kilocalorie())
                ?? w.totalEnergyBurned?.doubleValue(for: .kilocalorie())
                ?? 0
            let km = distanceTypes.lazy
                .compactMap { w.statistics(for: $0)?.sumQuantity()?.doubleValue(for: .meterUnit(with: .kilo)) }
                .first
            let (name, icon) = WorkoutSummary.describe(w.workoutActivityType,
                                                       indoor: w.metadata?[HKMetadataKeyIndoorWorkout] as? Bool)
            byDay[DayKey.key(w.startDate), default: []].append(
                WorkoutSummary(id: w.uuid, name: name, icon: icon, start: w.startDate,
                               duration: w.duration, kcal: kcal, distanceKm: km))
        }
        workoutsByDay.merge(byDay) { _, new in new }
    }

    // MARK: Steps

    /// Total steps per day (keyed YYYY-MM-DD) from `start` up to `end`, as Health's own daily totals
    /// (deduplicated across iPhone and Apple Watch). Days with no steps are left out.
    func dailySteps(from start: Date, to end: Date) async -> [String: Double] {
        guard isAvailable, end > start else { return [:] }
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: stepCount, predicate: HKQuery.predicateForSamples(withStart: start, end: end)),
            options: .cumulativeSum,
            anchorDate: DayKey.cal.startOfDay(for: start),
            intervalComponents: DateComponents(day: 1)
        )
        do {
            let collection = try await descriptor.result(for: store)
            var out: [String: Double] = [:]
            collection.enumerateStatistics(from: start, to: end) { stats, _ in
                if let sum = stats.sumQuantity()?.doubleValue(for: .count()), sum > 0 {
                    out[DayKey.key(stats.startDate)] = sum
                }
            }
            return out
        } catch {
            return [:]
        }
    }

    // MARK: Nutrition

    func write(entryId: UUID, name: String, date: Date, macros: Macros) async {
        guard isAvailable else { return }
        let version = NSNumber(value: Int(Date().timeIntervalSince1970 * 1000))
        var samples: [HKQuantitySample] = []
        for (type, key, path, unit) in nutrition {
            guard store.authorizationStatus(for: type) == .sharingAuthorized else { continue }
            let value = max(0, macros[keyPath: path])
            let sample = HKQuantitySample(
                type: type,
                quantity: HKQuantity(unit: unit, doubleValue: value),
                start: date, end: date,
                metadata: [
                    HKMetadataKeySyncIdentifier: "\(entryId.uuidString)-\(key)",
                    HKMetadataKeySyncVersion: version,
                    HKMetadataKeyFoodType: name,
                ]
            )
            samples.append(sample)
        }
        guard !samples.isEmpty else { return }
        do { try await store.save(samples) } catch { lastError = error.localizedDescription }
    }

    func delete(entryId: UUID) async {
        guard isAvailable else { return }
        for (type, key, _, _) in nutrition where store.authorizationStatus(for: type) == .sharingAuthorized {
            let predicate = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier,
                                                        allowedValues: ["\(entryId.uuidString)-\(key)"])
            _ = try? await store.deleteObjects(of: type, predicate: predicate)
        }
    }
}

// MARK: - App-level actions

extension HealthKitManager {
    /// Shows the Health permission sheet, then pulls weight in.
    func connect(app: AppState, context: ModelContext) async {
        guard isAvailable else {
            app.showToast("Apple Health isn't available on this device")
            return
        }
        do {
            try await requestAuthorization()
            app.healthEnabled = true
            app.showToast("Apple Health connected")
            await sync(app: app, context: context, announce: false)
        } catch {
            app.showToast("Couldn't connect to Apple Health")
        }
    }

    func sync(app: AppState, context: ModelContext, announce: Bool = true) async {
        guard app.healthEnabled else { return }
        await syncWeights(into: context)
        if lastError == nil {
            app.lastSync = .now
            if announce { app.showToast("Synced with Apple Health") }
        } else if announce {
            app.showToast("Sync failed — check Health permissions")
        }
    }
}
