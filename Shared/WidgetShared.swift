import Foundation
import SwiftUI
import WidgetKit

/// Shared by the app and the widget extension. The app writes a small snapshot of today
/// into the App Group container; the widget reads it.
enum SharedGroup {
    static let id = "group.com.sagegraphite.foodtracker"
    static var container: URL? { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) }
}

struct WidgetSnapshot: Codable, Equatable {
    var date: String
    var eaten: Double
    var p: Double
    var c: Double
    var f: Double
    var goalKcal: Double
    var goalP: Double
    var goalC: Double
    var goalF: Double
    /// Workout calories added to today's budget.
    var bonus: Double

    var budget: Double { goalKcal + bonus }
    var left: Double { budget - eaten }

    private static var url: URL? { SharedGroup.container?.appendingPathComponent("widget-snapshot.json") }

    static func load() -> WidgetSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func save() {
        guard let url = Self.url, let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// The snapshot as it applies to a given day: a new day starts from zero.
    func forDay(_ key: String) -> WidgetSnapshot {
        guard date != key else { return self }
        var s = self
        s.date = key
        s.eaten = 0; s.p = 0; s.c = 0; s.f = 0; s.bonus = 0
        return s
    }

    static func dayKey(_ date: Date = .now) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    static let placeholder = WidgetSnapshot(date: dayKey(), eaten: 1240, p: 112, c: 111, f: 37,
                                            goalKcal: 1800, goalP: 150, goalC: 170, goalF: 60, bonus: 460)
}

/// Deep links the widget buttons open.
enum SageLink {
    static let day = URL(string: "sage://day")!
    static let log = URL(string: "sage://log")!
    static let scan = URL(string: "sage://scan")!
    static let claude = URL(string: "sage://claude")!
}
