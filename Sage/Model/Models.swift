import Foundation
import SwiftData

enum FoodSource: String, Codable {
    case builtin, custom, off
}

enum Slot: String, CaseIterable, Codable, Identifiable {
    case breakfast = "Breakfast", lunch = "Lunch", snack = "Snack", dinner = "Dinner"
    var id: String { rawValue }

    /// Suggested slot for the current time of day (same cut-offs as the prototype).
    static func suggested(for date: Date = .now) -> Slot {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        let h = Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
        if h < 10.5 { return .breakfast }
        if h < 15 { return .lunch }
        if h < 17.5 { return .snack }
        return .dinner
    }
}

enum EntryKind: String, Codable {
    case food, meal, quick
}

/// A single food. Nutrition is given per `per` units of `unit`
/// (e.g. per 100 g, or per 1 slice).
@Model
final class Food {
    @Attribute(.unique) var id: String
    var name: String
    var brand: String?
    var pack: String?
    /// g, ml, slice, egg, scoop, serving, banana, tbsp…
    var unit: String
    var per: Double
    var step: Double
    var def: Double
    var kcal: Double
    var p: Double
    var c: Double
    var f: Double
    /// Logged as dry weight (pasta, rice, oats).
    var dry: Bool
    var sourceRaw: String
    var barcode: String?
    var servingGrams: Double?
    var createdAt: Date

    init(id: String, name: String, brand: String? = nil, pack: String? = nil, unit: String, per: Double, step: Double, def: Double,
         kcal: Double, p: Double, c: Double, f: Double, dry: Bool = false, source: FoodSource,
         barcode: String? = nil, servingGrams: Double? = nil) {
        self.id = id
        self.name = name
        self.brand = brand
        self.pack = pack
        self.unit = unit
        self.per = per
        self.step = step
        self.def = def
        self.kcal = kcal
        self.p = p
        self.c = c
        self.f = f
        self.dry = dry
        self.sourceRaw = source.rawValue
        self.barcode = barcode
        self.servingGrams = servingGrams
        self.createdAt = .now
    }

    var source: FoodSource { FoodSource(rawValue: sourceRaw) ?? .custom }
    var isMetric: Bool { unit == "g" || unit == "ml" }

    func macros(for amount: Double) -> Macros {
        let r = per > 0 ? amount / per : 0
        return Macros(kcal: kcal * r, p: p * r, c: c * r, f: f * r)
    }

    /// "per 100g dry", "per 1 slice", "per 100ml"
    var perLabel: String {
        if per == 1 && !isMetric { return "1 \(unit)" }
        return "\(per.clean)\(unit == "ml" ? "ml" : "g")\(dry ? " dry" : "")"
    }

    func amountLabel(_ amount: Double) -> String {
        switch unit {
        case "g": return "\(amount.clean)g\(dry ? " dry" : "")"
        case "ml": return "\(amount.clean)ml"
        default: return "\(amount.clean) \(unit)\(amount == 1 ? "" : "s")"
        }
    }
}

struct MealPart: Codable, Hashable {
    var foodId: String
    var amount: Double
}

/// A saved "usual" meal made of foods.
@Model
final class Meal {
    @Attribute(.unique) var id: String
    var name: String
    var desc: String
    var parts: [MealPart]
    var sortIndex: Int
    /// Pinned to the top of Your meals.
    var favourite: Bool = false

    init(id: String, name: String, desc: String, parts: [MealPart], sortIndex: Int = 0) {
        self.id = id
        self.name = name
        self.desc = desc
        self.parts = parts
        self.sortIndex = sortIndex
    }
}

/// One logged item on a given day.
@Model
final class Entry {
    @Attribute(.unique) var id: UUID
    /// YYYY-MM-DD in the user's calendar.
    var date: String
    var slotRaw: String
    var kindRaw: String
    /// Food id or meal id. For quick-adds, the label.
    var ref: String
    /// Grams / units for foods, servings for meals and quick-adds.
    var amount: Double
    /// HH:mm
    var time: String
    var createdAt: Date

    // Quick-add stores its own nutrition (per 1 serving).
    var quickKcal: Double?
    var quickP: Double?
    var quickC: Double?
    var quickF: Double?
    /// Free-text quantity, e.g. "4 each" for entries imported from another app.
    var note: String?

    init(date: String, slot: Slot, kind: EntryKind, ref: String, amount: Double, time: String,
         quick: Macros? = nil) {
        self.id = UUID()
        self.date = date
        self.slotRaw = slot.rawValue
        self.kindRaw = kind.rawValue
        self.ref = ref
        self.amount = amount
        self.time = time
        self.createdAt = .now
        self.quickKcal = quick?.kcal
        self.quickP = quick?.p
        self.quickC = quick?.c
        self.quickF = quick?.f
    }

    var slot: Slot {
        get { Slot(rawValue: slotRaw) ?? .snack }
        set { slotRaw = newValue.rawValue }
    }
    var kind: EntryKind { EntryKind(rawValue: kindRaw) ?? .food }
    var quickMacros: Macros {
        Macros(kcal: quickKcal ?? 0, p: quickP ?? 0, c: quickC ?? 0, f: quickF ?? 0)
    }
}

/// A body-mass reading pulled from Apple Health.
@Model
final class WeightReading {
    /// HealthKit sample UUID.
    @Attribute(.unique) var id: String
    var date: String
    var kg: Double
    var time: String
    var timestamp: Date
    var source: String

    init(id: String, timestamp: Date, kg: Double, source: String = "AppleHealth") {
        self.id = id
        self.timestamp = timestamp
        self.date = DayKey.key(timestamp)
        self.time = DayKey.time(timestamp)
        self.kg = kg
        self.source = source
    }
}

struct Goals: Codable, Equatable {
    var kcal: Double = 1800
    var p: Double = 150
    var c: Double = 170
    var f: Double = 60
}

extension Double {
    /// 80 → "80", 0.5 → "0.5", 1.25 → "1.25"
    var clean: String {
        if self == rounded() { return String(Int(self)) }
        let s = String(format: "%.2f", self)
        return s.replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
    }
}
