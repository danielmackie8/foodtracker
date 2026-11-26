import Foundation
import SwiftData

/// A food and amount while a meal is being built or edited. The food may not be saved yet
/// (a product from the database, or a food made from a quick-add entry).
struct DraftPart: Identifiable {
    let id = UUID()
    var food: Food
    var amount: Double
}

@MainActor
enum MealActions {
    /// Turns logged entries into meal parts. Meals are expanded into their foods; quick-add
    /// entries become new "Your food" items per serving, so they can be adjusted later.
    static func draftParts(from entries: [Entry], catalog: Catalog) -> [DraftPart] {
        var parts: [DraftPart] = []
        for e in entries {
            switch e.kind {
            case .food:
                if let f = catalog.foods[e.ref] { parts.append(DraftPart(food: f, amount: e.amount)) }
            case .meal:
                if let m = catalog.meals[e.ref] {
                    for p in m.parts {
                        if let f = catalog.foods[p.foodId] { parts.append(DraftPart(food: f, amount: p.amount * e.amount)) }
                    }
                }
            case .quick:
                let m = e.quickMacros
                let food = Food(id: "c" + UUID().uuidString, name: catalog.name(of: e), unit: "serving",
                                per: 1, step: 0.5, def: 1, kcal: m.kcal, p: m.p, c: m.c, f: m.f, source: .custom)
                parts.append(DraftPart(food: food, amount: e.amount))
            }
        }
        // Merge repeats of the same food.
        var merged: [DraftPart] = []
        for p in parts {
            if let i = merged.firstIndex(where: { $0.food.id == p.food.id }) { merged[i].amount += p.amount }
            else { merged.append(p) }
        }
        return merged
    }

    /// Short description, e.g. "250g Beef mince 5% · Egg, large ×4".
    static func describe(_ parts: [DraftPart]) -> String {
        parts.map { p in
            p.food.isMetric ? "\(p.food.amountLabel(p.amount)) \(p.food.name)" : "\(p.food.name) ×\(p.amount.clean)"
        }
        .joined(separator: " · ")
    }

    /// Creates or updates a meal. Existing log entries keep the nutrition they had.
    @discardableResult
    static func save(_ meal: Meal?, name: String, parts: [DraftPart], favourite: Bool,
                     catalog: Catalog, context: ModelContext) -> Meal {
        for p in parts where catalog.foods[p.food.id] == nil && p.food.modelContext == nil {
            context.insert(p.food)
        }
        let mealParts = parts.map { MealPart(foodId: $0.food.id, amount: $0.amount) }
        let desc = describe(parts)
        let result: Meal
        if let meal {
            freezeEntries(of: meal, catalog: catalog, context: context)
            meal.name = name
            meal.parts = mealParts
            meal.desc = desc
            meal.favourite = favourite
            result = meal
        } else {
            let nextIndex = ((try? context.fetch(FetchDescriptor<Meal>()))?.map(\.sortIndex).max() ?? 0) + 1
            result = Meal(id: "m" + UUID().uuidString, name: name, desc: desc, parts: mealParts, sortIndex: nextIndex)
            result.favourite = favourite
            context.insert(result)
        }
        try? context.save()
        return result
    }

    /// Deletes a meal; past entries that used it become quick-adds with the same numbers.
    static func delete(_ meal: Meal, catalog: Catalog, context: ModelContext) {
        freezeEntries(of: meal, catalog: catalog, context: context)
        context.delete(meal)
        try? context.save()
    }

    /// Converts every entry that uses `meal` into a quick-add holding its current nutrition,
    /// so editing or deleting the meal never changes past days.
    private static func freezeEntries(of meal: Meal, catalog: Catalog, context: ModelContext) {
        let id = meal.id
        let descriptor = FetchDescriptor<Entry>(predicate: #Predicate<Entry> { $0.ref == id })
        let entries = ((try? context.fetch(descriptor)) ?? []).filter { $0.kind == .meal }
        let perServing = catalog.macros(of: meal)
        for e in entries {
            e.note = e.amount == 1 ? meal.desc : "\(e.amount.clean) servings"
            e.ref = meal.name
            e.kindRaw = EntryKind.quick.rawValue
            e.quickKcal = perServing.kcal
            e.quickP = perServing.p
            e.quickC = perServing.c
            e.quickF = perServing.f
        }
    }
}
