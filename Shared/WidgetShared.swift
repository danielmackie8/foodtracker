import Foundation
import SwiftUI
import UIKit
import WidgetKit

/// Code shared by the app and the widget extension.
/// They exchange data through the App Group container:
///  - the app writes a small snapshot of today (totals, budget, favourites) for the widgets to show;
///  - widget buttons append "pending logs", which the app turns into real entries when it next opens.
enum SharedGroup {
    static let id = "group.com.sagegraphite.foodtracker"
    static var container: URL? { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) }
}

struct WidgetFavourite: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var kcal: Double
    var p: Double
    var c: Double
    var f: Double
}

struct WidgetSnapshot: Codable {
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
    var favourites: [WidgetFavourite]
    var lastLogged: String?
    var updated: Date

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
        s.eaten = 0; s.p = 0; s.c = 0; s.f = 0; s.bonus = 0; s.lastLogged = nil
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

    static let placeholder = WidgetSnapshot(
        date: dayKey(), eaten: 1240, p: 112, c: 111, f: 37, goalKcal: 1800, goalP: 150, goalC: 170, goalF: 60,
        bonus: 460,
        favourites: [WidgetFavourite(id: "shake", name: "Whey shake", kcal: 120, p: 24, c: 3, f: 2),
                     WidgetFavourite(id: "eggs", name: "Poached eggs & sourdough", kcal: 428, p: 31, c: 28, f: 21),
                     WidgetFavourite(id: "mincerice", name: "Mince & rice", kcal: 606, p: 58, c: 59, f: 15)],
        lastLogged: nil, updated: .now)
}

/// A meal logged from a widget, waiting for the app to add it to the food log.
struct PendingLog: Codable, Identifiable {
    var id: UUID
    var mealId: String
    var date: String
    var slot: String
    var time: String
}

enum PendingLogs {
    private static var url: URL? { SharedGroup.container?.appendingPathComponent("pending-logs.json") }

    static func load() -> [PendingLog] {
        guard let url, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([PendingLog].self, from: data)) ?? []
    }

    static func append(_ log: PendingLog) {
        write(load() + [log])
    }

    /// Removes the logs the app has added (by id), keeping any that arrived meanwhile.
    static func remove(_ ids: Set<UUID>) {
        write(load().filter { !ids.contains($0.id) })
    }

    private static func write(_ logs: [PendingLog]) {
        guard let url, let data = try? JSONEncoder().encode(logs) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

enum WidgetSlot {
    /// Same cut-offs as the app: Breakfast < 10:30 < Lunch < 15:00 < Snack < 17:30 < Dinner.
    static func suggested(_ date: Date = .now) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        let h = Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
        if h < 10.5 { return "Breakfast" }
        if h < 15 { return "Lunch" }
        if h < 17.5 { return "Snack" }
        return "Dinner"
    }
}

/// Sage Graphite colours for the widgets (light and dark).
enum WidgetPalette {
    static let background = dynamic(0xF6F3EE, 0x101613)
    static let card = dynamic(0xFBF9F5, 0x19211D)
    static let text = dynamic(0x1E2A23, 0xE8EDE9)
    static let muted = dynamic(0x5F6A63, 0x9AA69F)
    static let track = dynamic(0xE7E1D6, 0x2A3530)
    static let accent = dynamic(0x2F5D46, 0x7DBB97)
    static let carbs = dynamic(0xB9823A, 0xDDA55E)
    static let fat = dynamic(0x94658A, 0xC495B9)
    static let over = dynamic(0xB9823A, 0xDDA55E)
    static let onAccent = dynamic(0xFFFFFF, 0x0F1A14)

    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { trait in
            let hex = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}
