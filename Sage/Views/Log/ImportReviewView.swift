import SwiftUI
import SwiftData

/// Review food that Claude estimated, adjust it, then add it as quick-add entries.
struct ImportReviewView: View {
    let payload: ClaudeImport
    let defaultDate: String
    let catalog: Catalog
    @Binding var slot: Slot

    @Environment(AppState.self) private var app
    @Environment(HealthKitManager.self) private var health
    @Environment(\.modelContext) private var context
    @State private var items: [ClaudeImport.Item]
    @State private var expanded: UUID?
    @FocusState private var focused: Bool

    init(payload: ClaudeImport, defaultDate: String, catalog: Catalog, slot: Binding<Slot>) {
        self.payload = payload
        self.defaultDate = defaultDate
        self.catalog = catalog
        _slot = slot
        _items = State(initialValue: payload.items)
        _expanded = State(initialValue: payload.items.count == 1 ? payload.items[0].id : nil)
    }

    private var date: String { payload.date ?? defaultDate }

    var body: some View {
        let total = items.reduce(into: Macros()) { $0 += Macros(kcal: $1.kcal, p: $1.p, c: $1.c, f: $1.f) }

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles").foregroundStyle(Theme.accent)
                        Text("From Claude").font(.manrope(13, .bold)).foregroundStyle(Theme.accent)
                    }
                    Text(items.count == 1 ? items[0].name : "\(items.count) items")
                        .font(.manrope(24, .bold)).tracking(-0.4)
                    Text("\(dayLabel) · \(total.kcal.kcalString) kcal · \(total.p.grams) g protein. Estimates — tap an item to adjust.")
                        .font(.manrope(14)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                SlotChips(slot: $slot)

                VStack(spacing: 0) {
                    ForEach($items) { $item in
                        if item.id != items.first?.id { Divider().overlay(Theme.border) }
                        ItemRow(item: $item, expanded: expanded == item.id, focused: $focused,
                                toggle: { withAnimation(.snappy) { expanded = expanded == item.id ? nil : item.id } },
                                remove: items.count > 1 ? { withAnimation { items.removeAll { $0.id == item.id } } } : nil)
                    }
                }
                .card(padding: 0)

                let left = app.budget(on: date, health: health) - dayTotal - total.kcal
                Text("Afterwards: \(abs(left).kcalString) kcal \(left >= 0 ? "left" : "over")")
                    .font(.manrope(14, .semibold))
                    .foregroundStyle(left >= 0 ? Theme.accent : Theme.over)

                Button(items.count == 1 ? "Add to \(slot.rawValue)" : "Add \(items.count) items to \(slot.rawValue)") { add() }
                    .buttonStyle(PrimaryButtonStyle(enabled: !items.isEmpty))
                    .disabled(items.isEmpty)
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = false }
            }
        }
        .onAppear { if let s = payload.slot { slot = s } }
    }

    private var dayLabel: String {
        if date == DayKey.todayKey { return "Today" }
        if date == DayKey.key(DayKey.add(-1, to: DayKey.today)) { return "Yesterday" }
        return DayKey.short(DayKey.date(date))
    }

    private var dayTotal: Double {
        let day = date
        let descriptor = FetchDescriptor<Entry>(predicate: #Predicate<Entry> { $0.date == day })
        let entries = (try? context.fetch(descriptor)) ?? []
        return entries.reduce(0) { $0 + catalog.macros(of: $1).kcal }
    }

    private func add() {
        let time = DayKey.time(.now)
        for item in items {
            let entry = Entry(date: date, slot: slot, kind: .quick, ref: item.name, amount: 1, time: time,
                              quick: Macros(kcal: item.kcal, p: item.p, c: item.c, f: item.f))
            entry.note = item.amount
            EntryActions.add(entry, catalog: catalog, context: context, app: app, health: health)
        }
        app.showToast(items.count == 1 ? "Added \(items[0].name) to \(slot.rawValue)"
                                       : "Added \(items.count) items to \(slot.rawValue)")
        app.didLog(on: date)
        app.logRequest = nil
    }
}

private struct ItemRow: View {
    @Binding var item: ClaudeImport.Item
    var expanded: Bool
    var focused: FocusState<Bool>.Binding
    var toggle: () -> Void
    var remove: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: toggle) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name).font(.manrope(15, .semibold)).foregroundStyle(Theme.text)
                            .multilineTextAlignment(.leading)
                        Text([item.amount, "\(item.p.grams) g P · \(item.c.grams) g C · \(item.f.grams) g F"]
                                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.manrope(12, .medium)).foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 8)
                    Text(item.kcal.kcalString).font(.manrope(15, .bold)).monospacedDigit().foregroundStyle(Theme.text)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                HStack(spacing: 8) {
                    field("kcal", $item.kcal)
                    field("Protein g", $item.p)
                    field("Carbs g", $item.c)
                    field("Fat g", $item.f)
                }
                if let remove {
                    Button("Remove item", role: .destructive, action: remove)
                        .font(.manrope(13, .bold))
                        .foregroundStyle(Theme.danger)
                        .frame(minHeight: Theme.minTouch)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private func field(_ label: String, _ value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.manrope(11, .semibold)).foregroundStyle(Theme.muted)
            TextField("0", value: value, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .focused(focused)
                .font(.manrope(16, .semibold))
                .padding(.horizontal, 10)
                .frame(minHeight: 44)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        }
        .frame(maxWidth: .infinity)
    }
}
