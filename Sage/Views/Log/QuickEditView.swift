import SwiftUI
import SwiftData

/// Edit a quick-add entry (from Claude, the old app, or Quick add): name, amount,
/// calories and macros, meal, and optionally save it as one of your foods.
struct QuickEditView: View {
    let entry: Entry
    let catalog: Catalog
    let baseTotals: Macros
    @Binding var slot: Slot

    @Environment(AppState.self) private var app
    @Environment(HealthKitManager.self) private var health
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var note: String
    @State private var kcal: String
    @State private var p: String
    @State private var c: String
    @State private var f: String
    @State private var saveToFoods = false
    @FocusState private var focused: Bool

    init(entry: Entry, catalog: Catalog, baseTotals: Macros, slot: Binding<Slot>) {
        self.entry = entry
        self.catalog = catalog
        self.baseTotals = baseTotals
        _slot = slot
        let m = entry.quickMacros * entry.amount
        func s(_ v: Double) -> String { v == 0 ? "" : v.clean }
        _name = State(initialValue: catalog.name(of: entry))
        _note = State(initialValue: entry.note ?? "")
        _kcal = State(initialValue: s((m.kcal).rounded()))
        _p = State(initialValue: s((m.p * 10).rounded() / 10))
        _c = State(initialValue: s((m.c * 10).rounded() / 10))
        _f = State(initialValue: s((m.f * 10).rounded() / 10))
    }

    private var macros: Macros {
        Macros(kcal: FoodFormView.num(kcal), p: FoodFormView.num(p), c: FoodFormView.num(c), f: FoodFormView.num(f))
    }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    private var valid: Bool { !trimmedName.isEmpty && macros.kcal > 0 }

    var body: some View {
        let after = baseTotals + macros
        let left = app.budget(on: entry.date, health: health) - after.kcal

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Edit food").font(.manrope(24, .bold)).tracking(-0.4)
                    Text(DayKey.date(entry.date).formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                        .font(.manrope(13, .medium)).foregroundStyle(Theme.muted)
                }
                field("Name", text: $name, placeholder: "e.g. Chicken katsu curry", numeric: false)
                field("Amount (optional)", text: $note, placeholder: "e.g. 1 regular", numeric: false)
                HStack(spacing: 8) {
                    field("kcal", text: $kcal, placeholder: "0", numeric: true)
                    field("Protein g", text: $p, placeholder: "0", numeric: true)
                    field("Carbs g", text: $c, placeholder: "0", numeric: true)
                    field("Fat g", text: $f, placeholder: "0", numeric: true)
                }
                SlotChips(slot: $slot)
                Text("Afterwards: \(abs(left).kcalString) kcal \(left >= 0 ? "left" : "over") · \(after.p.grams) / \(app.goals.p.grams) g protein")
                    .font(.manrope(14, .semibold))
                    .foregroundStyle(left >= 0 ? Theme.accent : Theme.over)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.chip, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Toggle(isOn: $saveToFoods) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Save to my foods").font(.manrope(14, .bold))
                        Text("So you can log it again from Foods").font(.manrope(12, .medium)).foregroundStyle(Theme.muted)
                    }
                }
                .tint(Theme.switchOn)
                .padding(.horizontal, 14)
                .frame(minHeight: 58)
                .card(padding: 0)

                Button("Save changes") { save() }
                    .buttonStyle(PrimaryButtonStyle(enabled: valid))
                    .disabled(!valid)
                Button("Delete entry", role: .destructive) {
                    EntryActions.delete(entry, context: context, app: app, health: health)
                    app.showToast("Entry deleted")
                    app.logRequest = nil
                }
                .font(.manrope(16, .bold))
                .foregroundStyle(Theme.danger)
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } }
            ToolbarItem(placement: .topBarTrailing) {
                Text("Editing · \(slot.rawValue)").font(.manrope(13, .semibold)).foregroundStyle(Theme.muted)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = false }
            }
        }
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String, numeric: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.manrope(12, .semibold)).foregroundStyle(Theme.muted)
            TextField(placeholder, text: text)
                .font(.manrope(16, .bold))
                .keyboardType(numeric ? .decimalPad : .default)
                .focused($focused)
                .padding(.horizontal, 12)
                .frame(minHeight: 46)
                .background(Theme.field, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        }
        .frame(maxWidth: .infinity)
    }

    private func save() {
        guard valid else { return }
        let m = macros
        let label = note.trimmingCharacters(in: .whitespaces)
        entry.ref = trimmedName
        entry.note = label.isEmpty ? nil : label
        entry.amount = 1
        entry.quickKcal = m.kcal
        entry.quickP = m.p
        entry.quickC = m.c
        entry.quickF = m.f
        entry.slot = slot
        EntryActions.update(entry, catalog: catalog, context: context, app: app, health: health)
        if saveToFoods {
            let food = Food(id: "c" + UUID().uuidString, name: trimmedName, unit: "serving", per: 1, step: 0.5, def: 1,
                            kcal: m.kcal, p: m.p, c: m.c, f: m.f, source: .custom)
            context.insert(food)
            try? context.save()
            app.showToast("Saved · \(trimmedName) added to your foods")
        } else {
            app.showToast("Entry updated")
        }
        app.logRequest = nil
    }
}
