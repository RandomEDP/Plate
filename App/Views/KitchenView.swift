import PlateCore
import SwiftUI

struct KitchenView: View {
    @Environment(AppModel.self) private var model
    @State private var place: StorageLocation?
    @State private var search = ""
    @State private var adding = false
    @State private var typing = false
    @State private var scanning = false
    @State private var editing: InventoryItem?

    var items: [InventoryItem] {
        model.household.inventory
            .filter { place == nil || $0.location == place }
            .filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
            .sorted { a, b in
                let ea = a.expiry ?? .distantFuture, eb = b.expiry ?? .distantFuture
                return ea != eb ? ea < eb : a.name < b.name
            }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Where", selection: $place) {
                        Text("All").tag(StorageLocation?.none)
                        ForEach(StorageLocation.allCases) { Text($0.title).tag(StorageLocation?.some($0)) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                if model.household.inventory.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Your kitchen is empty").font(.headline)
                            Text("Add what's in your fridge, freezer and cupboards. The quickest way is to type a list, one thing per line, like “6 eggs” or “1kg chicken breast”.")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Button { typing = true } label: { Label("Type a list", systemImage: "text.badge.plus") }
                                .buttonStyle(.borderedProminent)
                        }
                        .padding(.vertical, 6)
                    }
                }
                ForEach(groups, id: \.0) { group in
                    Section(group.0) {
                        ForEach(group.1) { item in
                            Button { editing = item } label: { ItemRow(item: item) }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) { model.finish(item) } label: { Label("Used up", systemImage: "trash") }
                                }
                                .swipeActions(edge: .leading) {
                                    if model.household.preppedMeals[item.id] != nil {
                                        Button { model.eatPrepped(item, meal: currentMeal()) } label: { Label("Eat one", systemImage: "fork.knife") }
                                            .tint(.green)
                                    }
                                }
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Search your kitchen")
            .navigationTitle("Kitchen")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { adding = true } label: { Label("Add an item", systemImage: "plus") }
                        Button { typing = true } label: { Label("Type a list", systemImage: "text.badge.plus") }
                        Button { scanning = true } label: { Label("Scan a barcode", systemImage: "barcode.viewfinder") }
                    } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add food")
                }
            }
            .sheet(isPresented: $adding) { AddFoodView() }
            .sheet(isPresented: $typing) { TypeListView() }
            .sheet(isPresented: $scanning) { BarcodeAddView() }
            .sheet(item: $editing) { EditItemView(item: $0) }
        }
    }

    /// Prepped meals first, then by where things are kept.
    var groups: [(String, [InventoryItem])] {
        let prepped = items.filter { model.household.preppedMeals[$0.id] != nil }
        var out: [(String, [InventoryItem])] = []
        if !prepped.isEmpty { out.append(("Prepped meals", prepped)) }
        let rest = items.filter { model.household.preppedMeals[$0.id] == nil }
        for loc in StorageLocation.allCases where place == nil || place == loc {
            let these = rest.filter { $0.location == loc }
            if !these.isEmpty { out.append((loc.title, these)) }
        }
        return out
    }

    func currentMeal() -> MealType {
        let h = Calendar.current.component(.hour, from: Date())
        switch h { case ..<11: return .breakfast; case ..<15: return .lunch; case 17...: return .dinner; default: return .snack }
    }
}

struct ItemRow: View {
    let item: InventoryItem
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                if let f = FoodDatabase.food(item.foodId), f.name != item.name {
                    Text(f.name).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(item.amountText).foregroundStyle(.secondary).monospacedDigit()
            ExpiryBadge(date: item.expiry)
        }
        .contentShape(Rectangle())
    }
}

/// Pick a food from the built-in list (or type your own) and say how much.
struct AddFoodView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var food: Food?
    @State private var customName = ""
    @State private var amount = 1.0
    @State private var unit: BaseUnit = .piece
    @State private var location: StorageLocation = .fridge
    @State private var hasExpiry = true
    @State private var expiry = Date()
    var prefill: OpenFoodFacts.Product?

    var body: some View {
        NavigationStack {
            Form {
                if food == nil && customName.isEmpty {
                    Section {
                        TextField("What is it? e.g. chicken breast", text: $search)
                            .autocorrectionDisabled()
                        ForEach(FoodMatcher.search(search, limit: search.isEmpty ? 12 : 20)) { f in
                            Button { choose(f) } label: {
                                HStack {
                                    Text(f.name)
                                    Spacer()
                                    Text(f.category.title).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                        if !search.isEmpty {
                            Button("Add “\(search)” as my own item") {
                                customName = search
                                unit = .piece; amount = 1; location = .cupboard; hasExpiry = false
                            }
                        }
                    }
                } else {
                    Section {
                        HStack {
                            Text(food?.name ?? customName).font(.headline)
                            Spacer()
                            Button("Change") { food = nil; customName = "" }
                        }
                        HStack {
                            TextField("Amount", value: $amount, format: .number)
                                .keyboardType(.decimalPad)
                            Picker("", selection: $unit) {
                                ForEach(units, id: \.self) { Text($0.pickerTitle).tag($0) }
                            }
                            .labelsHidden()
                        }
                        Picker("Kept in", selection: $location) {
                            ForEach(StorageLocation.allCases) { Text($0.title).tag($0) }
                        }
                        Toggle("Use-by date", isOn: $hasExpiry)
                        if hasExpiry {
                            DatePicker("Use by", selection: $expiry, displayedComponents: .date)
                        }
                    }
                    if let food {
                        Section("Per 100\(food.unit == .ml ? "ml" : "g")") { MacroLine(macros: food.per100) }
                    }
                }
            }
            .navigationTitle("Add to kitchen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { add(); dismiss() }
                        .disabled((food == nil && customName.isEmpty) || amount <= 0)
                }
            }
            .onAppear(perform: applyPrefill)
        }
    }

    var units: [BaseUnit] {
        guard let food else { return BaseUnit.allCases }
        var u: [BaseUnit] = [food.unit]
        for other in BaseUnit.allCases where other != food.unit {
            if Units.convert(1, from: other, to: food.unit, food: food) != nil { u.append(other) }
        }
        return u
    }

    func choose(_ f: Food) {
        food = f
        unit = f.unit
        amount = f.packs.first(where: { $0.store == .sainsburys })?.size ?? (f.unit == .piece ? 1 : 100)
        location = f.storage
        if let d = Kitchen.defaultExpiry(for: f, location: f.storage, from: Date()) { expiry = d; hasExpiry = true } else { hasExpiry = false }
    }

    func applyPrefill() {
        guard let p = prefill else { return }
        if let f = p.food { choose(f) } else { customName = p.name; location = .cupboard; hasExpiry = false }
        if let size = p.size, let u = p.unit {
            if let f = food, let v = Units.convert(size, from: u, to: f.unit, food: f) { amount = v; unit = f.unit }
            else { amount = size; unit = u }
        }
    }

    func add() {
        var amountInUnit = amount
        var keptUnit = unit
        if let food, unit != food.unit, let v = Units.convert(amount, from: unit, to: food.unit, food: food) {
            amountInUnit = v; keptUnit = food.unit
        }
        let name = prefill.map { [$0.brand, $0.name].compactMap { $0 }.joined(separator: " ") } ?? food?.name ?? customName
        model.add(InventoryItem(foodId: food?.id, name: name.isEmpty ? (food?.name ?? customName) : name, amount: amountInUnit,
                                unit: keptUnit, location: location, expiry: hasExpiry ? expiry : nil, barcode: prefill?.barcode,
                                customPer100: food == nil ? prefill?.per100 : nil))
        model.banner = "Added \(food?.name ?? customName)"
    }
}

/// Type or paste a list ("6 eggs", "1kg chicken", "2 tins chopped tomatoes") and add it all in one go.
struct TypeListView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var parsed: [(String, IngredientParser.Result?)] {
        text.split(separator: "\n").map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { ($0, IngredientParser.parse($0)) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 160)
                        .autocorrectionDisabled()
                } footer: {
                    Text("One item per line, e.g. “6 eggs”, “500g mince”, “2 tins chopped tomatoes”, “milk”. Plate fills in where it's kept and a use-by date.")
                }
                if !parsed.isEmpty {
                    Section("Plate reads this as") {
                        ForEach(Array(parsed.enumerated()), id: \.offset) { _, row in
                            let (line, r) = row
                            if let item = item(from: r, line: line) {
                                HStack {
                                    Text(item.name)
                                    Spacer()
                                    Text(item.amountText).foregroundStyle(.secondary)
                                    Text(item.location.title).font(.caption).foregroundStyle(.secondary)
                                }
                            } else {
                                Text(line).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Type a list")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add all") {
                        var n = 0
                        for (line, r) in parsed { if let item = item(from: r, line: line) { model.add(item); n += 1 } }
                        model.banner = "Added \(n) item\(n == 1 ? "" : "s") to your kitchen"
                        dismiss()
                    }
                    .disabled(parsed.isEmpty)
                }
            }
        }
    }

    func item(from r: IngredientParser.Result?, line: String) -> InventoryItem? {
        let now = Date()
        guard let r else {
            let name = IngredientParser.clean(line)
            guard !name.isEmpty else { return nil }
            return InventoryItem(foodId: nil, name: name.prefix(1).uppercased() + name.dropFirst(), amount: 1, unit: .piece, location: .cupboard, addedAt: now)
        }
        if let food = r.food {
            var amount: Double
            if let q = r.quantity, let v = Units.amountInFoodUnit(q, food: food) { amount = v }
            else { amount = food.packs.first(where: { $0.store == .sainsburys })?.size ?? 1 }
            amount = (amount * 100).rounded() / 100
            return InventoryItem(foodId: food.id, name: food.name, amount: amount, unit: food.unit, location: food.storage,
                                 expiry: Kitchen.defaultExpiry(for: food, location: food.storage, from: now), addedAt: now)
        }
        let q = r.quantity
        let name = r.name.prefix(1).uppercased() + r.name.dropFirst()
        return InventoryItem(foodId: nil, name: name, amount: q.map { $0.amount * $0.unit.factor } ?? 1,
                             unit: q?.unit.base ?? .piece, location: .cupboard, addedAt: now)
    }
}

struct EditItemView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var item: InventoryItem
    @State private var hasExpiry = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $item.name)
                    HStack {
                        Text("Amount")
                        Spacer()
                        TextField("Amount", value: $item.amount, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        Text(item.unit == .piece ? "" : item.unit.short).foregroundStyle(.secondary)
                    }
                    Picker("Kept in", selection: $item.location) {
                        ForEach(StorageLocation.allCases) { Text($0.title).tag($0) }
                    }
                    Toggle("Use-by date", isOn: $hasExpiry)
                    if hasExpiry {
                        DatePicker("Use by", selection: Binding(get: { item.expiry ?? Date() }, set: { item.expiry = $0 }), displayedComponents: .date)
                    }
                }
                if let f = FoodDatabase.food(item.foodId) {
                    Section("Nutrition per 100\(f.unit == .ml ? "ml" : "g")") { MacroLine(macros: f.per100) }
                } else if let m = item.customPer100 {
                    Section("Nutrition per 100g (from the label)") { MacroLine(macros: m) }
                }
                Section {
                    Button("Used it all up", role: .destructive) { model.finish(item); dismiss() }
                }
            }
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { hasExpiry = item.expiry != nil }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if !hasExpiry { item.expiry = nil }
                        if item.amount <= 0 { model.finish(item) } else { model.update(item) }
                        dismiss()
                    }
                }
            }
        }
    }
}
