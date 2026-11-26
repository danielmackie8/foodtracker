import Foundation
import SwiftData
import CryptoKit

/// Two-way sync between the on-device store and Supabase.
///
/// The phone stays the working copy (fast, offline). Each sync:
///  1. Pulls rows changed on the server since the last pull (other devices, or Claude adding food)
///     and applies them, unless that record was also changed locally since the last sync.
///  2. Pushes local records whose content changed since they were last synced, and marks records
///     deleted locally as `deleted` on the server.
/// A content fingerprint per record (stored in Application Support) tells what changed, so no
/// code elsewhere needs to remember to flag edits. Built-in foods aren't synced; every phone has them.
@MainActor
@Observable
final class CloudSync {
    enum Status: Equatable { case idle, syncing, failed(String) }

    let auth: CloudAuth
    private(set) var status: Status = .idle
    private(set) var lastSynced: Date? {
        didSet { UserDefaults.standard.set(lastSynced, forKey: "cloudLastSynced") }
    }

    @ObservationIgnored private var state = SyncState.load()
    @ObservationIgnored private var pending: Task<Void, Never>?

    init(auth: CloudAuth) {
        self.auth = auth
        lastSynced = UserDefaults.standard.object(forKey: "cloudLastSynced") as? Date
    }

    var isSyncing: Bool { status == .syncing }

    /// Sync soon (after local edits); repeated calls within the delay collapse into one sync.
    func scheduleSync(context: ModelContext, app: AppState, health: HealthKitManager, after seconds: Double = 2) {
        guard auth.isSignedIn, !isSyncing else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            await self?.sync(context: context, app: app, health: health)
        }
    }

    func sync(context: ModelContext, app: AppState, health: HealthKitManager) async {
        guard auth.isSignedIn, !isSyncing else { return }
        status = .syncing
        do {
            let userId = auth.session?.userId ?? ""
            if state.userId != userId { state = SyncState(userId: userId) } // new account: start fresh
            try await pullAll(context: context, app: app, health: health)
            try await pushAll(context: context)
            state.save()
            lastSynced = .now
            status = .idle
        } catch CloudError.notSignedIn {
            status = .idle
        } catch {
            state.save()
            status = .failed(error.localizedDescription)
        }
    }

    /// Forget sync history (used when signing out), so the next sign-in starts clean.
    func reset() {
        pending?.cancel()
        state = SyncState(userId: "")
        state.save()
        lastSynced = nil
        status = .idle
    }

    // MARK: Pull

    private func pullAll(context: ModelContext, app: AppState, health: HealthKitManager) async throws {
        // Foods and meals first so pulled entries can refer to them.
        for row in try await pull("sage_foods") { applyFood(row, context: context) }
        for row in try await pull("sage_meals") { applyMeal(row, context: context) }
        var newEntries: [Entry] = []
        for row in try await pull("sage_entries") {
            if let created = applyEntry(row, context: context) { newEntries.append(created) }
        }
        try context.save()

        // Food added elsewhere (e.g. by Claude) for today or yesterday also goes to Apple Health.
        if app.healthEnabled && app.writeNutrition && !newEntries.isEmpty {
            let recent = DayKey.key(DayKey.add(-1, to: DayKey.today))
            let catalog = Catalog(foods: (try? context.fetch(FetchDescriptor<Food>())) ?? [],
                                  meals: (try? context.fetch(FetchDescriptor<Meal>())) ?? [])
            for e in newEntries where e.date >= recent {
                let macros = catalog.macros(of: e), name = catalog.name(of: e)
                let date = DayKey.date(e.date, time: e.time), id = e.id
                Task { await health.write(entryId: id, name: name, date: date, macros: macros) }
            }
        }
    }

    private func pull(_ table: String) async throws -> [[String: Any]] {
        var all: [[String: Any]] = []
        var since = state.lastPull[table]
        while true {
            var query = [URLQueryItem(name: "select", value: "*"),
                         URLQueryItem(name: "order", value: "updated_at.asc"),
                         URLQueryItem(name: "limit", value: "1000")]
            if let since { query.append(URLQueryItem(name: "updated_at", value: "gt.\(since)")) }
            let data = try await request("GET", table, query: query)
            guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw CloudError.badResponse }
            all += rows
            if let last = rows.last?["updated_at"] as? String { since = last }
            if rows.count < 1000 { break }
        }
        state.lastPull[table] = since
        return all
    }

    private func fetchOne<T: PersistentModel>(_ type: T.Type, _ predicate: Predicate<T>, context: ModelContext) -> T? {
        var d = FetchDescriptor<T>(predicate: predicate)
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }

    /// True when the local record changed since it was last synced (local edits win).
    private func locallyModified(_ key: String, row: [String: Any]) -> Bool {
        guard let stored = state.hashes[key] else { return true }
        return stored != Self.fingerprint(row)
    }

    private func applyFood(_ row: [String: Any], context: ModelContext) {
        guard let id = row["id"] as? String else { return }
        let key = "foods/\(id)"
        let local = fetchOne(Food.self, #Predicate<Food> { $0.id == id }, context: context)
        if let local, locallyModified(key, row: Self.row(local)) { return }
        if bool(row["deleted"]) {
            if let local { context.delete(local) }
            state.hashes[key] = nil
            return
        }
        let food: Food
        if let local {
            food = local
        } else {
            food = Food(id: id, name: "", unit: "g", per: 100, step: 10, def: 100, kcal: 0, p: 0, c: 0, f: 0, source: .custom)
            context.insert(food)
        }
        food.name = row["name"] as? String ?? food.name
        food.brand = row["brand"] as? String
        food.pack = row["pack"] as? String
        food.unit = row["unit"] as? String ?? "g"
        food.per = num(row["per"]) ?? 100
        food.step = num(row["step"]) ?? 10
        food.def = num(row["def"]) ?? 100
        food.kcal = num(row["kcal"]) ?? 0
        food.p = num(row["p"]) ?? 0
        food.c = num(row["c"]) ?? 0
        food.f = num(row["f"]) ?? 0
        food.dry = bool(row["dry"])
        food.sourceRaw = row["source"] as? String ?? FoodSource.custom.rawValue
        food.barcode = row["barcode"] as? String
        food.servingGrams = num(row["serving_grams"])
        state.hashes[key] = Self.fingerprint(Self.row(food))
    }

    private func applyMeal(_ row: [String: Any], context: ModelContext) {
        guard let id = row["id"] as? String else { return }
        let key = "meals/\(id)"
        let local = fetchOne(Meal.self, #Predicate<Meal> { $0.id == id }, context: context)
        if let local, locallyModified(key, row: Self.row(local)) { return }
        if bool(row["deleted"]) {
            if let local { context.delete(local) }
            state.hashes[key] = nil
            return
        }
        let parts = (row["parts"] as? [[String: Any]] ?? []).compactMap { p -> MealPart? in
            guard let foodId = p["foodId"] as? String else { return nil }
            return MealPart(foodId: foodId, amount: num(p["amount"]) ?? 1)
        }
        let meal: Meal
        if let local {
            meal = local
        } else {
            meal = Meal(id: id, name: "", desc: "", parts: [])
            context.insert(meal)
        }
        meal.name = row["name"] as? String ?? meal.name
        meal.desc = row["descr"] as? String ?? ""
        meal.parts = parts
        meal.sortIndex = Int(num(row["sort_index"]) ?? 0)
        meal.favourite = bool(row["favourite"])
        state.hashes[key] = Self.fingerprint(Self.row(meal))
    }

    /// Returns the entry if it was newly created on this device.
    private func applyEntry(_ row: [String: Any], context: ModelContext) -> Entry? {
        guard let idString = row["id"] as? String, let uuid = UUID(uuidString: idString) else { return nil }
        let key = "entries/\(uuid.uuidString.lowercased())"
        let local = fetchOne(Entry.self, #Predicate<Entry> { $0.id == uuid }, context: context)
        if let local, locallyModified(key, row: Self.row(local)) { return nil }
        if bool(row["deleted"]) {
            if let local { context.delete(local) }
            state.hashes[key] = nil
            return nil
        }
        guard let date = row["date"] as? String, let slot = Slot(rawValue: row["slot"] as? String ?? ""),
              let kind = EntryKind(rawValue: row["kind"] as? String ?? ""), let ref = row["ref"] as? String else { return nil }
        var created: Entry?
        let entry: Entry
        if let local {
            entry = local
        } else {
            entry = Entry(date: date, slot: slot, kind: kind, ref: ref, amount: 1, time: "12:00")
            entry.id = uuid
            context.insert(entry)
            created = entry
        }
        entry.date = date
        entry.slot = slot
        entry.kindRaw = kind.rawValue
        entry.ref = ref
        entry.amount = num(row["amount"]) ?? 1
        entry.time = row["time"] as? String ?? "12:00"
        entry.quickKcal = num(row["quick_kcal"])
        entry.quickP = num(row["quick_p"])
        entry.quickC = num(row["quick_c"])
        entry.quickF = num(row["quick_f"])
        entry.note = row["note"] as? String
        state.hashes[key] = Self.fingerprint(Self.row(entry))
        return created
    }

    // MARK: Push

    private func pushAll(context: ModelContext) async throws {
        let foods = ((try? context.fetch(FetchDescriptor<Food>())) ?? []).filter { $0.source != .builtin }
        try await push("sage_foods", prefix: "foods",
                       rows: foods.map { ("foods/\($0.id)", Self.row($0)) })
        let meals = (try? context.fetch(FetchDescriptor<Meal>())) ?? []
        try await push("sage_meals", prefix: "meals",
                       rows: meals.map { ("meals/\($0.id)", Self.row($0)) })
        let entries = (try? context.fetch(FetchDescriptor<Entry>())) ?? []
        try await push("sage_entries", prefix: "entries",
                       rows: entries.map { ("entries/\($0.id.uuidString.lowercased())", Self.row($0)) })
    }

    private func push(_ table: String, prefix: String, rows: [(key: String, row: [String: Any])]) async throws {
        let userId = auth.session?.userId ?? ""
        // Changed or new records.
        let changed = rows.filter { state.hashes[$0.key] != Self.fingerprint($0.row) }
        for chunk in changed.chunked(200) {
            let body: [[String: Any]] = chunk.map { var r = $0.row; r["user_id"] = userId; return r }
            _ = try await request("POST", table, query: [URLQueryItem(name: "on_conflict", value: "user_id,id")],
                                  body: body, prefer: "resolution=merge-duplicates,return=minimal")
            for item in chunk { state.hashes[item.key] = Self.fingerprint(item.row) }
        }
        // Records deleted on this phone since the last sync.
        let present = Set(rows.map(\.key))
        let gone = state.hashes.keys.filter { $0.hasPrefix(prefix + "/") && !present.contains($0) }
        for chunk in Array(gone).chunked(100) {
            let ids = chunk.map { String($0.dropFirst(prefix.count + 1)) }
            let list = ids.map { "\"\($0)\"" }.joined(separator: ",")
            _ = try await request("PATCH", table, query: [URLQueryItem(name: "id", value: "in.(\(list))")],
                                  body: ["deleted": true], prefer: "return=minimal")
            for key in chunk { state.hashes[key] = nil }
        }
    }

    // MARK: Rows

    static func row(_ f: Food) -> [String: Any] {
        ["id": f.id, "name": f.name, "brand": f.brand ?? NSNull(), "pack": f.pack ?? NSNull(), "unit": f.unit,
         "per": f.per, "step": f.step, "def": f.def, "kcal": f.kcal, "p": f.p, "c": f.c, "f": f.f, "dry": f.dry,
         "source": f.sourceRaw, "barcode": f.barcode ?? NSNull(), "serving_grams": f.servingGrams ?? NSNull(),
         "deleted": false]
    }

    static func row(_ m: Meal) -> [String: Any] {
        ["id": m.id, "name": m.name, "descr": m.desc,
         "parts": m.parts.map { ["foodId": $0.foodId, "amount": $0.amount] as [String: Any] },
         "sort_index": m.sortIndex, "favourite": m.favourite, "deleted": false]
    }

    static func row(_ e: Entry) -> [String: Any] {
        ["id": e.id.uuidString.lowercased(), "date": e.date, "slot": e.slotRaw, "kind": e.kindRaw, "ref": e.ref,
         "amount": e.amount, "time": e.time,
         "quick_kcal": e.quickKcal ?? NSNull(), "quick_p": e.quickP ?? NSNull(),
         "quick_c": e.quickC ?? NSNull(), "quick_f": e.quickF ?? NSNull(),
         "note": e.note ?? NSNull(), "deleted": false]
    }

    static func fingerprint(_ row: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: HTTP

    private func request(_ method: String, _ table: String, query: [URLQueryItem] = [],
                         body: Any? = nil, prefer: String? = nil) async throws -> Data {
        let token = try await auth.validAccessToken()
        var comps = URLComponents(url: CloudConfig.url.appendingPathComponent("rest/v1/\(table)"), resolvingAgainstBaseURL: false)!
        comps.queryItems = query
        // "+" in timestamps must be encoded, or the server reads it as a space.
        comps.percentEncodedQuery = comps.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.timeoutInterval = 30
        req.setValue(CloudConfig.publishableKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let prefer { req.setValue(prefer, forHTTPHeaderField: "Prefer") }
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw CloudError.server(code, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    private func num(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue }
    private func bool(_ v: Any?) -> Bool { (v as? NSNumber)?.boolValue ?? false }
}

/// What was last synced: a fingerprint per record and the newest server timestamp seen per table.
private struct SyncState: Codable {
    var userId: String
    var hashes: [String: String] = [:]
    var lastPull: [String: String] = [:]

    private static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("cloud-sync.json")
    }

    static func load() -> SyncState {
        guard let data = try? Data(contentsOf: url),
              let s = try? JSONDecoder().decode(SyncState.self, from: data) else { return SyncState(userId: "") }
        return s
    }

    func save() {
        try? FileManager.default.createDirectory(at: Self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(self) { try? data.write(to: Self.url, options: .atomic) }
    }
}

private extension Array {
    func chunked(_ size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
