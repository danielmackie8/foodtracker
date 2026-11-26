import Foundation

/// Food estimated by Claude, handed to the app as a `sage://log` link or as pasted JSON.
///
/// Link:  sage://log?slot=Dinner&date=yesterday&item=Chicken%20katsu%20curry;1150;52;140;38;1%20regular
///        (one `item=` per food: name;kcal;protein;carbs;fat;amount — amount optional)
/// JSON:  {"slot":"Dinner","date":"today","items":[{"name":"…","amount":"…","kcal":0,"protein":0,"carbs":0,"fat":0}]}
struct ClaudeImport: Hashable {
    struct Item: Hashable, Identifiable {
        var id = UUID()
        var name: String
        var amount: String?
        var kcal: Double
        var p: Double
        var c: Double
        var f: Double
    }

    var slot: Slot?
    /// YYYY-MM-DD, or nil for "whichever day the log sheet is on".
    var date: String?
    var items: [Item]

    /// Accepts a sage:// link, Claude's whole reply containing one, or JSON (with or without a code fence).
    static func parse(_ text: String) -> ClaudeImport? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = trimmed.range(of: #"sage://[^\s)\]>"']+"#, options: .regularExpression),
           let url = URL(string: String(trimmed[range])),
           let parsed = parse(url: url) {
            return parsed
        }
        if let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}"), start < end {
            return parse(json: String(trimmed[start...end]))
        }
        return nil
    }

    static func parse(url: URL) -> ClaudeImport? {
        guard url.scheme?.lowercased() == "sage",
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let query = comps.queryItems ?? []
        if let data = query.first(where: { $0.name == "data" })?.value {
            return parse(json: data)
        }
        var items: [Item] = []
        for q in query where q.name == "item" {
            guard let value = q.value else { continue }
            let parts = value.split(separator: ";", omittingEmptySubsequences: false).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard parts.count >= 2, !parts[0].isEmpty else { continue }
            func n(_ i: Int) -> Double { i < parts.count ? number(parts[i]) ?? 0 : 0 }
            let amount = parts.count > 5 && !parts[5].isEmpty ? parts[5] : nil
            items.append(Item(name: parts[0], amount: amount, kcal: n(1), p: n(2), c: n(3), f: n(4)))
        }
        guard !items.isEmpty else { return nil }
        return ClaudeImport(slot: slot(query.first { $0.name == "slot" }?.value),
                            date: date(query.first { $0.name == "date" }?.value),
                            items: items)
    }

    static func parse(json: String) -> ClaudeImport? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let rawItems = (object["items"] as? [[String: Any]]) ?? [object] // a single item at the top level
        let items: [Item] = rawItems.compactMap { d in
            guard let name = (d["name"] as? String)?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
            func n(_ keys: String...) -> Double {
                for k in keys { if let v = number(d[k]) { return v } }
                return 0
            }
            return Item(name: name, amount: d["amount"] as? String,
                        kcal: n("kcal", "calories", "energy"), p: n("protein", "p"),
                        c: n("carbs", "carbohydrates", "c"), f: n("fat", "f"))
        }
        guard !items.isEmpty else { return nil }
        return ClaudeImport(slot: slot(object["slot"] as? String), date: date(object["date"] as? String), items: items)
    }

    // MARK: Helpers

    private static func number(_ v: Any?) -> Double? {
        if let n = v as? NSNumber { return n.doubleValue }
        guard let s = v as? String else { return nil }
        let cleaned = s.replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "0123456789.").inverted)
        return Double(cleaned)
    }

    private static func slot(_ s: String?) -> Slot? {
        guard let s = s?.lowercased() else { return nil }
        if s.hasPrefix("break") { return .breakfast }
        if s.hasPrefix("lunch") { return .lunch }
        if s.hasPrefix("snack") { return .snack }
        if s.hasPrefix("dinner") || s.hasPrefix("tea") || s.hasPrefix("supper") { return .dinner }
        return nil
    }

    private static func date(_ s: String?) -> String? {
        guard let s = s?.trimmingCharacters(in: .whitespaces).lowercased(), !s.isEmpty else { return nil }
        if s == "today" { return DayKey.todayKey }
        if s == "yesterday" { return DayKey.key(DayKey.add(-1, to: DayKey.today)) }
        // Only accept a real YYYY-MM-DD that isn't in the future.
        guard s.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
              s <= DayKey.todayKey else { return nil }
        return s
    }

    var total: Macros {
        items.reduce(into: Macros()) { $0 += Macros(kcal: $1.kcal, p: $1.p, c: $1.c, f: $1.f) }
    }

    /// The set-up text for Claude, shown in Profile with a Copy button.
    static let claudeInstructions = """
    You're my food-logging helper for my iPhone app, Sage. When I tell you what I ate, estimate calories and macros for each item (UK brands and portion sizes unless I say otherwise; pasta, rice and oats are dry weight). Keep the reply short:

    1. One line per item: name — kcal · protein g · carbs g · fat g.

    2. Then the same data as JSON in a single code block, so I can copy it into the app. Use exactly this shape, whole numbers, no units:
    {"slot":"Dinner","date":"today","items":[{"name":"…","amount":"…","kcal":0,"protein":0,"carbs":0,"fat":0}]}
    - slot is Breakfast, Lunch, Snack or Dinner: use what I said, otherwise guess from the time of day.
    - date is "today" unless I say otherwise ("yesterday" or YYYY-MM-DD).
    - Don't include links.
    """
}
