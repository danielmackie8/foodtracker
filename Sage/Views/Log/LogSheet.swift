import SwiftUI
import SwiftData

enum LogRoute: Hashable {
    case meal(String)
    case food(String)
    case product(OFFProduct)
    case quickAdd
    case createFood(String)
}

/// The log sheet: search + lists, then the amount screen.
struct LogSheet: View {
    let request: LogRequest

    @Environment(\.dismiss) private var dismiss
    @Query private var foods: [Food]
    @Query(sort: \Meal.sortIndex) private var meals: [Meal]
    @Query private var dayEntries: [Entry]

    @State private var path: [LogRoute] = []
    @State private var slot: Slot

    init(request: LogRequest) {
        self.request = request
        let day = request.date
        _dayEntries = Query(filter: #Predicate<Entry> { $0.date == day })
        _slot = State(initialValue: request.slot)
    }

    var body: some View {
        let catalog = Catalog(foods: foods, meals: meals)
        let dayTotals = dayEntries.reduce(into: Macros()) { $0 += catalog.macros(of: $1) }

        NavigationStack(path: $path) {
            Group {
                if let entry = request.editing {
                    AmountView(target: AmountTarget(entry: entry, catalog: catalog), editing: entry,
                               catalog: catalog, baseTotals: dayTotals - catalog.macros(of: entry),
                               date: request.date, slot: $slot)
                } else {
                    LogListView(foods: foods, meals: meals, catalog: catalog, slot: $slot, path: $path)
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

private enum ListTab: Hashable { case usuals, foods, products }

private struct LogListView: View {
    var foods: [Food]
    var meals: [Meal]
    var catalog: Catalog
    @Binding var slot: Slot
    @Binding var path: [LogRoute]

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var tab: ListTab = .usuals
    @State private var remote: [OFFProduct] = []
    @State private var remoteQuery = ""
    @State private var remoteState: RemoteState = .idle
    @State private var scanning = false
    @FocusState private var searchFocused: Bool

    enum RemoteState: Equatable { case idle, loading, failed(String) }

    init(foods: [Food], meals: [Meal], catalog: Catalog, slot: Binding<Slot>, path: Binding<[LogRoute]>) {
        self.foods = foods
        self.meals = meals
        self.catalog = catalog
        _slot = slot
        _path = path
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
                PillPicker(options: [(ListTab.usuals, "Your meals"), (.foods, "Foods"), (.products, "UK products")], selection: $tab)
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
            case .usuals:
                ForEach(meals) { m in
                    let mac = catalog.macros(of: m)
                    ResultRow(name: m.name, sub: "\(mac.kcal.kcalString) kcal · \(mac.p.grams) g protein · \(m.desc)") {
                        path.append(.meal(m.id))
                    }
                }
            case .foods:
                ForEach(sortedFoods) { f in
                    ResultRow(name: f.name, sub: foodSubtitle(f)) { path.append(.food(f.id)) }
                }
            case .products:
                productsHint
            }
        } else {
            let matchedMeals = meals.filter { $0.name.lowercased().contains(q) }
            let matchedFoods = sortedFoods.filter { ($0.name + " " + ($0.brand ?? "")).lowercased().contains(q) || $0.barcode == q }
            let names = Set(matchedFoods.map(\.name) + matchedMeals.map(\.name))
            let savedCodes = Set(matchedFoods.compactMap(\.barcode))
            let bundled = BundledProducts.shared.search(q).filter { !names.contains($0.name) && !savedCodes.contains($0.barcode) }
            let bundledCodes = Set(bundled.map(\.barcode))
            let live = remoteQuery == q ? remote.filter { !bundledCodes.contains($0.barcode) && !savedCodes.contains($0.barcode) } : []

            ForEach(matchedMeals) { m in
                let mac = catalog.macros(of: m)
                ResultRow(name: m.name, sub: "\(mac.kcal.kcalString) kcal · \(mac.p.grams) g protein · \(m.desc)") { path.append(.meal(m.id)) }
            }
            ForEach(matchedFoods) { f in
                ResultRow(name: f.name, sub: foodSubtitle(f)) { path.append(.food(f.id)) }
            }
            if !bundled.isEmpty || !live.isEmpty {
                HStack {
                    Text("UK PRODUCTS").font(.manrope(11, .bold)).tracking(0.8).foregroundStyle(Theme.muted)
                    Spacer()
                    Text("Open Food Facts").font(.manrope(11, .medium)).foregroundStyle(Theme.muted)
                }
                .padding(.top, 18).padding(.bottom, 4)
                ForEach(bundled + live) { p in
                    ResultRow(name: p.name, sub: p.subtitle) { path.append(.product(p)) }
                }
            }

            remoteFooter(isEmpty: matchedMeals.isEmpty && matchedFoods.isEmpty && bundled.isEmpty && live.isEmpty)
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
                    Label(isBarcode ? "Look up barcode \(q)" : "Search all UK products for “\(query.trimmingCharacters(in: .whitespaces))”",
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
            Text("\(BundledProducts.shared.products.count) UK products available offline · more from Open Food Facts")
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

private struct ResultRow: View {
    var name: String
    var sub: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(name).font(.manrope(15, .semibold)).foregroundStyle(Theme.text).lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(sub).font(.manrope(12, .medium)).foregroundStyle(Theme.muted).lineLimit(2)
                        .multilineTextAlignment(.leading)
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
