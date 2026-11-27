import WidgetKit
import SwiftUI

@main
struct SageWidgets: WidgetBundle {
    var body: some Widget {
        TodayWidget()
    }
}

// MARK: - Timeline

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

/// Shows the app's latest snapshot, then a fresh day from midnight.
/// The app asks for a reload whenever the log changes.
struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        let snap = context.isPreview ? WidgetSnapshot.placeholder : (WidgetSnapshot.load() ?? .placeholder)
        completion(SnapshotEntry(date: .now, snapshot: snap.forDay(WidgetSnapshot.dayKey())))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let now = Date()
        let snap = WidgetSnapshot.load() ?? .placeholder
        let midnight = Calendar.current.startOfDay(for: now).addingTimeInterval(24 * 3600 + 5)
        let entries = [
            SnapshotEntry(date: now, snapshot: snap.forDay(WidgetSnapshot.dayKey(now))),
            SnapshotEntry(date: midnight, snapshot: snap.forDay(WidgetSnapshot.dayKey(midnight))),
        ]
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(30 * 60))))
    }
}

// MARK: - Widget

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SageToday", provider: SnapshotProvider()) { entry in
            TodayWidgetView(snap: entry.snapshot)
                .containerBackground(Palette.card, for: .widget)
                .widgetURL(SageLink.day)
        }
        .configurationDisplayName("Today")
        .description("Calories left, macros, and quick ways to log food.")
        .supportedFamilies([.systemMedium])
    }
}

/// Sage Graphite, light. Fixed colours so the widget always looks the same.
private enum Palette {
    static let card = Color(red: 0xFB / 255, green: 0xF9 / 255, blue: 0xF5 / 255)
    static let text = Color(red: 0x1E / 255, green: 0x2A / 255, blue: 0x23 / 255)
    static let muted = Color(red: 0x5F / 255, green: 0x6A / 255, blue: 0x63 / 255)
    static let track = Color(red: 0xE7 / 255, green: 0xE1 / 255, blue: 0xD6 / 255)
    static let accent = Color(red: 0x2F / 255, green: 0x5D / 255, blue: 0x46 / 255)
    static let accentLight = Color(red: 0x4F / 255, green: 0x8A / 255, blue: 0x6A / 255)
    static let carbs = Color(red: 0xB9 / 255, green: 0x82 / 255, blue: 0x3A / 255)
    static let fat = Color(red: 0x94 / 255, green: 0x65 / 255, blue: 0x8A / 255)
    static let over = Color(red: 0xB9 / 255, green: 0x82 / 255, blue: 0x3A / 255)
}

private func manrope(_ size: CGFloat, _ weight: String) -> Font {
    .custom("Manrope-\(weight)", size: size)
}

private func number(_ v: Double) -> String { Int(v.rounded()).formatted() }

struct TodayWidgetView: View {
    let snap: WidgetSnapshot

    var body: some View {
        let over = snap.left < 0
        VStack(alignment: .leading, spacing: 0) {
            // Kcal left and eaten / budget
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(number(abs(snap.left)))
                    .font(manrope(34, "ExtraBold"))
                    .tracking(-1)
                    .foregroundStyle(over ? Palette.over : Palette.text)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text(over ? "KCAL OVER" : "KCAL LEFT")
                    .font(manrope(11, "Bold")).tracking(0.6)
                    .foregroundStyle(Palette.muted)
                Spacer(minLength: 4)
                Text("\(number(snap.eaten)) / \(number(snap.budget))")
                    .font(manrope(11, "SemiBold"))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
            }

            // Calorie bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.track)
                    Capsule()
                        .fill(over ? AnyShapeStyle(Palette.over)
                                   : AnyShapeStyle(LinearGradient(colors: [Palette.accent, Palette.accentLight],
                                                                  startPoint: .leading, endPoint: .trailing)))
                        .frame(width: geo.size.width * min(1, snap.budget > 0 ? snap.eaten / snap.budget : 0))
                }
            }
            .frame(height: 10)
            .padding(.top, 6)

            // Macros
            HStack(spacing: 10) {
                MacroMini(name: "Protein", value: snap.p, goal: snap.goalP, color: Palette.accent)
                MacroMini(name: "Carbs", value: snap.c, goal: snap.goalC, color: Palette.carbs)
                MacroMini(name: "Fat", value: snap.f, goal: snap.goalF, color: Palette.fat)
            }
            .padding(.top, 10)

            Spacer(minLength: 6)

            // Log your food
            HStack(spacing: 8) {
                Text(snap.bonus >= 1 ? "+\(number(snap.bonus)) FROM WORKOUTS" : "LOG YOUR FOOD")
                    .font(manrope(10.5, "Bold")).tracking(0.6)
                    .foregroundStyle(snap.bonus >= 1 ? Palette.accent : Palette.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Link(destination: SageLink.claude) { roundButton("sparkles", filled: false) }
                Link(destination: SageLink.scan) { roundButton("barcode.viewfinder", filled: false) }
                Link(destination: SageLink.log) { roundButton("plus", filled: true) }
            }
        }
    }

    private func roundButton(_ symbol: String, filled: Bool) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(filled ? Color.white : Palette.accent)
            .frame(width: 30, height: 30)
            .background(filled ? Palette.accent : Palette.accent.opacity(0.1), in: Circle())
    }
}

private struct MacroMini: View {
    var name: String
    var value: Double
    var goal: Double
    var color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 2) {
                Text(name).font(manrope(10.5, "SemiBold")).foregroundStyle(Palette.muted)
                Spacer(minLength: 2)
                Text("\(number(value))").font(manrope(10.5, "ExtraBold")).foregroundColor(Palette.text)
                + Text("/\(number(goal))g").font(manrope(10, "SemiBold")).foregroundColor(Palette.muted)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.track)
                    Capsule().fill(color).frame(width: geo.size.width * (goal > 0 ? min(1, value / goal) : 0))
                }
            }
            .frame(height: 5)
        }
    }
}
