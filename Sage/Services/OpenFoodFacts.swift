import Foundation

/// A product from Open Food Facts (ODbL). Nutrition is per 100 g / 100 ml.
struct OFFProduct: Codable, Hashable, Identifiable {
    var barcode: String
    var name: String
    var brand: String
    var pack: String
    var kcal: Double
    var p: Double
    var c: Double
    var f: Double
    var servingGrams: Double

    var id: String { barcode }
    var foodId: String { "off" + barcode }

    var subtitle: String {
        let head = [brand, pack].filter { !$0.isEmpty }.joined(separator: " · ")
        return (head.isEmpty ? "" : head + " · ") + "\(kcal.clean) kcal · \(p.clean) g protein per 100g"
    }

    /// An unsaved Food for this product. It is inserted into the store when logged,
    /// so logged products keep working offline.
    func makeFood() -> Food {
        Food(id: foodId, name: name, brand: brand.isEmpty ? nil : brand, pack: pack.isEmpty ? nil : pack,
             unit: "g", per: 100, step: 10, def: servingGrams > 0 ? servingGrams : 100,
             kcal: kcal, p: p, c: c, f: f, source: .off, barcode: barcode,
             servingGrams: servingGrams > 0 ? servingGrams : nil)
    }

    static func normalise(_ code: String) -> String {
        String(code.drop(while: { $0 == "0" }))
    }
}

// MARK: - Bundled UK catalogue (off-uk.json)

/// 671 UK products shipped with the app, searchable offline.
final class BundledProducts {
    static let shared = BundledProducts()

    let products: [OFFProduct]
    private let haystack: [String]

    private init() {
        var list: [OFFProduct] = []
        if let url = Bundle.main.url(forResource: "off-uk", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let rows = try? JSONSerialization.jsonObject(with: data) as? [[Any]] {
            // [barcode, name, brand, pack, kcal/100g, protein, carbs, fat, servingGrams]
            func num(_ v: Any) -> Double { (v as? NSNumber)?.doubleValue ?? Double(v as? String ?? "") ?? 0 }
            for r in rows where r.count >= 9 {
                list.append(OFFProduct(barcode: r[0] as? String ?? "", name: r[1] as? String ?? "",
                                       brand: r[2] as? String ?? "", pack: r[3] as? String ?? "",
                                       kcal: num(r[4]), p: num(r[5]), c: num(r[6]), f: num(r[7]), servingGrams: num(r[8])))
            }
        }
        products = list
        haystack = list.map { ($0.name + " " + $0.brand).lowercased() }
    }

    func search(_ query: String, limit: Int = 30) -> [OFFProduct] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        if q.allSatisfy(\.isNumber), (8...14).contains(q.count) {
            return product(barcode: q).map { [$0] } ?? []
        }
        let tokens = q.split(separator: " ").map(String.init)
        var out: [OFFProduct] = []
        for (i, h) in haystack.enumerated() where tokens.allSatisfy({ h.contains($0) }) {
            out.append(products[i])
            if out.count >= limit { break }
        }
        return out
    }

    func product(barcode: String) -> OFFProduct? {
        let n = OFFProduct.normalise(barcode)
        return products.first { OFFProduct.normalise($0.barcode) == n }
    }
}

// MARK: - Live API

enum OFFError: LocalizedError {
    case rateLimited, notFound, badResponse
    var errorDescription: String? {
        switch self {
        case .rateLimited: return "Too many searches — try again in a minute."
        case .notFound: return "Product not found on Open Food Facts."
        case .badResponse: return "Open Food Facts didn't respond as expected."
        }
    }
}

/// Live Open Food Facts lookups with a disk cache and a client-side rate limit
/// (search is limited to about 10 requests a minute).
actor OpenFoodFactsClient {
    static let shared = OpenFoodFactsClient()

    private let session: URLSession
    private var searchTimes: [Date] = []
    private var searchCache: [String: [OFFProduct]] = [:]
    private var productCache: [String: OFFProduct] = [:]
    private let cacheURL: URL

    private static let fields = "code,product_name,product_name_en,brands,quantity,serving_quantity,nutriments"

    init() {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = ["User-Agent": "SageFoodTracker/1.0 (iOS; personal food log)"]
        config.timeoutIntervalForRequest = 15
        config.urlCache = URLCache(memoryCapacity: 4 << 20, diskCapacity: 32 << 20)
        session = URLSession(configuration: config)

        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheURL = dir.appendingPathComponent("off-products.json")
        if let data = try? Data(contentsOf: cacheURL),
           let saved = try? JSONDecoder().decode([String: OFFProduct].self, from: data) {
            productCache = saved
        }
    }

    /// Bundled catalogue → disk cache → network.
    func product(barcode: String) async throws -> OFFProduct {
        let code = barcode.filter(\.isNumber)
        if let p = BundledProducts.shared.product(barcode: code) { return p }
        if let p = productCache[OFFProduct.normalise(code)] { return p }

        var comps = URLComponents(string: "https://world.openfoodfacts.org/api/v2/product/\(code).json")!
        comps.queryItems = [URLQueryItem(name: "fields", value: Self.fields)]
        let (data, response) = try await session.data(from: comps.url!)
        if (response as? HTTPURLResponse)?.statusCode == 404 { throw OFFError.notFound }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw OFFError.badResponse }
        guard (json["status"] as? NSNumber)?.intValue == 1, let raw = json["product"] as? [String: Any],
              let product = Self.parse(raw, fallbackCode: code) else { throw OFFError.notFound }
        remember(product)
        return product
    }

    /// Full-text search restricted to UK products.
    func search(_ query: String) async throws -> [OFFProduct] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard q.count >= 2 else { return [] }
        if let cached = searchCache[q] { return cached }

        let now = Date()
        searchTimes = searchTimes.filter { now.timeIntervalSince($0) < 60 }
        guard searchTimes.count < 9 else { throw OFFError.rateLimited }
        searchTimes.append(now)

        var comps = URLComponents(string: "https://world.openfoodfacts.org/cgi/search.pl")!
        comps.queryItems = [
            .init(name: "search_terms", value: q),
            .init(name: "search_simple", value: "1"),
            .init(name: "action", value: "process"),
            .init(name: "json", value: "1"),
            .init(name: "page_size", value: "20"),
            .init(name: "tagtype_0", value: "countries"),
            .init(name: "tag_contains_0", value: "contains"),
            .init(name: "tag_0", value: "united-kingdom"),
            .init(name: "fields", value: Self.fields),
        ]
        let (data, response) = try await session.data(from: comps.url!)
        if (response as? HTTPURLResponse)?.statusCode == 429 { throw OFFError.rateLimited }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = json["products"] as? [[String: Any]] else { throw OFFError.badResponse }
        let products = rows.compactMap { Self.parse($0, fallbackCode: nil) }
        searchCache[q] = products
        return products
    }

    private func remember(_ p: OFFProduct) {
        productCache[OFFProduct.normalise(p.barcode)] = p
        if let data = try? JSONEncoder().encode(productCache) { try? data.write(to: cacheURL, options: .atomic) }
    }

    static func parse(_ raw: [String: Any], fallbackCode: String?) -> OFFProduct? {
        func num(_ v: Any?) -> Double? {
            if let n = v as? NSNumber { return n.doubleValue }
            if let s = v as? String { return Double(s.replacingOccurrences(of: ",", with: ".")) }
            return nil
        }
        let n = raw["nutriments"] as? [String: Any] ?? [:]
        let name = (raw["product_name_en"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (raw["product_name"] as? String ?? "")
        guard !name.isEmpty else { return nil }
        let kcal = num(n["energy-kcal_100g"]) ?? num(n["energy_100g"]).map { $0 / 4.184 }
        guard let kcal else { return nil }
        let brand = (raw["brands"] as? String ?? "").split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        return OFFProduct(barcode: raw["code"] as? String ?? fallbackCode ?? "",
                          name: name, brand: brand, pack: raw["quantity"] as? String ?? "",
                          kcal: kcal.rounded(), p: num(n["proteins_100g"]) ?? 0,
                          c: num(n["carbohydrates_100g"]) ?? 0, f: num(n["fat_100g"]) ?? 0,
                          servingGrams: num(raw["serving_quantity"]) ?? 0)
    }
}
