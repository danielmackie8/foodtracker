import Foundation

struct Macros: Equatable {
    var kcal: Double = 0
    var p: Double = 0
    var c: Double = 0
    var f: Double = 0

    static let zero = Macros()

    static func + (a: Macros, b: Macros) -> Macros {
        Macros(kcal: a.kcal + b.kcal, p: a.p + b.p, c: a.c + b.c, f: a.f + b.f)
    }
    static func - (a: Macros, b: Macros) -> Macros {
        Macros(kcal: a.kcal - b.kcal, p: a.p - b.p, c: a.c - b.c, f: a.f - b.f)
    }
    static func * (a: Macros, k: Double) -> Macros {
        Macros(kcal: a.kcal * k, p: a.p * k, c: a.c * k, f: a.f * k)
    }
    static func += (a: inout Macros, b: Macros) { a = a + b }
}

struct DayTotals {
    var macros = Macros()
    var count = 0
}

/// Lookup tables for foods and meals, used to turn entries into nutrition.
struct Catalog {
    let foods: [String: Food]
    let meals: [String: Meal]

    init(foods: [Food], meals: [Meal]) {
        self.foods = Dictionary(foods.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        self.meals = Dictionary(meals.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private init(foodMap: [String: Food], mealMap: [String: Meal]) {
        foods = foodMap
        meals = mealMap
    }

    /// The same catalogue with one more food (e.g. a product that was just saved).
    func with(_ food: Food) -> Catalog {
        var f = foods
        f[food.id] = food
        return Catalog(foodMap: f, mealMap: meals)
    }

    func macros(of meal: Meal) -> Macros {
        meal.parts.reduce(into: Macros()) { acc, part in
            if let food = foods[part.foodId] { acc += food.macros(for: part.amount) }
        }
    }

    func macros(kind: EntryKind, ref: String, amount: Double, quick: Macros = .zero, transientFood: Food? = nil) -> Macros {
        switch kind {
        case .quick: return quick * amount
        case .meal: return meals[ref].map { macros(of: $0) * amount } ?? .zero
        case .food:
            if let food = foods[ref] ?? (transientFood?.id == ref ? transientFood : nil) {
                return food.macros(for: amount)
            }
            return .zero
        }
    }

    func macros(of entry: Entry) -> Macros {
        macros(kind: entry.kind, ref: entry.ref, amount: entry.amount, quick: entry.quickMacros)
    }

    func name(of entry: Entry) -> String {
        switch entry.kind {
        case .quick: return entry.ref.isEmpty ? "Quick add" : entry.ref
        case .meal: return meals[entry.ref]?.name ?? "Deleted meal"
        case .food: return foods[entry.ref]?.name ?? "Unknown food"
        }
    }

    func amountLabel(of entry: Entry) -> String {
        switch entry.kind {
        case .quick:
            if let note = entry.note, !note.isEmpty {
                return entry.amount == 1 ? note : "\(entry.amount.clean) × \(note)"
            }
            return entry.amount == 1 ? "Quick add" : "\(entry.amount.clean) × quick add"
        case .meal:
            if entry.amount == 1, let m = meals[entry.ref] { return m.desc }
            return entry.amount == 1 ? "1 serving" : "\(entry.amount.clean) servings"
        case .food: return foods[entry.ref]?.amountLabel(entry.amount) ?? "\(entry.amount.clean)g"
        }
    }
}

/// Entries grouped by day with cached totals.
struct Ledger {
    let catalog: Catalog
    private(set) var byDate: [String: [Entry]] = [:]

    init(entries: [Entry], catalog: Catalog) {
        self.catalog = catalog
        for e in entries { byDate[e.date, default: []].append(e) }
    }

    func entries(on day: String) -> [Entry] { byDate[day] ?? [] }

    func totals(_ day: String) -> DayTotals {
        let list = entries(on: day)
        return DayTotals(macros: list.reduce(into: Macros()) { $0 += catalog.macros(of: $1) }, count: list.count)
    }
}

// MARK: - Dates

enum DayKey {
    private static let keyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()

    static var cal: Calendar {
        var c = Calendar.current
        c.firstWeekday = 2 // Monday
        return c
    }

    static func key(_ date: Date) -> String {
        keyFormatter.timeZone = .current
        return keyFormatter.string(from: date)
    }
    static func time(_ date: Date) -> String {
        timeFormatter.timeZone = .current
        return timeFormatter.string(from: date)
    }
    static func date(_ key: String) -> Date {
        keyFormatter.timeZone = .current
        return keyFormatter.date(from: key) ?? cal.startOfDay(for: .now)
    }
    /// Date for a day key plus an HH:mm time, used when writing to Apple Health.
    static func date(_ key: String, time: String) -> Date {
        let base = date(key)
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return base }
        return cal.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: base) ?? base
    }

    static var today: Date { cal.startOfDay(for: .now) }
    static var todayKey: String { key(.now) }

    static func add(_ days: Int, to date: Date) -> Date {
        cal.date(byAdding: .day, value: days, to: date) ?? date
    }

    static func monday(of date: Date) -> Date {
        let weekday = cal.component(.weekday, from: date) // 1 = Sunday
        return add(-((weekday + 5) % 7), to: cal.startOfDay(for: date))
    }

    /// "23 Nov"
    static func short(_ date: Date) -> String { date.formatted(.dateTime.day().month(.abbreviated)) }
    /// "Monday, 23 November"
    static func long(_ date: Date) -> String { date.formatted(.dateTime.weekday(.wide).day().month(.wide)) }
    static func weekday(_ date: Date) -> String { date.formatted(.dateTime.weekday(.wide)) }
    /// "M", "T"… Monday-first single letters.
    static func initial(_ date: Date) -> String {
        let i = (cal.component(.weekday, from: date) + 5) % 7
        return ["M", "T", "W", "T", "F", "S", "S"][i]
    }
}

extension Double {
    /// Rounded and grouped: 1800 → "1,800"
    var kcalString: String { Int(rounded()).formatted(.number.grouping(.automatic)) }
    var grams: String { "\(Int(rounded()))" }
}
