import Foundation
import SwiftData
import SwiftUI
import UIKit

/// Builds export files: CSVs for spreadsheets and a full JSON backup.
@MainActor
enum DataExport {
    static func makeFiles(context: ModelContext) throws -> [URL] {
        let foods = (try? context.fetch(FetchDescriptor<Food>())) ?? []
        let meals = (try? context.fetch(FetchDescriptor<Meal>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? []
        let entries = (try? context.fetch(FetchDescriptor<Entry>(sortBy: [SortDescriptor(\.date), SortDescriptor(\.time)]))) ?? []
        let weights = (try? context.fetch(FetchDescriptor<WeightReading>(sortBy: [SortDescriptor(\.timestamp)]))) ?? []
        let catalog = Catalog(foods: foods, meals: meals)

        let stamp = DayKey.todayKey
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Sage export \(stamp)", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        func n(_ v: Double) -> String { String(format: "%.1f", v) }

        // Food log: one row per entry with its nutrition.
        var log = [["date", "meal", "time", "item", "amount", "kcal", "protein_g", "carbs_g", "fat_g", "type"]]
        for e in entries {
            let m = catalog.macros(of: e)
            log.append([e.date, e.slotRaw, e.time, catalog.name(of: e), catalog.amountLabel(of: e),
                        n(m.kcal), n(m.p), n(m.c), n(m.f), e.kindRaw])
        }
        // Daily totals.
        var days = [["date", "kcal", "protein_g", "carbs_g", "fat_g", "items"]]
        let ledger = Ledger(entries: entries, catalog: catalog)
        for key in Set(entries.map(\.date)).sorted() {
            let t = ledger.totals(key)
            days.append([key, n(t.macros.kcal), n(t.macros.p), n(t.macros.c), n(t.macros.f), String(t.count)])
        }
        var foodRows = [["name", "brand", "per", "unit", "kcal", "protein_g", "carbs_g", "fat_g", "source", "barcode"]]
        for f in foods.sorted(by: { $0.name < $1.name }) {
            foodRows.append([f.name, f.brand ?? "", f.per.clean, f.unit, n(f.kcal), n(f.p), n(f.c), n(f.f), f.sourceRaw, f.barcode ?? ""])
        }
        var mealRows = [["name", "favourite", "kcal", "protein_g", "carbs_g", "fat_g", "contents"]]
        for m in meals {
            let t = catalog.macros(of: m)
            mealRows.append([m.name, m.favourite ? "yes" : "no", n(t.kcal), n(t.p), n(t.c), n(t.f), m.desc])
        }
        var weightRows = [["date", "time", "kg"]]
        for w in weights { weightRows.append([w.date, w.time, String(format: "%.2f", w.kg)]) }

        let files: [(String, [[String]])] = [
            ("Food log.csv", log), ("Daily totals.csv", days), ("Foods.csv", foodRows),
            ("Meals.csv", mealRows), ("Weight.csv", weightRows),
        ]
        var urls: [URL] = []
        for (name, rows) in files {
            let url = dir.appendingPathComponent(name)
            try csv(rows).write(to: url, atomically: true, encoding: .utf8)
            urls.append(url)
        }

        // Full backup of everything the app stores.
        let backup: [String: Any] = [
            "app": "Sage", "exported": ISO8601DateFormatter().string(from: .now),
            "foods": foods.map { CloudSync.row($0) },
            "meals": meals.map { CloudSync.row($0) },
            "entries": entries.map { CloudSync.row($0) },
            "weights": weights.map { ["date": $0.date, "time": $0.time, "kg": $0.kg] as [String: Any] },
        ]
        let json = try JSONSerialization.data(withJSONObject: backup, options: [.prettyPrinted, .sortedKeys])
        let backupURL = dir.appendingPathComponent("Sage backup \(stamp).json")
        try json.write(to: backupURL)
        urls.append(backupURL)
        return urls
    }

    private static func csv(_ rows: [[String]]) -> String {
        rows.map { row in
            row.map { field in
                field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" })
                    ? "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
                    : field
            }.joined(separator: ",")
        }.joined(separator: "\n") + "\n"
    }
}

/// The iOS share sheet (AirDrop, Files, Mail…).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
