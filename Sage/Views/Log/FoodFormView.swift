import SwiftUI
import SwiftData

/// Quick add (kcal + optional macros) or Create a food (per 100 g or per serving).
struct FoodFormView: View {
    enum Mode: Equatable {
        case quick
        case create(String)
    }

    let mode: Mode
    @Binding var slot: Slot
    let date: String
    let baseTotals: Macros
    let catalog: Catalog
    var onCreated: (Food) -> Void

    @Environment(AppState.self) private var app
    @Environment(HealthKitManager.self) private var health
    @Environment(\.modelContext) private var context

    @State private var name = ""
    @State private var kcal = ""
    @State private var p = ""
    @State private var c = ""
    @State private var f = ""
    @State private var per100 = true
    @State private var didPrefill = false
    @FocusState private var focus: Field?

    enum Field: Hashable { case name, kcal, p, c, f }

    init(mode: Mode, slot: Binding<Slot>, date: String, baseTotals: Macros, catalog: Catalog, onCreated: @escaping (Food) -> Void) {
        self.mode = mode
        _slot = slot
        self.date = date
        self.baseTotals = baseTotals
        self.catalog = catalog
        self.onCreated = onCreated
    }

    private var isQuick: Bool { mode == .quick }
    private var k: Double { Self.num(kcal) }
    private var valid: Bool { k > 0 && (isQuick || !name.trimmingCharacters(in: .whitespaces).isEmpty) }

    static func num(_ s: String) -> Double {
        let v = Double(s.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)) ?? 0
        return max(0, v)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isQuick ? "Quick add" : "Create a food").font(.manrope(24, .bold))
                    Text(isQuick ? "Log calories without picking a food. Good for meals out or a rough estimate."
                                 : "Saved to your foods so you can search for it next time.")
                        .font(.manrope(14)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if isQuick {
                    SlotChips(slot: $slot)
                } else {
                    PillPicker(options: [(true, "Per 100 g"), (false, "Per serving")], selection: $per100)
                }

                field(isQuick ? "Label (optional)" : "Food name",
                      text: $name, placeholder: isQuick ? "e.g. Pub lunch" : "e.g. Pork sausages", numeric: false, id: .name)
                field(isQuick ? "Calories (kcal)" : (per100 ? "Calories per 100 g" : "Calories per serving"),
                      text: $kcal, placeholder: "0", numeric: true, id: .kcal)
                HStack(spacing: 10) {
                    field("Protein g", text: $p, placeholder: "0", numeric: true, id: .p)
                    field("Carbs g", text: $c, placeholder: "0", numeric: true, id: .c)
                    field("Fat g", text: $f, placeholder: "0", numeric: true, id: .f)
                }

                Text(preview)
                    .font(.manrope(14, .semibold))
                    .foregroundStyle(valid ? Theme.accent : Theme.muted)

                Button(isQuick ? "Add to \(slot.rawValue)" : "Save and log") { save() }
                    .buttonStyle(PrimaryButtonStyle(enabled: valid))
                    .disabled(!valid)
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Text(slot.rawValue).font(.manrope(13, .semibold)).foregroundStyle(Theme.muted)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focus = nil }
            }
        }
        .onAppear {
            guard !didPrefill else { return }
            didPrefill = true
            if case .create(let prefill) = mode { name = prefill }
            focus = (isQuick || !name.isEmpty) ? .kcal : .name
        }
    }

    private var preview: String {
        if isQuick {
            guard k > 0 else { return "Enter calories to continue" }
            let left = app.goals.kcal - baseTotals.kcal - k
            return "Afterwards: \(abs(left).kcalString) kcal \(left >= 0 ? "left" : "over") · \((baseTotals.p + Self.num(p)).grams) / \(app.goals.p.grams) g protein"
        }
        return valid ? "You can set the amount on the next screen" : "A name and calories are needed"
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String, numeric: Bool, id: Field) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.manrope(13, .semibold)).foregroundStyle(Theme.muted)
            TextField(placeholder, text: text)
                .font(.manrope(17, .semibold))
                .keyboardType(numeric ? .decimalPad : .default)
                .textInputAutocapitalization(numeric ? .never : .sentences)
                .focused($focus, equals: id)
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        }
        .frame(maxWidth: .infinity)
    }

    private func save() {
        guard valid else { return }
        let macros = Macros(kcal: k, p: Self.num(p), c: Self.num(c), f: Self.num(f))
        let label = name.trimmingCharacters(in: .whitespaces)

        if isQuick {
            let entry = Entry(date: date, slot: slot, kind: .quick, ref: label.isEmpty ? "Quick add" : label,
                              amount: 1, time: DayKey.time(.now), quick: macros)
            EntryActions.add(entry, catalog: catalog, context: context, app: app, health: health)
            app.showToast("Added \(k.kcalString) kcal to \(slot.rawValue)")
            app.didLog(on: date)
            app.logRequest = nil
            return
        }

        let food = Food(id: "c" + UUID().uuidString, name: label,
                        unit: per100 ? "g" : "serving", per: per100 ? 100 : 1,
                        step: per100 ? 10 : 0.5, def: per100 ? 100 : 1,
                        kcal: macros.kcal, p: macros.p, c: macros.c, f: macros.f, source: .custom)
        context.insert(food)
        try? context.save()
        app.showToast("Saved \(label) to your foods")
        onCreated(food)
    }
}
