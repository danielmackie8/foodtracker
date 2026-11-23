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
        let read: Set<HKObjectType> = [bodyMass]
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
