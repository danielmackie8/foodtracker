import Foundation
import SwiftData

/// Built-in foods and the user's usual meals.
/// Pasta, rice and oats are dry weight. No fish or seafood.
enum SeedData {
    private static func food(_ id: String, _ name: String, unit: String, per: Double, step: Double, def: Double,
                             _ kcal: Double, _ p: Double, _ c: Double, _ f: Double, dry: Bool = false) -> Food {
        Food(id: id, name: name, unit: unit, per: per, step: step, def: def, kcal: kcal, p: p, c: c, f: f, dry: dry, source: .builtin)
    }

    static func foods() -> [Food] {
        [
            food("whey", "Whey protein", unit: "scoop", per: 1, step: 1, def: 1, 120, 24, 3, 2),
            food("egg", "Egg, large", unit: "egg", per: 1, step: 1, def: 2, 72, 6.5, 0.4, 5),
            food("sourdough", "Sourdough", unit: "slice", per: 1, step: 1, def: 1, 140, 5, 26, 1),
            food("bread", "Wholemeal bread", unit: "slice", per: 1, step: 1, def: 2, 95, 4.5, 15, 1.2),
            food("yog", "Greek yoghurt", unit: "g", per: 100, step: 25, def: 100, 95, 7, 4, 5),
            food("berries", "Mixed berries", unit: "g", per: 100, step: 20, def: 80, 50, 1, 10, 0),
            food("pb", "Peanut butter", unit: "g", per: 100, step: 5, def: 15, 600, 25, 13, 47),
            food("mince", "Beef mince 5%", unit: "g", per: 100, step: 25, def: 250, 136, 20.8, 0, 5.5),
            food("chicken", "Chicken breast", unit: "g", per: 100, step: 25, def: 200, 120, 23, 0, 3),
            food("pork", "Pork loin steak", unit: "g", per: 100, step: 25, def: 150, 145, 22, 0, 6),
            food("pasta", "Pasta", unit: "g", per: 100, step: 10, def: 80, 356, 12.5, 72, 1.5, dry: true),
            food("rice", "Basmati rice", unit: "g", per: 100, step: 5, def: 75, 355, 8, 78, 1, dry: true),
            food("oats", "Porridge oats", unit: "g", per: 100, step: 10, def: 40, 375, 12.5, 60, 7.5, dry: true),
            food("potato", "Potatoes", unit: "g", per: 100, step: 50, def: 300, 77, 2, 17, 0.1),
            food("sauce", "Tomato pasta sauce", unit: "g", per: 100, step: 20, def: 120, 50, 1.5, 8, 1.5),
            food("milk", "Semi-skimmed milk", unit: "ml", per: 100, step: 50, def: 200, 49, 3.5, 5, 1.8),
            food("cheddar", "Cheddar", unit: "g", per: 100, step: 10, def: 30, 416, 25, 0.1, 35),
            food("banana", "Banana", unit: "banana", per: 1, step: 1, def: 1, 105, 1.3, 27, 0.4),
            food("oil", "Olive oil", unit: "tbsp", per: 1, step: 1, def: 1, 120, 0, 0, 14),
            food("pizza", "Takeaway pizza", unit: "slice", per: 1, step: 1, def: 2, 205, 9, 24, 8),
        ]
    }

    static func meals() -> [Meal] {
        let list: [(String, String, String, [(String, Double)])] = [
            ("shake", "Whey shake", "1 scoop", [("whey", 1)]),
            ("eggs", "Poached eggs & sourdough", "4 eggs · 1 slice sourdough", [("egg", 4), ("sourdough", 1)]),
            ("bowl", "Greek yoghurt bowl", "100g yoghurt · 80g berries · 15g PB", [("yog", 100), ("berries", 80), ("pb", 15)]),
            ("mincepasta", "Mince & pasta", "250g mince · 80g pasta (dry) · 120g sauce", [("mince", 250), ("pasta", 80), ("sauce", 120)]),
            ("chickpot", "Chicken & potatoes", "200g chicken · 300g potatoes", [("chicken", 200), ("potato", 300)]),
            ("mincerice", "Mince & rice", "250g mince · 75g rice (dry)", [("mince", 250), ("rice", 75)]),
            ("eggstoast", "Eggs on toast", "3 eggs · 2 slices wholemeal", [("egg", 3), ("bread", 2)]),
        ]
        return list.enumerated().map { i, m in
            Meal(id: m.0, name: m.1, desc: m.2, parts: m.3.map { MealPart(foodId: $0.0, amount: $0.1) }, sortIndex: i)
        }
    }

    /// Inserts any built-in foods and meals that aren't in the store yet.
    @MainActor
    static func ensureSeeded(_ context: ModelContext) {
        let existingFoods = Set((try? context.fetch(FetchDescriptor<Food>()))?.map(\.id) ?? [])
        for f in foods() where !existingFoods.contains(f.id) { context.insert(f) }
        let existingMeals = Set((try? context.fetch(FetchDescriptor<Meal>()))?.map(\.id) ?? [])
        for m in meals() where !existingMeals.contains(m.id) { context.insert(m) }
        try? context.save()
    }
}
