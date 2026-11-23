import Foundation
import SQLite3

/// The bundled Open Food Facts UK product database (built by scripts/update_products.py).
///
/// It ships as raw-DEFLATE-compressed SQLite (`products.sqlite.zlib`). On first launch,
/// and after an app update that ships newer data, it is unpacked into Application Support
/// and then opened read-only. Rows are stored most-scanned first, so a search that hits
/// its limit returns the popular products and stops early.
actor ProductDatabase {
    static let shared = ProductDatabase()

    struct Meta: Decodable {
        var version: String
        var count: Int
    }

    /// Read synchronously from the bundle, so the UI can show the product count straight away.
    nonisolated static let meta: Meta? = {
        guard let url = Bundle.main.url(forResource: "products-meta", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Meta.self, from: data)
    }()

    private var db: OpaquePointer?
    private var openFailed = false
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    // MARK: Opening

    /// Unpacks (if needed) and opens the database. Safe to call repeatedly.
    @discardableResult
    func prepare() -> Bool {
        if db != nil { return true }
        if openFailed { return false }
        guard let meta = Self.meta,
              let packed = Bundle.main.url(forResource: "products.sqlite", withExtension: "zlib") else {
            openFailed = true
            return false
        }
        let fm = FileManager.default
        let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Products", isDirectory: true)
        let file = dir.appendingPathComponent("products-\(meta.version).sqlite")

        if !fm.fileExists(atPath: file.path) {
            do {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                let data = try (Data(contentsOf: packed) as NSData).decompressed(using: .zlib) as Data
                let tmp = dir.appendingPathComponent("unpacking.tmp")
                try data.write(to: tmp, options: .atomic)
                try fm.moveItem(at: tmp, to: file)
                var values = URLResourceValues()
                values.isExcludedFromBackup = true // it can be rebuilt from the bundle
                var f = file
                try? f.setResourceValues(values)
                // Remove databases from older app versions.
                for old in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
                where old.lastPathComponent != file.lastPathComponent {
                    try? fm.removeItem(at: old)
                }
            } catch {
                openFailed = true
                return false
            }
        }

        var handle: OpaquePointer?
        if sqlite3_open_v2(file.path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK {
            db = handle
            return true
        }
        sqlite3_close(handle)
        openFailed = true
        return false
    }

    // MARK: Queries

    /// Every word must appear in the product name or brand (case- and accent-insensitive).
    func search(_ query: String, limit: Int = 40) -> [OFFProduct] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, prepare() else { return [] }
        if q.allSatisfy(\.isNumber), (8...14).contains(q.count) {
            return product(barcode: q).map { [$0] } ?? []
        }
        let tokens = q.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .prefix(6)
            .map(String.init)
        guard !tokens.isEmpty else { return [] }

        let clause = tokens.map { _ in "search LIKE ? ESCAPE '\\'" }.joined(separator: " AND ")
        let sql = "SELECT code, name, brand, pack, kcal, p, c, f, serving FROM products WHERE \(clause) LIMIT ?"
        let binds: [Any] = tokens.map { "%" + escapeLike($0) + "%" } + [limit]
        return rows(sql, binds)
    }

    func product(barcode: String) -> OFFProduct? {
        guard prepare() else { return nil }
        let norm = OFFProduct.normalise(barcode.filter(\.isNumber))
        guard !norm.isEmpty else { return nil }
        return rows("SELECT code, name, brand, pack, kcal, p, c, f, serving FROM products WHERE norm = ? LIMIT 1", [norm]).first
    }

    // MARK: SQLite plumbing

    private func escapeLike(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    private func rows(_ sql: String, _ binds: [Any]) -> [OFFProduct] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        for (i, value) in binds.enumerated() {
            let idx = Int32(i + 1)
            if let s = value as? String {
                sqlite3_bind_text(stmt, idx, s, -1, Self.transient)
            } else if let n = value as? Int {
                sqlite3_bind_int64(stmt, idx, Int64(n))
            }
        }
        func text(_ col: Int32) -> String {
            sqlite3_column_text(stmt, col).map { String(cString: $0) } ?? ""
        }
        var out: [OFFProduct] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(OFFProduct(
                barcode: text(0), name: text(1), brand: text(2), pack: text(3),
                kcal: sqlite3_column_double(stmt, 4), p: sqlite3_column_double(stmt, 5),
                c: sqlite3_column_double(stmt, 6), f: sqlite3_column_double(stmt, 7),
                servingGrams: sqlite3_column_double(stmt, 8)))
        }
        return out
    }
}
