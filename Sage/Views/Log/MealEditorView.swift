import SwiftUI
import SwiftData

/// Create or edit a saved meal: name, foods with amounts, favourite.
struct MealEditorView: View {
    let meal: Meal?
    let catalog: Catalog
    /// Called after saving (with the meal) or deleting (with nil).
    var onDone: (Meal?) -> Void

    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @State private var name: String
    @State private var parts: [DraftPart]
    @State private var favourite: Bool
    @State private var picking = false
    @State private var confirmDelete = false
    @FocusState private var nameFocused: Bool

    init(meal: Meal?, initialParts: [DraftPart] = [], suggestedName: String = "", favourite: Bool = false,
         catalog: Catalog, onDone: @escaping (Meal?) -> Void) {
        self.meal = meal
        self.catalog = catalog
        self.onDone = onDone
        if let meal {
            _name = State(initialValue: meal.name)
            _parts = State(initialValue: meal.parts.compactMap { p in
                catalog.foods[p.foodId].map { DraftPart(food: $0, amount: p.amount) }
            })
            _favourite = State(initialValue: meal.favourite)
        } else {
            _name = State(initialValue: suggestedName)
            _parts = State(initialValue: initialParts)
            _favourite = State(initialValue: favourite)
        }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    private var canSave: Bool { !trimmedName.isEmpty && !parts.isEmpty }

    var body: some View {
        let total = parts.reduce(into: Macros()) { $0 += $1.food.macros(for: $1.amount) }

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(meal == nil ? "Save as a meal" : "Edit meal").font(.manrope(24, .bold)).tracking(-0.4)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Name").font(.manrope(13, .semibold)).foregroundStyle(Theme.muted)
                    TextField("e.g. Eggs, sourdough & avo", text: $name)
                        .font(.manrope(17, .semibold))
                        .focused($nameFocused)
                        .submitLabel(.done)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 48)
                        .background(Theme.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
                }

                Text("Foods").font(.manrope(13, .semibold)).foregroundStyle(Theme.muted).padding(.top, 2)
                VStack(spacing: 0) {
                    ForEach($parts) { $part in
                        PartRow(part: $part) {
                            withAnimation { parts.removeAll { $0.id == part.id } }
                        }
                        Divider().overlay(Theme.border).padding(.horizontal, 16)
                    }
                    Button { picking = true } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .bold))
                                .frame(width: 26, height: 26)
                                .background(Theme.accent.opacity(0.1), in: Circle())
                            Text("Add a food").font(.manrope(15, .bold))
                            Spacer()
                        }
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 52)
                    }
                    .buttonStyle(PressableStyle())
                }
                .card(padding: 0)

                HStack {
                    Text("Per serving").font(.manrope(14, .semibold))
                    Spacer()
                    (Text("\(total.kcal.kcalString) kcal").font(.manrope(14, .heavy))
                     + Text(" · \(total.p.grams) g P · \(total.c.grams) g C · \(total.f.grams) g F").font(.manrope(13, .medium)))
                        .monospacedDigit()
                }
                .padding(14)
                .background(Theme.chip, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                Toggle(isOn: $favourite) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Favourite", systemImage: "star.fill").font(.manrope(15, .semibold))
                        Text("Show at the top of Your meals").font(.manrope(12, .medium)).foregroundStyle(Theme.muted)
                    }
                }
                .tint(Theme.switchOn)
                .padding(.horizontal, 16)
                .frame(minHeight: 60)
                .card(padding: 0)

                Button(meal == nil ? "Save meal" : "Save changes") { save() }
                    .buttonStyle(PrimaryButtonStyle(enabled: canSave))
                    .disabled(!canSave)

                if meal != nil {
                    Button("Delete meal", role: .destructive) { confirmDelete = true }
                        .font(.manrope(16, .bold))
                        .foregroundStyle(Theme.danger)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $picking) {
            FoodPickerView(catalog: catalog) { food in
                picking = false
                if let i = parts.firstIndex(where: { $0.food.id == food.id }) {
                    parts[i].amount += food.def
                } else {
                    parts.append(DraftPart(food: food, amount: food.def))
                }
            }
            .presentationDetents([.large])
            .presentationBackground(Theme.background)
        }
        .confirmationDialog("Delete \(trimmedName.isEmpty ? "this meal" : trimmedName)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete meal", role: .destructive) {
                if let meal {
                    MealActions.delete(meal, catalog: catalog, context: context)
                    app.showToast("Meal deleted")
                    onDone(nil)
                }
            }
        } message: {
            Text("Days you've already logged it keep their calories.")
        }
        .onAppear { if meal == nil && name.isEmpty { nameFocused = true } }
    }

    private func save() {
        guard canSave else { return }
        let saved = MealActions.save(meal, name: trimmedName, parts: parts, favourite: favourite,
                                     catalog: catalog, context: context)
        app.showToast(meal == nil ? "Saved \(trimmedName) to your meals" : "Meal updated")
        onDone(saved)
    }
}

private struct PartRow: View {
    @Binding var part: DraftPart
    var remove: () -> Void

    private var step: Double { part.food.step > 0 ? part.food.step : 1 }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(part.food.name).font(.manrope(15, .semibold)).lineLimit(2)
                Text("\(part.food.amountLabel(part.amount)) · \(part.food.macros(for: part.amount).kcal.kcalString) kcal")
                    .font(.manrope(12, .medium)).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 6)
            Button {
                if part.amount - step < step * 0.5 { remove() } else { part.amount = ((part.amount - step) * 100).rounded() / 100 }
            } label: { Image(systemName: part.amount - step < step * 0.5 ? "trash" : "minus") }
                .buttonStyle(SmallStepStyle())
                .accessibilityLabel(part.amount - step < step * 0.5 ? "Remove \(part.food.name)" : "Less")
            Text(part.food.isMetric ? part.amount.clean : part.amount.clean)
                .font(.manrope(15, .bold)).monospacedDigit()
                .frame(minWidth: 34)
            Button { part.amount = ((part.amount + step) * 100).rounded() / 100 } label: { Image(systemName: "plus") }
                .buttonStyle(SmallStepStyle())
                .accessibilityLabel("More")
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 60)
    }
}

private struct SmallStepStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(Theme.text)
            .frame(width: 34, height: 34)
            .background(Theme.card, in: Circle())
            .overlay(Circle().strokeBorder(Theme.border, lineWidth: 1))
            .frame(width: Theme.minTouch, height: Theme.minTouch)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// Pick a food for a meal: your foods and built-ins, plus UK products from the bundled database.
struct FoodPickerView: View {
    let catalog: Catalog
    var onPick: (Food) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var products: [OFFProduct] = []

    private var q: String { query.trimmingCharacters(in: .whitespaces).lowercased() }

    var body: some View {
        let foods = catalog.foods.values
            .filter { q.isEmpty || ($0.name + " " + ($0.brand ?? "")).lowercased().contains(q) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let savedIds = Set(catalog.foods.keys)

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Add a food").font(.manrope(22, .bold))
                Spacer()
                Button("Cancel") { dismiss() }.font(.manrope(16, .semibold)).frame(minHeight: Theme.minTouch)
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                TextField("Search foods or UK products", text: $query)
                    .font(.manrope(16))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .background(Theme.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(foods) { f in
                        pickRow(f.name, "per \(f.perLabel) · \(f.kcal.clean) kcal · \(f.p.clean) g protein") { onPick(f) }
                    }
                    let extra = products.filter { !savedIds.contains($0.foodId) }
                    if !extra.isEmpty {
                        Text("UK PRODUCTS").font(.manrope(11, .bold)).tracking(0.8).foregroundStyle(Theme.muted)
                            .padding(.top, 18).padding(.bottom, 4)
                        ForEach(extra) { p in
                            pickRow(p.name, p.subtitle) { onPick(p.makeFood()) }
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.top, 16)
        .task(id: q) {
            guard q.count >= 2 else { products = []; return }
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            products = await ProductDatabase.shared.search(q, limit: 25)
        }
    }

    private func pickRow(_ name: String, _ sub: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(name).font(.manrope(15, .semibold)).foregroundStyle(Theme.text).lineLimit(2)
                    Text(sub).font(.manrope(12, .medium)).foregroundStyle(Theme.muted).lineLimit(2)
                }
                Spacer(minLength: 8)
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 32, height: 32)
                    .background(Theme.accent.opacity(0.1), in: Circle())
            }
            .padding(.vertical, 10)
            .frame(minHeight: 60)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
        }
        .buttonStyle(PressableStyle())
    }
}
