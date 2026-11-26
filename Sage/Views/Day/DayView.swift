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
    @Environment(HealthKitManager.self) private var health
    let dayKey: String
    @Query private var entries: [Entry]
    @Query private var previous: [Entry]
    @Query private var foods: [Food]
    @Query private var meals: [Meal]

    init(dayKey: String) {
        self.dayKey = dayKey
        _entries = Query(filter: #Predicate<Entry> { $0.date == dayKey }, sort: \Entry.time)
        let prevKey = DayKey.key(DayKey.add(-1, to: DayKey.date(dayKey)))
        _previous = Query(filter: #Predicate<Entry> { $0.date == prevKey }, sort: \Entry.time)
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
                SummaryCard(title: "Summary", totals: total, goals: app.goals,
                            bonus: app.workoutBonus(on: dayKey, health: health))
                ForEach(Slot.allCases) { slot in
                    SlotCard(slot: slot, dayKey: dayKey,
                             entries: entries.filter { $0.slot == slot },
                             previous: previous.filter { $0.slot == slot },
                             catalog: catalog)
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .task(id: dayKey) {
            if app.showsWorkouts { await health.loadWorkouts(on: dayKey) }
        }
    }

    private func title(_ date: Date) -> String {
        switch app.dayOffset {
        case 0: return "Today"
        case -1: return "Yesterday"
        default: return DayKey.short(date)
        }
    }
}

private struct SaveMealRequest: Identifiable {
    let id = UUID()
    var entries: [Entry]
}

private struct SlotCard: View {
    @Environment(AppState.self) private var app
    @Environment(HealthKitManager.self) private var health
    @Environment(\.modelContext) private var context
    var slot: Slot
    var dayKey: String
    var entries: [Entry]
    /// The same slot on the day before, for "Same as yesterday?".
    var previous: [Entry]
    var catalog: Catalog

    @State private var saveRequest: SaveMealRequest?
    @State private var copying = false
    @State private var hideSuggestion = false

    private var isToday: Bool { dayKey == DayKey.todayKey }

    var body: some View {
        let sub = entries.reduce(into: Macros()) { $0 += catalog.macros(of: $1) }
        VStack(alignment: .leading, spacing: 8) {
            // Section label above the card: meal name, totals and the ⋯ menu.
            HStack(alignment: .center) {
                Text(slot.rawValue.uppercased())
                    .font(.manrope(13, .heavy))
                    .tracking(1)
                    .foregroundStyle(Theme.muted)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if !entries.isEmpty {
                    Text("\(sub.kcal.kcalString) kcal · \(sub.p.grams) g P")
                        .font(.manrope(13, .semibold))
                        .foregroundStyle(Theme.muted)
                        .monospacedDigit()
                    Menu {
                        if !isToday {
                            Button { copy(entries, to: DayKey.todayKey) } label: {
                                Label("Add \(slot.rawValue.lowercased()) to today", systemImage: "arrow.uturn.forward")
                            }
                        }
                        Button { saveRequest = SaveMealRequest(entries: entries) } label: {
                            Label("Save as a meal", systemImage: "star")
                        }
                        Button { copying = true } label: {
                            Label("Copy to another day…", systemImage: "calendar")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Theme.muted)
                            .frame(width: 36, height: 28)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("\(slot.rawValue) options")
                }
            }
            .padding(.leading, 4)
            .padding(.trailing, entries.isEmpty ? 4 : -4)
            .padding(.top, 6)
            .frame(minHeight: 28)

            // The card holds only food, then an "Add to …" row.
            VStack(spacing: 0) {
                ForEach(entries) { e in
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
                            .frame(minHeight: 60)
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityHint("Edit, or swipe left to delete")
                        .contextMenu {
                            Button { copy([e], to: DayKey.todayKey) } label: {
                                Label(isToday ? "Log again" : "Add to today", systemImage: "arrow.uturn.forward")
                            }
                            Button { saveRequest = SaveMealRequest(entries: [e]) } label: {
                                Label("Save as a meal", systemImage: "star")
                            }
                            Button(role: .destructive) { delete(e) } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                    Divider().overlay(Theme.border).padding(.horizontal, 16)
                }

                if entries.isEmpty && !previous.isEmpty && !hideSuggestion {
                    suggestion
                }

                Button { app.openLog(slot: slot) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .bold))
                            .frame(width: 26, height: 26)
                            .background(Theme.accent.opacity(0.1), in: Circle())
                        Text("Add to \(slot.rawValue)").font(.manrope(15, .bold))
                        Spacer()
                    }
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 52)
                }
                .buttonStyle(PressableStyle())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        }
        .sheet(item: $saveRequest) { req in
            NavigationStack {
                MealEditorView(meal: nil,
                               initialParts: MealActions.draftParts(from: req.entries, catalog: catalog),
                               suggestedName: suggestedName(req.entries),
                               catalog: catalog) { _ in saveRequest = nil }
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) { Button("Cancel") { saveRequest = nil } }
                    }
            }
            .presentationBackground(Theme.background)
        }
        .sheet(isPresented: $copying) {
            CopyToDaySheet(entries: entries, slot: slot, fromDay: dayKey, catalog: catalog)
                .presentationDetents([.large])
                .presentationBackground(Theme.background)
        }
    }

    /// "Same as yesterday?" — one tap repeats the previous day's items in this slot.
    private var suggestion: some View {
        let total = previous.reduce(into: Macros()) { $0 += catalog.macros(of: $1) }
        let names = previous.map { catalog.name(of: $0) }
        let title = names.count == 1 ? names[0] : "\(names[0]) + \(names.count - 1) more"
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Label(isToday ? "Same as yesterday?" : "Same as the day before?", systemImage: "arrow.uturn.forward")
                    .font(.manrope(12, .bold)).foregroundStyle(Theme.accent)
                Text(title).font(.manrope(15, .semibold)).lineLimit(1)
                Text("\(total.kcal.kcalString) kcal · \(total.p.grams) g P")
                    .font(.manrope(12, .medium)).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 8)
            Button { copy(previous, to: dayKey) } label: {
                Text("Add")
                    .font(.manrope(14, .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 36)
                    .background(Theme.accent, in: Capsule())
                    .frame(minHeight: Theme.minTouch)
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Add \(title) to \(slot.rawValue)")
            Button { withAnimation { hideSuggestion = true } } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 28, height: Theme.minTouch)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Hide suggestion")
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .padding(.vertical, 6)
        .background(Theme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Theme.accent.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        .padding(8)
    }

    private func suggestedName(_ entries: [Entry]) -> String {
        let names = entries.map { catalog.name(of: $0) }
        return names.prefix(3).joined(separator: " + ")
    }

    private func copy(_ items: [Entry], to day: String) {
        EntryActions.copy(items, to: day, slot: slot, catalog: catalog, context: context, app: app, health: health)
        let what = items.count == 1 ? catalog.name(of: items[0]) : "\(items.count) items"
        app.showToast(day == DayKey.todayKey && !isToday ? "Added \(what) to today" : "Added \(what) to \(slot.rawValue)")
    }

    private func delete(_ entry: Entry) {
        EntryActions.delete(entry, context: context, app: app, health: health)
        app.showToast("Entry deleted")
    }
}

/// Copy a slot's items to another day (and slot).
private struct CopyToDaySheet: View {
    let entries: [Entry]
    let fromDay: String
    let catalog: Catalog

    @Environment(AppState.self) private var app
    @Environment(HealthKitManager.self) private var health
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var date = DayKey.today
    @State private var slot: Slot

    init(entries: [Entry], slot: Slot, fromDay: String, catalog: Catalog) {
        self.entries = entries
        self.fromDay = fromDay
        self.catalog = catalog
        _slot = State(initialValue: slot)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Copy to another day").font(.manrope(22, .bold))
                    Spacer()
                    Button("Cancel") { dismiss() }.font(.manrope(16, .semibold)).frame(minHeight: Theme.minTouch)
                }
                Text(entries.map { catalog.name(of: $0) }.joined(separator: " · "))
                    .font(.manrope(14)).foregroundStyle(Theme.muted)
                DatePicker("Day", selection: $date, in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(Theme.accent)
                    .card(padding: 8)
                SlotChips(slot: $slot)
                Button("Copy \(entries.count == 1 ? "item" : "\(entries.count) items") to \(slot.rawValue)") {
                    let day = DayKey.key(date)
                    EntryActions.copy(entries, to: day, slot: slot, catalog: catalog, context: context, app: app, health: health)
                    app.showToast("Copied to \(day == DayKey.todayKey ? "today" : DayKey.short(date))")
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(Theme.pagePadding)
        }
    }
}
