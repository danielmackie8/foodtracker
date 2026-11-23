import Foundation
import SwiftData

/// One-time import of food logged in the previous app (11–23 Nov 2026).
///
/// Rows come from `history-import.json`: [date, slot, name, quantity note, kcal, protein, carbs, fat],
/// already totalled for the quantity eaten. Each becomes a quick-add entry. They are not written
/// to Apple Health, because the old app may already have put them there.
enum HistoryImport {
    private static let doneKey = "historyImport.2026-11-23.done"

    @MainActor
    static func runIfNeeded(_ context: ModelContext) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey),
              let url = Bundle.main.url(forResource: "history-import", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[Any]] else { return }

        func num(_ v: Any) -> Double { (v as? NSNumber)?.doubleValue ?? 0 }
        let baseTimes: [Slot: (Int, Int)] = [.breakfast: (8, 0), .lunch: (12, 30), .snack: (15, 30), .dinner: (19, 0)]
        var countPerSlot: [String: Int] = [:]

        for r in rows where r.count >= 8 {
            guard let date = r[0] as? String, let slotName = r[1] as? String, let name = r[2] as? String else { continue }
            let slot = Slot(rawValue: slotName) ?? .snack
            // Spread items a minute apart so they keep the export's order within each meal.
            let key = "\(date)|\(slot.rawValue)"
            let n = countPerSlot[key, default: 0]
            countPerSlot[key] = n + 1
            let (h, m) = baseTimes[slot] ?? (12, 0)
            let time = String(format: "%02d:%02d", h, m + n)

            let entry = Entry(date: date, slot: slot, kind: .quick, ref: name, amount: 1, time: time,
                              quick: Macros(kcal: num(r[4]), p: num(r[5]), c: num(r[6]), f: num(r[7])))
            entry.note = r[3] as? String
            context.insert(entry)
        }
        do {
            try context.save()
            defaults.set(true, forKey: doneKey)
        } catch {
            context.rollback()
        }
    }
}
