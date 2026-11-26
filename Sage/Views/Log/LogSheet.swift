import SwiftUI
import SwiftData

enum LogRoute: Hashable {
    case meal(String)
    case food(String)
    case product(OFFProduct)
    case quickAdd
    case createFood(String)
    case imported(ClaudeImport)
    case createMeal
    case editMeal(String)
}

/// The log sheet: search + lists, then the amount screen.
struct LogSheet: View {
    let request: LogRequest

    @Environment(\.dismiss) private var dismiss
    @Query private var foods: [Food]
    @Query(sort: \Meal.sortIndex) private var meals: [Meal]
    @Query private var dayEntries: [Entry]
    @Query private var yesterdayEntries: [Entry]

    @State private var path: [LogRoute] = []
    @State private var slot: Slot

    init(request: LogRequest) {
        self.request = request
        let day = request.date
        _dayEntries = Query(filter: #Predicate<Entry> { $0.date == day })
        let previous = DayKey.key(DayKey.add(-1, to: DayKey.date(day)))
        _yesterdayEntries = Query(filter: #Predicate<Entry> { $0.date == previous }, sort: \Entry.time)
        _slot = State(initialValue: request.slot)
    }

    var body: some View {
        let catalog = Catalog(foods: foods, meals: meals)
        let dayTotals = dayEntries.reduce(into: Macros()) { $0 += catalog.macros(of: $1) }

        NavigationStack(path: $path) {
            Group {
                if let payload = request.imported {
                    ImportReviewView(payload: payload, defaultDate: request.date, catalog: catalog, slot: $slot)
                } else if let entry = request.editing {
                    AmountView(target: AmountTarget(entry: entry, catalog: catalog), editing: entry,
                               catalog: catalog, baseTotals: dayTotals - catalog.macros(of: entry),
                               date: request.date, slot: $slot)
                } else {
                    LogListView(foods: foods, meals: meals, catalog: catalog, yesterday: yesterdayEntries,
                                date: request.date, slot: $slot, path: $path)
                }
            }
            .navigationDestination(for: LogRoute.self) { route in
                switch route {
                case .meal(let id):
                    if let meal = catalog.meals[id] {
                        AmountView(target: .meal(meal), editing: nil, catalog: catalog, baseTotals: dayTotals, date: request.date, slot: $slot)
                    }
                case .food(let id):
                    if let food = catalog.foods[id] {
                        AmountView(target: .food(food), editing: nil, catalog: catalog, baseTotals: dayTotals, date: request.date, slot: $slot)
                    }
                case .product(let product):
                    // Use the saved copy if this product was logged before; otherwise a transient food.
                    AmountView(target: .food(catalog.foods[product.foodId] ?? product.makeFood()), editing: nil,
                               catalog: catalog, baseTotals: dayTotals, date: request.date, slot: $slot)
                case .quickAdd:
                    FoodFormView(mode: .quick, slot: $slot, date: request.date, baseTotals: dayTotals, catalog: catalog) { _ in }
                case .imported(let payload):
                    ImportReviewView(payload: payload, defaultDate: request.date, catalog: catalog, slot: $slot)
                case .createMeal:
                    MealEditorView(meal: nil, catalog: catalog) { _ in path.removeLast() }
                case .editMeal(let id):
                    if let meal = catalog.meals[id] {
                        MealEditorView(meal: meal, catalog: catalog) { _ in path.removeLast() }
                    }
                case .createFood(let name):
                    FoodFormView(mode: .create(name), slot: $slot, date: request.date, baseTotals: dayTotals, catalog: catalog) { food in
                        path.removeLast()
                        path.append(.food(food.id))
                    }
                }
            }
        }
        .tint(Theme.accent)
    }
}

// MARK: - Slot chips

struct SlotChips: View {
    @Binding var slot: Slot
    var body: some View {
        HStack(spacing: 8) {
            ForEach(Slot.allCases) { s in
                let on = s == slot
                Button { slot = s } label: {
                    Text(s.rawValue)
                        .font(.manrope(13, .semibold))
                        .foregroundStyle(on ? Color.white : Theme.text)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 36)
                        .frame(maxWidth: .infinity)
                        .background(on ? Theme.accent : Color.white, in: Capsule())
                        .overlay(Capsule().strokeBorder(on ? Theme.accent : Theme.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .frame(minHeight: Theme.minTouch)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: slot)
    }
}

// MARK: - Search & lists

private enum ListTab: Hashable { case yesterday, usuals, foods, products }

private struct LogListView: View {
    var foods: [Food]
    var meals: [Meal]
    var catalog: Catalog
    var yesterday: [Entry]
    var date: String
    @Binding var slot: Slot
    @Binding var path: [LogRoute]

    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app
    @Environment(HealthKitManager.self) private var health
    @Environment(\.modelContext) private var context
    @State private var query = ""
    @State private var tab: ListTab
    @State private var local: [OFFProduct] = []
    @State private var localQuery = ""
    @State private var remote: [OFFProduct] = []
    @State private var remoteQuery = ""
    @State private var remoteState: RemoteState = .idle
    @State private var scanning = false
    @State private var pasteFailed = false
    @State private var breakdownMeal: Meal?
    @FocusState private var searchFocused: Bool

    enum RemoteState: Equatable { case idle, loading, failed(String) }

    init(foods: [Food], meals: [Meal], catalog: Catalog, yesterday: [Entry], date: String,
         slot: Binding<Slot>, path: Binding<[LogRoute]>) {
        self.foods = foods
        self.meals = meals
        self.catalog = catalog
        self.yesterday = yesterday
        self.date = date
        _slot = slot
        _path = path
        _tab = State(initialValue: yesterday.isEmpty ? .usuals : .yesterday)
    }

    private static let builtinOrder: [String: Int] = Dictionary(uniqueKeysWithValues: SeedData.foods().enumerated().map { ($1.id, $0) })

    private var q: String { query.trimmingCharacters(in: .whitespaces).lowercased() }
    private var isBarcode: Bool { q.allSatisfy(\.isNumber) && (8...14).contains(q.count) }

    private var sortedFoods: [Food] {
        foods.sorted { a, b in
            let ia = Self.builtinOrder[a.id], ib = Self.builtinOrder[b.id]
            switch (ia, ib) {
            case let (x?, y?): return x < y
            case (nil, nil): return a.createdAt > b.createdAt
            case (nil, _): return true
            case (_, nil): return false
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                LazyVStack(spacing: 0) { results }
                    .padding(.horizontal, Theme.pagePadding)
                    .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .background(Theme.background)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: q) {
            // Search the bundled database as you type, slightly debounced.
            let current = q
            guard !current.isEmpty else { local = []; localQuery = ""; return }
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            let found = await ProductDatabase.shared.search(current)
            guard !Task.isCancelled else { return }
            local = found
            localQuery = current
        }
        .sheet(item: $breakdownMeal) { meal in
            MealBreakdownSheet(meal: meal, catalog: catalog, date: date, slot: $slot,
                               onEdit: {
                                   breakdownMeal = nil
                                   path.append(.editMeal(meal.id))
                               })
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(28)
                .presentationBackground(Theme.background)
        }
        .fullScreenCover(isPresented: $scanning) {
            BarcodeScannerSheet { code in
                scanning = false
                query = code
                Task { await lookUpBarcode(code) }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Add to \(slot.rawValue)").font(.manrope(22, .bold))
                Spacer()
                Button("Cancel") { dismiss() }
                    .font(.manrope(16, .semibold))
                    .frame(minHeight: Theme.minTouch)
            }
            SlotChips(slot: $slot)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                TextField("Search foods, brands or a barcode", text: $query)
                    .font(.manrope(16))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($searchFocused)
                    .onSubmit { Task { await submitSearch() } }
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted) }
                        .accessibilityLabel("Clear search")
                }
                Button { scanning = true } label: {
                    Image(systemName: "barcode.viewfinder").font(.system(size: 20)).foregroundStyle(Theme.accent)
                        .frame(width: Theme.minTouch, height: Theme.minTouch)
                }
                .accessibilityLabel("Scan a barcode")
            }
            .padding(.leading, 14)
            .frame(minHeight: 48)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))

            if q.isEmpty {
                HStack(spacing: 8) {
                    ActionChip(title: "Quick add", icon: "bolt.fill") { path.append(.quickAdd) }
                    ActionChip(title: "Create a food", icon: "plus") { path.append(.createFood("")) }
                }
                FromClaudeRow { text in
                    if let payload = ClaudeImport.parse(text) {
                        path.append(.imported(payload))
                    } else {
                        pasteFailed = true
                    }
                }
                .alert("Nothing to add", isPresented: $pasteFailed) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("Copy Claude's code block (or its Add to Sage link) first, then tap Paste.")
                }
                PillPicker(options: [(ListTab.yesterday, "Yesterday"), (.usuals, "Your meals"), (.foods, "Foods"), (.products, "UK")],
                           selection: $tab)
            }
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    // MARK: Results

    @ViewBuilder private var results: some View {
        if q.isEmpty {
            switch tab {
            case .yesterday:
                yesterdayList
            case .usuals:
                mealsList
            case .foods:
                ForEach(sortedFoods) { f in
                    ResultRow(name: f.name, sub: foodSubtitle(f), action: { path.append(.food(f.id)) },
                              onAdd: { add(food: f) })
                }
            case .products:
                productsHint
            }
        } else {
            let matchedMeals = meals.filter { $0.name.lowercased().contains(q) }
            let matchedFoods = sortedFoods.filter { ($0.name + " " + ($0.brand ?? "")).lowercased().contains(q) || $0.barcode == q }
            let names = Set(matchedFoods.map(\.name) + matchedMeals.map(\.name))
            let savedCodes = Set(matchedFoods.compactMap(\.barcode))
            let bundled = (localQuery == q ? local : []).filter { !names.contains($0.name) && !savedCodes.contains($0.barcode) }
            let bundledCodes = Set(bundled.map(\.barcode))
            let live = remoteQuery == q ? remote.filter { !bundledCodes.contains($0.barcode) && !savedCodes.contains($0.barcode) } : []

            ForEach(matchedMeals) { m in
                let mac = catalog.macros(of: m)
                ResultRow(name: m.name, sub: "\(mac.kcal.kcalString) kcal · \(mac.p.grams) g protein · \(m.desc)",
                          action: { breakdownMeal = m }, onAdd: { add(meal: m) })
            }
            ForEach(matchedFoods) { f in
                ResultRow(name: f.name, sub: foodSubtitle(f), action: { path.append(.food(f.id)) },
                          onAdd: { add(food: f) })
            }
            if !bundled.isEmpty || !live.isEmpty {
                HStack {
                    Text("UK PRODUCTS").font(.manrope(11, .bold)).tracking(0.8).foregroundStyle(Theme.muted)
                    Spacer()
                    Text("Open Food Facts").font(.manrope(11, .medium)).foregroundStyle(Theme.muted)
                }
                .padding(.top, 18).padding(.bottom, 4)
                ForEach(bundled + live) { p in
                    ResultRow(name: p.name, sub: p.subtitle, action: { path.append(.product(p)) },
                              onAdd: { add(food: catalog.foods[p.foodId] ?? p.makeFood()) })
                }
            }

            remoteFooter(isEmpty: matchedMeals.isEmpty && matchedFoods.isEmpty && bundled.isEmpty && live.isEmpty)
        }
    }

    // MARK: Yesterday

    @ViewBuilder private var yesterdayList: some View {
        if yesterday.isEmpty {
            Text("Nothing logged yesterday.")
                .font(.manrope(14)).foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, minHeight: 120)
        } else {
            let prevDate = DayKey.add(-1, to: DayKey.date(date))
            Text("YESTERDAY · \(prevDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)).uppercased())")
                .font(.manrope(11, .heavy)).tracking(0.8).foregroundStyle(Theme.muted)
                .padding(.top, 6).padding(.bottom, 2)
            ForEach(Slot.allCases) { s in
                let items = yesterday.filter { $0.slot == s }
                if !items.isEmpty {
                    Text(s.rawValue.uppercased())
                        .font(.manrope(11, .bold)).tracking(0.6).foregroundStyle(Theme.accent)
                        .padding(.top, 14)
                    ForEach(items) { e in
                        let m = catalog.macros(of: e)
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(catalog.name(of: e)).font(.manrope(15, .semibold)).lineLimit(2)
                                Text("\(m.kcal.kcalString) kcal · \(m.p.grams) g P · \(catalog.amountLabel(of: e))")
                                    .font(.manrope(12, .medium)).foregroundStyle(Theme.muted).lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            Button { copy([e]) } label: {
                                Label("Add", systemImage: "plus")
                                    .font(.manrope(13, .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 14)
                                    .frame(minHeight: 34)
                                    .background(Theme.accent, in: Capsule())
                                    .frame(minHeight: Theme.minTouch)
                            }
                            .buttonStyle(PressableStyle())
                            .accessibilityLabel("Add \(catalog.name(of: e)) to \(slot.rawValue)")
                        }
                        .padding(.vertical, 6)
                        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
                    }
                }
            }
            let sameSlot = yesterday.filter { $0.slot == slot }
            if sameSlot.count > 1 {
                Button("Repeat all of yesterday's \(slot.rawValue.lowercased())") { copy(sameSlot) }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 18)
            }
        }
    }

    /// One tap from the + button: logs a meal (1 serving) or a food (its usual amount).
    private func add(meal: Meal) {
        let entry = Entry(date: date, slot: slot, kind: .meal, ref: meal.id, amount: 1, time: DayKey.time(.now))
        EntryActions.add(entry, catalog: catalog, context: context, app: app, health: health)
        finishAdd(meal.name)
    }

    private func add(food: Food) {
        var cat = catalog
        if catalog.foods[food.id] == nil {
            context.insert(food) // a UK product logged for the first time
            cat = cat.with(food)
        }
        let entry = Entry(date: date, slot: slot, kind: .food, ref: food.id, amount: food.def, time: DayKey.time(.now))
        EntryActions.add(entry, catalog: cat, context: context, app: app, health: health)
        finishAdd(food.name)
    }

    private func finishAdd(_ name: String) {
        app.showToast("Added \(name) to \(slot.rawValue)")
        app.didLog(on: date)
        app.logRequest = nil
    }

    private func copy(_ entries: [Entry]) {
        EntryActions.copy(entries, to: date, slot: slot, catalog: catalog, context: context, app: app, health: health)
        app.showToast(entries.count == 1 ? "Added \(catalog.name(of: entries[0])) to \(slot.rawValue)"
                                         : "Added \(entries.count) items to \(slot.rawValue)")
        app.didLog(on: date)
        app.logRequest = nil
    }

    // MARK: Your meals

    @ViewBuilder private var mealsList: some View {
        let favourites = meals.filter(\.favourite)
        let others = meals.filter { !$0.favourite }
        Button { path.append(.createMeal) } label: {
            Label("Create a meal", systemImage: "plus")
                .font(.manrope(14, .bold))
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity, minHeight: Theme.minTouch)
                .background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .padding(.top, 4)

        if !favourites.isEmpty {
            Label("FAVOURITES", systemImage: "star.fill")
                .font(.manrope(11, .heavy)).tracking(0.8).foregroundStyle(Theme.muted)
                .padding(.top, 16).padding(.bottom, 2)
            ForEach(favourites) { m in mealRow(m) }
            Text("ALL MEALS")
                .font(.manrope(11, .heavy)).tracking(0.8).foregroundStyle(Theme.muted)
                .padding(.top, 18).padding(.bottom, 2)
        }
        ForEach(others) { m in mealRow(m) }
        Text("Tap ☆ to favourite · press and hold a meal to edit or delete it")
            .font(.manrope(12, .medium)).foregroundStyle(Theme.muted)
            .padding(.top, 12)
    }

    private func mealRow(_ m: Meal) -> some View {
        let mac = catalog.macros(of: m)
        return HStack(spacing: 4) {
            Button {
                m.favourite.toggle()
                try? context.save()
            } label: {
                Image(systemName: m.favourite ? "star.fill" : "star")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(m.favourite ? Theme.carbs : Theme.dashed)
                    .frame(width: 36, height: Theme.minTouch)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(m.favourite ? "Remove \(m.name) from favourites" : "Add \(m.name) to favourites")
            ResultRow(name: m.name, sub: "\(mac.kcal.kcalString) kcal · \(mac.p.grams) g protein · \(m.desc)",
                      action: { breakdownMeal = m }, onAdd: { add(meal: m) })
        }
        .contextMenu {
            Button { path.append(.editMeal(m.id)) } label: { Label("Edit meal", systemImage: "pencil") }
            Button {
                m.favourite.toggle()
                try? context.save()
            } label: {
                Label(m.favourite ? "Remove from favourites" : "Add to favourites", systemImage: m.favourite ? "star.slash" : "star")
            }
            Button(role: .destructive) {
                MealActions.delete(m, catalog: catalog, context: context)
                app.showToast("Meal deleted")
            } label: { Label("Delete meal", systemImage: "trash") }
        }
    }

    @ViewBuilder private func remoteFooter(isEmpty: Bool) -> some View {
        VStack(spacing: 10) {
            switch remoteState {
            case .loading:
                ProgressView().padding(.vertical, 8)
            case .failed(let message):
                Text(message).font(.manrope(13, .medium)).foregroundStyle(Theme.over).multilineTextAlignment(.center)
            case .idle:
                EmptyView()
            }
            if remoteState != .loading && remoteQuery != q {
                Button {
                    Task { await submitSearch() }
                } label: {
                    Label(isBarcode ? "Look up barcode \(q) online" : "Search Open Food Facts online for “\(query.trimmingCharacters(in: .whitespaces))”",
                          systemImage: "globe")
                        .font(.manrope(14, .bold))
                        .frame(maxWidth: .infinity, minHeight: Theme.minTouch)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
            } else if isEmpty && remoteState != .loading {
                Text("No matches for “\(query.trimmingCharacters(in: .whitespaces))”.")
                    .font(.manrope(14, .medium)).foregroundStyle(Theme.muted)
            }
            if isEmpty || remoteQuery == q {
                Button("Create “\(query.trimmingCharacters(in: .whitespaces))”") {
                    path.append(.createFood(isBarcode ? "" : query.trimmingCharacters(in: .whitespaces)))
                }
                .buttonStyle(.plain)
                .font(.manrope(14, .bold))
                .foregroundStyle(Theme.accent)
                .frame(minHeight: Theme.minTouch)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
    }

    private var productsHint: some View {
        VStack(spacing: 8) {
            Image(systemName: "barcode.viewfinder").font(.system(size: 30)).foregroundStyle(Theme.accent)
            Text("Search any UK product").font(.manrope(16, .bold))
            Text("Type a brand and product, like “Tesco 5% mince”, or scan the barcode on the pack.")
                .font(.manrope(14)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            Button {
                scanning = true
            } label: {
                Label("Scan a barcode", systemImage: "barcode.viewfinder")
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.top, 6)
            Text("\((ProductDatabase.meta?.count ?? 0).formatted()) UK products available offline · newer ones from Open Food Facts online")
                .font(.manrope(12, .medium)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                .padding(.top, 4)
        }
        .padding(.vertical, 28)
        .padding(.horizontal, 8)
    }

    private func foodSubtitle(_ f: Food) -> String {
        let prefix: String
        switch f.source {
        case .off: prefix = f.brand.map { "\($0) · " } ?? ""
        case .custom: prefix = "Your food · "
        case .builtin: prefix = ""
        }
        return "\(prefix)per \(f.perLabel) · \(f.kcal.clean) kcal · \(f.p.clean) g protein"
    }

    // MARK: Remote

    private func submitSearch() async {
        let current = q
        guard !current.isEmpty else { return }
        if isBarcode { await lookUpBarcode(current); return }
        remoteState = .loading
        do {
            let found = try await OpenFoodFactsClient.shared.search(current)
            remote = found
            remoteQuery = current
            remoteState = .idle
        } catch {
            remoteState = .failed((error as? LocalizedError)?.errorDescription ?? "Couldn't reach Open Food Facts.")
        }
    }

    private func lookUpBarcode(_ code: String) async {
        // A product logged before is already saved locally.
        if let saved = foods.first(where: { $0.barcode.map(OFFProduct.normalise) == OFFProduct.normalise(code) }) {
            path.append(.food(saved.id))
            return
        }
        remoteState = .loading
        do {
            let product = try await OpenFoodFactsClient.shared.product(barcode: code)
            remoteState = .idle
            remoteQuery = code
            remote = [product]
            path.append(.product(product))
        } catch {
            remoteQuery = code
            remote = []
            remoteState = .failed((error as? LocalizedError)?.errorDescription ?? "Couldn't reach Open Food Facts.")
        }
    }
}

private struct ActionChip: View {
    var title: String
    var icon: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.manrope(14, .bold))
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity, minHeight: Theme.minTouch)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
    }
}

/// A result row. Tapping the row opens its details; tapping + adds it straight away.
private struct ResultRow: View {
    var name: String
    var sub: String
    var action: () -> Void
    var onAdd: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 4) {
            Button(action: action) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(name).font(.manrope(15, .semibold)).foregroundStyle(Theme.text).lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(sub).font(.manrope(12, .medium)).foregroundStyle(Theme.muted).lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 8)
                }
                .padding(.vertical, 10)
                .frame(minHeight: 60)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityHint("Shows details")

            Button(action: onAdd ?? action) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 32, height: 32)
                    .background(Theme.accent.opacity(0.1), in: Circle())
                    .frame(width: Theme.minTouch, height: Theme.minTouch)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Add \(name)")
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }
}

/// "From Claude" row: the system Paste button reads Claude's copied reply without a permission prompt.
private struct FromClaudeRow: View {
    var onPaste: (String) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("From Claude").font(.manrope(14, .bold)).foregroundStyle(Theme.accent)
                Text("Copy Claude's estimate, then paste").font(.manrope(12, .medium)).foregroundStyle(Theme.muted)
            }
            Spacer()
            PasteButton(payloadType: String.self) { strings in
                guard let text = strings.first else { return }
                Task { @MainActor in onPaste(text) }
            }
            .labelStyle(.titleAndIcon)
            .buttonBorderShape(.capsule)
            .tint(Theme.accent)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 56)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
    }
}

/// Pop-up breakdown of a meal: each food with its amount and calories, servings, and Add.
private struct MealBreakdownSheet: View {
    let meal: Meal
    let catalog: Catalog
    let date: String
    @Binding var slot: Slot
    var onEdit: () -> Void

    @Environment(AppState.self) private var app
    @Environment(HealthKitManager.self) private var health
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var servings: Double = 1

    var body: some View {
        let parts: [(food: Food, amount: Double)] = meal.parts.compactMap { p in
            guard let food = catalog.foods[p.foodId] else { return nil }
            return (food: food, amount: p.amount * servings)
        }
        let total = catalog.macros(of: meal) * servings

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text(meal.name).font(.manrope(22, .heavy)).tracking(-0.3)
                    Spacer()
                    Button("Edit", action: onEdit)
                        .font(.manrope(15, .bold))
                        .foregroundStyle(Theme.accent)
                        .frame(minHeight: Theme.minTouch)
                }

                HStack(spacing: 8) {
                    tile(total.kcal.kcalString, "kcal", Theme.text)
                    tile("\(total.p.grams)g", "protein", Theme.accent)
                    tile("\(total.c.grams)g", "carbs", Theme.text)
                    tile("\(total.f.grams)g", "fat", Theme.text)
                }

                VStack(spacing: 0) {
                    ForEach(Array(parts.enumerated()), id: \.offset) { i, part in
                        if i > 0 { Divider().overlay(Theme.border) }
                        let m = part.food.macros(for: part.amount)
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(part.food.name).font(.manrope(15, .semibold))
                                Text("\(part.food.amountLabel(part.amount)) · \(m.p.grams) g P · \(m.c.grams) g C · \(m.f.grams) g F")
                                    .font(.manrope(12, .medium)).foregroundStyle(Theme.muted)
                            }
                            Spacer(minLength: 8)
                            (Text(m.kcal.kcalString).font(.manrope(15, .bold))
                             + Text(" kcal").font(.manrope(12, .medium)).foregroundColor(Theme.muted))
                                .monospacedDigit()
                        }
                        .frame(minHeight: 56)
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.horizontal, 16)
                .card(padding: 0)

                HStack {
                    Text("Servings").font(.manrope(15, .semibold))
                    Spacer()
                    Button { servings = max(0.5, servings - 0.5) } label: { Image(systemName: "minus") }
                        .buttonStyle(CircleIconButtonStyle())
                        .accessibilityLabel("Fewer servings")
                    Text(servings.clean).font(.manrope(17, .bold)).monospacedDigit().frame(minWidth: 36)
                    Button { servings += 0.5 } label: { Image(systemName: "plus") }
                        .buttonStyle(CircleIconButtonStyle())
                        .accessibilityLabel("More servings")
                }

                SlotChips(slot: $slot)

                Button("Add to \(slot.rawValue)") {
                    let entry = Entry(date: date, slot: slot, kind: .meal, ref: meal.id, amount: servings, time: DayKey.time(.now))
                    EntryActions.add(entry, catalog: catalog, context: context, app: app, health: health)
                    app.showToast("Added \(meal.name) to \(slot.rawValue)")
                    app.didLog(on: date)
                    dismiss()
                    app.logRequest = nil
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(Theme.pagePadding)
        }
    }

    private func tile(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.manrope(18, .heavy)).foregroundStyle(color).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.manrope(12, .medium)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, minHeight: 60)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
    }
}
