import WidgetKit
import SwiftUI
import AppIntents

@main
struct SageWidgets: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        FavouritesWidget()
    }
}

// MARK: - Timeline

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

/// Shows the app's latest snapshot, then resets to a fresh day at midnight.
struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        let snap = context.isPreview ? .placeholder : (WidgetSnapshot.load() ?? .placeholder)
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
        // The app also asks for a reload whenever the log changes.
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(30 * 60))))
    }
}

// MARK: - Today widget

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SageToday", provider: SnapshotProvider()) { entry in
            TodayWidgetView(snap: entry.snapshot)
                .containerBackground(WidgetPalette.background, for: .widget)
                .widgetURL(URL(string: "sage://day"))
        }
        .configurationDisplayName("Today")
        .description("Calories left and today's protein, carbs and fat.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct TodayWidgetView: View {
    let snap: WidgetSnapshot
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemMedium: medium
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .accessoryInline: inline
        default: small
        }
    }

    private var leftColor: Color { snap.left >= 0 ? WidgetPalette.accent : WidgetPalette.over }
    private var leftLabel: String { snap.left >= 0 ? "kcal left" : "kcal over" }

    private var small: some View {
        VStack(spacing: 8) {
            Ring(eaten: snap.eaten, budget: snap.budget, size: 86, line: 9) {
                VStack(spacing: 0) {
                    Text(kcal(abs(snap.left))).font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(leftColor).minimumScaleFactor(0.6).lineLimit(1)
                    Text(leftLabel).font(.system(size: 10, weight: .semibold)).foregroundStyle(WidgetPalette.muted)
                }
            }
            HStack(spacing: 4) {
                Circle().fill(WidgetPalette.accent).frame(width: 6, height: 6)
                Text("\(Int(snap.p.rounded())) / \(Int(snap.goalP)) g protein")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(WidgetPalette.text)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
        }
    }

    private var medium: some View {
        HStack(spacing: 16) {
            Ring(eaten: snap.eaten, budget: snap.budget, size: 110, line: 11) {
                VStack(spacing: 0) {
                    Text(kcal(abs(snap.left))).font(.system(size: 24, weight: .heavy, design: .rounded))
                        .foregroundStyle(leftColor).minimumScaleFactor(0.6).lineLimit(1)
                    Text(leftLabel).font(.system(size: 11, weight: .semibold)).foregroundStyle(WidgetPalette.muted)
                }
            }
            VStack(alignment: .leading, spacing: 9) {
                Text("\(kcal(snap.eaten)) of \(kcal(snap.budget)) kcal\(snap.bonus >= 1 ? " · +\(kcal(snap.bonus)) workouts" : "")")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(WidgetPalette.muted)
                    .lineLimit(1).minimumScaleFactor(0.7)
                MacroLine(name: "Protein", value: snap.p, goal: snap.goalP, color: WidgetPalette.accent)
                MacroLine(name: "Carbs", value: snap.c, goal: snap.goalC, color: WidgetPalette.carbs)
                MacroLine(name: "Fat", value: snap.f, goal: snap.goalF, color: WidgetPalette.fat)
            }
        }
    }

    private var circular: some View {
        Gauge(value: min(max(snap.eaten / max(snap.budget, 1), 0), 1)) {
            Image(systemName: "fork.knife")
        } currentValueLabel: {
            Text(kcalShort(abs(snap.left)))
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(kcal(abs(snap.left))) \(leftLabel)").font(.headline).widgetAccentable()
            Text("\(Int(snap.p.rounded())) / \(Int(snap.goalP)) g protein").font(.caption)
            Gauge(value: min(max(snap.eaten / max(snap.budget, 1), 0), 1)) { EmptyView() }
                .gaugeStyle(.accessoryLinearCapacity)
        }
    }

    private var inline: some View {
        Text("\(kcal(abs(snap.left))) \(leftLabel) · \(Int(snap.p.rounded()))g P")
    }
}

// MARK: - Favourites widget

struct FavouritesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SageFavourites", provider: SnapshotProvider()) { entry in
            FavouritesWidgetView(snap: entry.snapshot)
                .containerBackground(WidgetPalette.background, for: .widget)
                .widgetURL(URL(string: "sage://day"))
        }
        .configurationDisplayName("Log a favourite")
        .description("Your starred meals. Tap + to log one without opening Sage.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct FavouritesWidgetView: View {
    let snap: WidgetSnapshot
    @Environment(\.widgetFamily) private var family

    private var maxRows: Int { family == .systemLarge ? 6 : 3 }

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemLarge ? 8 : 5) {
            HStack(alignment: .firstTextBaseline) {
                Text("Add to \(WidgetSlot.suggested())").font(.system(size: 13, weight: .bold)).foregroundStyle(WidgetPalette.text)
                Spacer()
                Text("\(kcal(abs(snap.left))) \(snap.left >= 0 ? "left" : "over")")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(snap.left >= 0 ? WidgetPalette.accent : WidgetPalette.over)
            }
            if let last = snap.lastLogged {
                Label("Logged \(last)", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(WidgetPalette.accent)
                    .lineLimit(1)
            }
            if snap.favourites.isEmpty {
                Spacer()
                Text("Star meals in Sage (Meals tab, ☆) to log them from here.")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(WidgetPalette.muted)
                Spacer()
            } else {
                ForEach(snap.favourites.prefix(maxRows)) { meal in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(meal.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(WidgetPalette.text)
                                .lineLimit(1)
                            Text("\(kcal(meal.kcal)) kcal · \(Int(meal.p.rounded())) g P")
                                .font(.system(size: 10, weight: .medium)).foregroundStyle(WidgetPalette.muted)
                        }
                        Spacer(minLength: 4)
                        Button(intent: LogFavouriteIntent(mealId: meal.id)) {
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(WidgetPalette.onAccent)
                                .frame(width: 30, height: 30)
                                .background(WidgetPalette.accent, in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Pieces

private struct Ring<Center: View>: View {
    var eaten: Double
    var budget: Double
    var size: CGFloat
    var line: CGFloat
    @ViewBuilder var center: Center

    var body: some View {
        let over = eaten > budget
        ZStack {
            Circle().stroke(WidgetPalette.track, lineWidth: line)
            Circle()
                .trim(from: 0, to: budget > 0 ? min(1, eaten / budget) : 0)
                .stroke(over ? WidgetPalette.over : WidgetPalette.accent,
                        style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
            center
        }
        .frame(width: size, height: size)
    }
}

private struct MacroLine: View {
    var name: String
    var value: Double
    var goal: Double
    var color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(name).font(.system(size: 11, weight: .semibold)).foregroundStyle(WidgetPalette.muted)
                Spacer()
                Text("\(Int(value.rounded())) / \(Int(goal)) g").font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(WidgetPalette.text)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(WidgetPalette.track)
                    Capsule().fill(color).frame(width: geo.size.width * (goal > 0 ? min(1, value / goal) : 0))
                }
            }
            .frame(height: 6)
        }
    }
}

private func kcal(_ v: Double) -> String { Int(v.rounded()).formatted() }
private func kcalShort(_ v: Double) -> String {
    v >= 1000 ? String(format: "%.1fk", v / 1000) : String(Int(v.rounded()))
}
