import SwiftUI
import SwiftData

struct DayView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        // Re-create the inner view when the day changes so its @Query filters on that day.
        DayContent(dayKey: DayKey.key(app.dayDate))
            .id(app.dayOffset)
    }
}

private struct DayContent: View {
    @Environment(AppState.self) private var app
    let dayKey: String
    @Query private var entries: [Entry]
    @Query private var foods: [Food]
    @Query private var meals: [Meal]

    init(dayKey: String) {
        self.dayKey = dayKey
        _entries = Query(filter: #Predicate<Entry> { $0.date == dayKey }, sort: \Entry.time)
    }

    var body: some View {
        let catalog = Catalog(foods: foods, meals: meals)
        let total = entries.reduce(into: Macros()) { $0 += catalog.macros(of: $1) }
        let date = app.dayDate

        ScrollView {
            VStack(spacing: Theme.gap) {
                PageHeader(eyebrow: DayKey.weekday(date), title: title(date)) {
                    PrevNextButtons(canGoNext: app.dayOffset < 0, prevLabel: "Previous day", nextLabel: "Next day",
                                    prev: { app.dayOffset -= 1 },
                                    next: { if app.dayOffset < 0 { app.dayOffset += 1 } })
                }
                SummaryCard(title: "Summary", totals: total, goals: app.goals)
                ForEach(Slot.allCases) { slot in
                    SlotCard(slot: slot, entries: entries.filter { $0.slot == slot }, catalog: catalog)
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
    }

    private func title(_ date: Date) -> String {
        switch app.dayOffset {
        case 0: return "Today"
        case -1: return "Yesterday"
        default: return DayKey.short(date)
        }
    }
}

private struct SlotCard: View {
    @Environment(AppState.self) private var app
    @Environment(HealthKitManager.self) private var health
    @Environment(\.modelContext) private var context
    var slot: Slot
    var entries: [Entry]
    var catalog: Catalog

    var body: some View {
        let sub = entries.reduce(into: Macros()) { $0 += catalog.macros(of: $1) }
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(slot.rawValue).font(.manrope(17, .bold))
                    Text(entries.isEmpty ? "Nothing logged" : "\(sub.kcal.kcalString) kcal · \(sub.p.grams) g protein")
                        .font(.manrope(13, .medium)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Button { app.openLog(slot: slot) } label: { Image(systemName: "plus") }
                    .buttonStyle(CircleIconButtonStyle())
                    .accessibilityLabel("Add to \(slot.rawValue)")
            }
            .padding(16)

            ForEach(entries) { e in
                Divider().overlay(Theme.border).padding(.horizontal, 16)
                SwipeToDelete(onDelete: { delete(e) }) {
                    Button { app.openEdit(e) } label: {
                        let m = catalog.macros(of: e)
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(catalog.name(of: e)).font(.manrope(15, .semibold)).lineLimit(1)
                                Text("\(e.time) · \(catalog.amountLabel(of: e))")
                                    .font(.manrope(12, .medium)).foregroundStyle(Theme.muted).lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(m.kcal.kcalString).font(.manrope(15, .bold)).monospacedDigit()
                                Text("\(m.p.grams) g P").font(.manrope(12, .semibold)).foregroundStyle(Theme.accent)
                            }
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 58)
                }
                .buttonStyle(PressableStyle())
                .accessibilityHint("Edit, or swipe left to delete")
                }
            }
        }
        .padding(.bottom, entries.isEmpty ? 0 : 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
    }

    private func delete(_ entry: Entry) {
        EntryActions.delete(entry, context: context, app: app, health: health)
        app.showToast("Entry deleted")
    }
}
