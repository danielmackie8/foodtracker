import SwiftUI
import SwiftData

private enum FoodGroup: Hashable { case mine, logged, builtin }

/// Profile › Your foods: everything you've created or logged, searchable, with usage.
struct FoodsListView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Food.name) private var foods: [Food]
    @Query private var meals: [Meal]
    @Query private var entries: [Entry]
    @State private var query = ""
    @State private var group: FoodGroup = .mine

    var body: some View {
        let mine = foods.filter { $0.source == .custom }
        let logged = foods.filter { $0.source == .off }
        let builtin = foods.filter { $0.source == .builtin }
        let list: [Food] = {
            let base = group == .mine ? mine : group == .logged ? logged : builtin
            let q = query.trimmingCharacters(in: .whitespaces).lowercased()
            return q.isEmpty ? base : base.filter { ($0.name + " " + ($0.brand ?? "")).lowercased().contains(q) }
        }()
        let uses = Dictionary(grouping: entries.filter { $0.kind == .food }, by: \.ref).mapValues(\.count)

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                    TextField("Search your foods", text: $query)
                        .font(.manrope(15))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 46)
                .background(Theme.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))

                PillPicker(options: [(FoodGroup.mine, "Mine (\(mine.count))"), (.logged, "Logged UK (\(logged.count))"),
                                     (.builtin, "Built-in (\(builtin.count))")], selection: $group)

                if list.isEmpty {
                    Text(group == .mine ? "Foods you create, or save from Claude and Quick add, appear here."
                                        : group == .logged ? "UK products you scan or search and log appear here."
                                        : "No matches.")
                        .font(.manrope(14)).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    VStack(spacing: 0) {
                        ForEach(list) { food in
                            NavigationLink(value: food.id) {
                                FoodRow(food: food, uses: uses[food.id] ?? 0,
                                        inMeals: meals.filter { $0.parts.contains { $0.foodId == food.id } }.count)
                            }
                            .buttonStyle(PressableStyle())
                            if food.id != list.last?.id { Divider().overlay(Theme.border) }
                        }
                    }
                    .padding(.horizontal, 16)
                    .card(padding: 0)
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .navigationTitle("Your foods")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: "new") { Image(systemName: "plus") }
                    .accessibilityLabel("New food")
            }
        }
        .navigationDestination(for: String.self) { id in
            if id == "new" {
                FoodEditView(food: nil)
            } else if let food = foods.first(where: { $0.id == id }) {
                FoodEditView(food: food)
            }
        }
    }
}

private struct FoodRow: View {
    let food: Food
    let uses: Int
    let inMeals: Int

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(food.name).font(.manrope(14.5, .bold)).foregroundStyle(Theme.text).lineLimit(1)
                Text("\(food.brand.map { "\($0) · " } ?? "")\(food.kcal.clean) kcal per \(food.perLabel) · \(food.p.clean) g P")
                    .font(.manrope(11.5, .medium)).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer(minLength: 6)
            if let badge {
                Text(badge)
                    .font(.manrope(10.5, .bold)).foregroundStyle(Theme.accent)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Theme.accent.opacity(0.1), in: Capsule())
            }
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.dashed)
        }
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }

    private var badge: String? {
        if uses > 0 { return "logged \(uses)×" }
        if inMeals > 0 { return "in \(inMeals) meal\(inMeals == 1 ? "" : "s")" }
        return nil
    }
}

/// Create or edit a food. Built-in foods are read-only apart from favouriting and logging.
struct FoodEditView: View {
    let food: Food?

    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var foods: [Food]
    @Query private var meals: [Meal]
    @Query private var entries: [Entry]

    @State private var name = ""
    @State private var brand = ""
    @State private var per100 = true
    @State private var kcal = ""
    @State private var p = ""
    @State private var c = ""
    @State private var f = ""
    @State private var fibre = ""
    @State private var sugar = ""
    @State private var salt = ""
    @State private var loaded = false
    @State private var confirmDelete = false
    @FocusState private var focused: Bool

    init(food: Food?) {
        self.food = food
    }

    private var readOnly: Bool { food?.source == .builtin }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    private var valid: Bool { !trimmedName.isEmpty && FoodFormView.num(kcal) > 0 }

    var body: some View {
        let uses = food.map { fd in entries.filter { $0.kind == .food && $0.ref == fd.id }.count } ?? 0
        let inMeals = food.map { fd in meals.filter { $0.parts.contains { $0.foodId == fd.id } }.count } ?? 0

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                field("Name", $name, "e.g. Pork sausages", numeric: false)
                field("Brand (optional)", $brand, "e.g. HelloFresh", numeric: false)
                if food == nil || food?.isMetric == true || food?.unit == "serving" {
                    PillPicker(options: [(true, "Per 100 g"), (false, "Per serving")], selection: $per100)
                        .disabled(readOnly)
                } else if let food {
                    Text("Per \(food.perLabel)").font(.manrope(13, .semibold)).foregroundStyle(Theme.muted)
                }
                HStack(spacing: 8) {
                    field("kcal", $kcal, "0", numeric: true)
                    field("Protein g", $p, "0", numeric: true)
                    field("Carbs g", $c, "0", numeric: true)
                    field("Fat g", $f, "0", numeric: true)
                }
                Text("More detail (optional)").font(.manrope(12, .semibold)).foregroundStyle(Theme.muted).padding(.top, 2)
                HStack(spacing: 8) {
                    field("Fibre g", $fibre, "—", numeric: true)
                    field("Sugar g", $sugar, "—", numeric: true)
                    field("Salt g", $salt, "—", numeric: true)
                }

                if food != nil {
                    Text(usageText(uses: uses, inMeals: inMeals))
                        .font(.manrope(12.5, .medium))
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.chip, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                }

                if let food {
                    HStack(spacing: 8) {
                        secondary("★ Add to favourites") {
                            FoodActions.favourite(food, context: context)
                            app.showToast("\(food.name) added to favourites")
                        }
                        secondary("Log it now") {
                            dismiss()
                            app.tab = .day
                            app.dayOffset = 0
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(350))
                                app.openLog()
                            }
                        }
                    }
                }

                if !readOnly {
                    Button(food == nil ? "Create food" : "Save changes") { save() }
                        .buttonStyle(PrimaryButtonStyle(enabled: valid))
                        .disabled(!valid)
                }
                if food != nil && !readOnly {
                    Button("Delete food", role: .destructive) { confirmDelete = true }
                        .font(.manrope(16, .bold)).foregroundStyle(Theme.danger)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .disabled(false)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        .navigationTitle(food == nil ? "New food" : readOnly ? "Built-in food" : "Edit food")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = false }
            }
        }
        .confirmationDialog("Delete \(trimmedName)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete food", role: .destructive) {
                if let food {
                    FoodActions.delete(food, catalog: Catalog(foods: foods, meals: meals), context: context)
                    app.showToast("Food deleted")
                    dismiss()
                }
            }
        } message: {
            Text("Days you've already logged keep their numbers. It's removed from any meals that use it.")
        }
        .onAppear(perform: load)
    }

    private func usageText(uses: Int, inMeals: Int) -> String {
        var parts: [String] = []
        parts.append(uses == 0 ? "Not logged yet" : "Logged \(uses) time\(uses == 1 ? "" : "s")")
        if inMeals > 0 { parts.append("used in \(inMeals) meal\(inMeals == 1 ? "" : "s")") }
        var s = parts.joined(separator: " · ") + "."
        if readOnly { s += " Built-in foods can't be edited; create your own version instead." }
        else { s += " Changes apply from now on; days you've already logged keep their numbers." }
        return s
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let food else { return }
        func s(_ v: Double?) -> String { v.map { $0.clean } ?? "" }
        name = food.name
        brand = food.brand ?? ""
        per100 = food.isMetric
        kcal = s(food.kcal); p = s(food.p); c = s(food.c); f = s(food.f)
        fibre = s(food.fibre); sugar = s(food.sugar); salt = s(food.salt)
    }

    private func optional(_ s: String) -> Double? {
        s.trimmingCharacters(in: .whitespaces).isEmpty ? nil : FoodFormView.num(s)
    }

    private func save() {
        guard valid else { return }
        let target: Food
        if let food {
            // Keep past days as they were before changing the numbers.
            FoodActions.freezeHistory(of: food, catalog: Catalog(foods: foods, meals: meals), context: context)
            target = food
        } else {
            target = Food(id: "c" + UUID().uuidString, name: trimmedName, unit: "g", per: 100, step: 10, def: 100,
                          kcal: 0, p: 0, c: 0, f: 0, source: .custom)
            context.insert(target)
        }
        target.name = trimmedName
        target.brand = brand.trimmingCharacters(in: .whitespaces).isEmpty ? nil : brand.trimmingCharacters(in: .whitespaces)
        if food == nil || food?.isMetric == true || food?.unit == "serving" {
            if per100 {
                if !target.isMetric { target.unit = "g"; target.per = 100; target.step = 10; target.def = 100 }
            } else {
                target.unit = "serving"; target.per = 1; target.step = 0.5; target.def = 1
            }
        }
        target.kcal = FoodFormView.num(kcal)
        target.p = FoodFormView.num(p)
        target.c = FoodFormView.num(c)
        target.f = FoodFormView.num(f)
        target.fibre = optional(fibre)
        target.sugar = optional(sugar)
        target.salt = optional(salt)
        try? context.save()
        app.showToast(food == nil ? "\(trimmedName) added to your foods" : "Food updated")
        dismiss()
    }

    private func field(_ label: String, _ text: Binding<String>, _ placeholder: String, numeric: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.manrope(12, .semibold)).foregroundStyle(Theme.muted)
            TextField(placeholder, text: text)
                .font(.manrope(16, .bold))
                .keyboardType(numeric ? .decimalPad : .default)
                .focused($focused)
                .disabled(readOnly)
                .padding(.horizontal, 12)
                .frame(minHeight: 46)
                .background(Theme.field, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        }
        .frame(maxWidth: .infinity)
    }

    private func secondary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.manrope(14, .bold)).foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }
}
