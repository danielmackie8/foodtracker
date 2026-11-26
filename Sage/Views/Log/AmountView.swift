import SwiftUI
import SwiftData

enum AmountTarget {
    case food(Food)
    case meal(Meal)
    case quick(name: String, macros: Macros)

    init(entry: Entry, catalog: Catalog) {
        switch entry.kind {
        case .quick:
            self = .quick(name: catalog.name(of: entry), macros: entry.quickMacros)
        case .meal:
            if let m = catalog.meals[entry.ref] { self = .meal(m) } else { self = .quick(name: "Deleted meal", macros: .zero) }
        case .food:
            if let f = catalog.foods[entry.ref] { self = .food(f) } else { self = .quick(name: "Unknown food", macros: .zero) }
        }
    }
}

/// Amount screen: stepper, live macros, and what's left afterwards.
/// Also used to edit (amount or slot) or delete an existing entry.
struct AmountView: View {
    let target: AmountTarget
    let editing: Entry?
    let catalog: Catalog
    let baseTotals: Macros
    let date: String
    @Binding var slot: Slot

    @Environment(AppState.self) private var app
    @Environment(HealthKitManager.self) private var health
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var qty: Double
    @FocusState private var qtyFocused: Bool

    init(target: AmountTarget, editing: Entry?, catalog: Catalog, baseTotals: Macros, date: String, slot: Binding<Slot>) {
        self.target = target
        self.editing = editing
        self.catalog = catalog
        self.baseTotals = baseTotals
        self.date = date
        self._slot = slot
        let initial: Double
        if let editing { initial = editing.amount }
        else if case .food(let f) = target { initial = f.def }
        else { initial = 1 }
        _qty = State(initialValue: initial)
    }

    private var step: Double {
        if case .food(let f) = target { return f.step > 0 ? f.step : 1 }
        return 0.5
    }

    private var name: String {
        switch target {
        case .food(let f): return f.name
        case .meal(let m): return m.name
        case .quick(let name, _): return name
        }
    }

    private var subtitle: String {
        switch target {
        case .meal(let m): return "\(m.desc) per serving"
        case .quick(_, let m): return "Quick add · \(m.kcal.kcalString) kcal each"
        case .food(let f):
            if f.source == .off {
                var parts = [f.brand, f.pack].compactMap { $0 }.filter { !$0.isEmpty }
                parts.append("\(f.kcal.clean) kcal per 100g")
                if let s = f.servingGrams { parts.append("1 serving = \(s.clean)g") }
                return parts.joined(separator: " · ")
            }
            return "\(f.kcal.clean) kcal per \(f.perLabel)" + (f.dry ? " · weigh it dry, before cooking" : "")
        }
    }

    private var unitLabel: String {
        switch target {
        case .meal, .quick: return qty == 1 ? "serving" : "servings"
        case .food(let f):
            switch f.unit {
            case "g": return f.dry ? "grams, dry" : "grams"
            case "ml": return "millilitres"
            default: return f.unit + (qty == 1 ? "" : "s")
            }
        }
    }

    private var macros: Macros {
        switch target {
        case .food(let f): return f.macros(for: qty)
        case .meal(let m): return catalog.macros(of: m) * qty
        case .quick(_, let m): return m * qty
        }
    }

    var body: some View {
        let m = macros
        let after = baseTotals + m
        let left = app.budget(on: date, health: health) - after.kcal

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(name).font(.manrope(24, .bold)).tracking(-0.4)
                    Text(subtitle).font(.manrope(14)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                SlotChips(slot: $slot)

                // Stepper
                HStack {
                    Button { change(-1) } label: { Image(systemName: "minus") }
                        .buttonStyle(BigStepStyle())
                        .accessibilityLabel("Less")
                    Spacer()
                    VStack(spacing: 2) {
                        TextField("0", value: $qty, format: .number.precision(.fractionLength(0...2)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.center)
                            .focused($qtyFocused)
                            .bigNumber(40)
                            .frame(maxWidth: 160)
                        Text(unitLabel).font(.manrope(13, .medium)).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Button { change(1) } label: { Image(systemName: "plus") }
                        .buttonStyle(BigStepStyle())
                        .accessibilityLabel("More")
                }
                .sensoryFeedback(.selection, trigger: qty)
                .padding(.vertical, 8)

                // Live macros
                HStack(spacing: 8) {
                    MacroTile(value: m.kcal.kcalString, label: "kcal", color: Theme.text)
                    MacroTile(value: "\(m.p.grams)g", label: "protein", color: Theme.accent)
                    MacroTile(value: "\(m.c.grams)g", label: "carbs", color: Theme.text)
                    MacroTile(value: "\(m.f.grams)g", label: "fat", color: Theme.text)
                }

                Text("Afterwards: \(abs(left).kcalString) kcal \(left >= 0 ? "left" : "over") · \(after.p.grams) / \(app.goals.p.grams) g protein")
                    .font(.manrope(14, .semibold))
                    .foregroundStyle(left >= 0 ? Theme.accent : Theme.over)

                if case .food(let f) = target, f.source == .off {
                    Text("Barcode \(f.barcode ?? "") · Data from Open Food Facts (ODbL). Check it against the pack.")
                        .font(.manrope(12)).foregroundStyle(Theme.muted)
                }

                VStack(spacing: 8) {
                    Button(editing == nil ? "Add to \(slot.rawValue)" : "Save changes") { commit() }
                        .buttonStyle(PrimaryButtonStyle(enabled: qty > 0))
                        .disabled(qty <= 0)
                    if editing != nil {
                        Button("Delete entry", role: .destructive) { deleteEntry() }
                            .font(.manrope(16, .bold))
                            .foregroundStyle(Theme.danger)
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.immediately)
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if editing != nil {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Text(editing != nil ? "Editing · \(slot.rawValue)" : slot.rawValue)
                    .font(.manrope(13, .semibold)).foregroundStyle(Theme.muted)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { qtyFocused = false }
            }
        }
    }

    private func change(_ dir: Double) {
        qtyFocused = false
        // Snap to the step grid, never below one step.
        let next = ((qty / step).rounded() + dir) * step
        qty = max(step, (next * 100).rounded() / 100)
    }

    private func commit() {
        if let editing {
            editing.amount = qty
            editing.slot = slot
            EntryActions.update(editing, catalog: catalog, context: context, app: app, health: health)
            app.showToast("Entry updated")
            app.logRequest = nil
            return
        }
        var cat = catalog
        let entry: Entry
        switch target {
        case .food(let f):
            if catalog.foods[f.id] == nil {
                // An Open Food Facts product: save it so it keeps working offline.
                context.insert(f)
                cat = cat.with(f)
            }
            entry = Entry(date: date, slot: slot, kind: .food, ref: f.id, amount: qty, time: DayKey.time(.now))
        case .meal(let m):
            entry = Entry(date: date, slot: slot, kind: .meal, ref: m.id, amount: qty, time: DayKey.time(.now))
        case .quick(let name, let m):
            entry = Entry(date: date, slot: slot, kind: .quick, ref: name, amount: qty, time: DayKey.time(.now), quick: m)
        }
        EntryActions.add(entry, catalog: cat, context: context, app: app, health: health)
        app.showToast("Added \(name) to \(slot.rawValue)")
        app.didLog(on: date)
        app.logRequest = nil
    }

    private func deleteEntry() {
        guard let editing else { return }
        EntryActions.delete(editing, context: context, app: app, health: health)
        app.showToast("Entry deleted")
        app.logRequest = nil
    }
}

private struct MacroTile: View {
    var value: String
    var label: String
    var color: Color
    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.manrope(18, .heavy)).foregroundStyle(color).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.manrope(12, .medium)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

private struct BigStepStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .frame(width: 60, height: 60)
            .background(Theme.card, in: Circle())
            .overlay(Circle().strokeBorder(Theme.border, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
    }
}
