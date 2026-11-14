import PlateCore
import SwiftUI

struct ShopView: View {
    @Environment(AppModel.self) private var model
    @State private var newList = false
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                if model.household.lists.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("No shopping lists yet").font(.headline)
                            Text("Make a list and pick the meals you want: Plate adds up everything they need, takes off what's already in your kitchen, and picks the best packs at Sainsbury's and Costco.")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Button { newList = true } label: { Label("New list", systemImage: "plus") }
                                .buttonStyle(.borderedProminent)
                        }
                        .padding(.vertical, 6)
                    }
                }
                ForEach(model.household.lists) { list in
                    NavigationLink(value: list.id) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(list.name).font(.body.weight(.medium))
                            let res = model.result(for: list)
                            Text("\(list.meals.count) meal\(list.meals.count == 1 ? "" : "s") · \(res.toBuy.count) to buy · about \(Format.money(res.totalCost))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { idx in model.household.lists.remove(atOffsets: idx) }
            }
            .navigationTitle("Shop")
            .navigationDestination(for: UUID.self) { ListDetailView(listId: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { newList = true } label: { Image(systemName: "plus") }.accessibilityLabel("New list")
                }
            }
            .alert("New list", isPresented: $newList) {
                TextField("Name", text: $newName)
                Button("Create") {
                    model.household.lists.insert(ShoppingList(name: newName.isEmpty ? "Shopping" : newName, stores: model.household.stores), at: 0)
                    newName = ""
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}

struct ListDetailView: View {
    @Environment(AppModel.self) private var model
    let listId: UUID
    @State private var pickingMeals = false
    @State private var manual = ""
    @State private var confirmPutAway = false

    var body: some View {
        if let list = model.list(listId) {
            content(list)
        } else {
            ContentUnavailableView("List deleted", systemImage: "cart")
        }
    }

    func content(_ list: ShoppingList) -> some View {
        let res = model.result(for: list)
        let toBuy = res.toBuy
        let byStore = Dictionary(grouping: toBuy) { $0.store?.title ?? "Anywhere" }
        let storeOrder = byStore.keys.sorted { a, b in a == "Anywhere" ? false : b == "Anywhere" ? true : a < b }
        return List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("About \(Format.money(res.totalCost))").font(.title3.weight(.bold))
                        Spacer()
                        Text("\(list.checked.intersection(Set(toBuy.map(\.key))).count) of \(toBuy.count) in the trolley")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if res.totalSaving > 0.05 {
                        Label("Bulk buys save about \(Format.money(res.totalSaving))", systemImage: "tag")
                            .font(.subheadline).foregroundStyle(.green)
                    }
                    HStack {
                        ForEach(Store.allCases) { store in
                            let on = list.stores.contains(store)
                            Button {
                                var l = list
                                if on { l.stores.removeAll { $0 == store } } else { l.stores.append(store) }
                                if l.stores.isEmpty { l.stores = [store == .costco ? .sainsburys : .costco] }
                                model.update(l)
                            } label: { Label(store.title, systemImage: on ? "checkmark.circle.fill" : "circle") }
                            .buttonStyle(.bordered).controlSize(.small)
                            .tint(on ? .accentColor : .secondary)
                        }
                    }
                    Toggle("Take off what's in my kitchen", isOn: Binding(get: { list.useKitchen }, set: { var l = list; l.useKitchen = $0; model.update(l) }))
                        .font(.subheadline)
                    Text("Prices are rough guides for comparing packs, not live prices.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }

            Section {
                ForEach(list.meals) { m in
                    if let r = model.recipe(m.recipeId) {
                        Stepper(value: Binding(get: { m.servings }, set: { v in
                            var l = list
                            if let i = l.meals.firstIndex(where: { $0.id == m.id }) { l.meals[i].servings = v }
                            model.update(l)
                        }), in: 1...60) {
                            VStack(alignment: .leading) {
                                Text(r.name).font(.subheadline)
                                Text("\(m.servings) portion\(m.servings == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .onDelete { idx in var l = list; l.meals.remove(atOffsets: idx); model.update(l) }
                Button { pickingMeals = true } label: { Label("Add meals", systemImage: "plus.circle") }
            } header: { Text("Meals") }

            ForEach(storeOrder, id: \.self) { store in
                Section(store) {
                    ForEach(byStore[store] ?? []) { line in lineRow(line, list) }
                }
            }

            Section {
                HStack {
                    TextField("Add something else", text: $manual)
                        .onSubmit(addManual)
                    Button("Add", action: addManual).disabled(manual.isEmpty)
                }
                ForEach(list.manualItems) { item in
                    Text(item.name).foregroundStyle(.secondary).font(.caption)
                }
                .onDelete { idx in var l = list; l.manualItems.remove(atOffsets: idx); model.update(l) }
            } header: { Text("Extras") }

            let covered = res.covered
            if !covered.isEmpty {
                Section {
                    ForEach(covered) { line in
                        HStack {
                            Text(line.name).foregroundStyle(.secondary)
                            Spacer()
                            if let need = line.need, let unit = line.unit {
                                Text("need \(Format.amount(need, unit)), have \(Format.amount(line.inStock, unit))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: { Text("Already in your kitchen") }
            }
        }
        .navigationTitle(list.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: shareText(list, res)) { Image(systemName: "square.and.arrow.up") }
            }
            ToolbarItem(placement: .bottomBar) {
                Button { confirmPutAway = true } label: { Label("Put the shopping away", systemImage: "refrigerator") }
                    .disabled(list.checked.intersection(Set(toBuy.map(\.key))).isEmpty)
            }
        }
        .confirmationDialog("Add everything ticked to your kitchen?", isPresented: $confirmPutAway, titleVisibility: .visible) {
            Button("Put it away") {
                let n = model.putAway(list)
                model.banner = "Added \(n) item\(n == 1 ? "" : "s") to your kitchen"
            }
        }
        .sheet(isPresented: $pickingMeals) { MealPickerView(listId: listId) }
    }

    func lineRow(_ line: ShoppingLine, _ list: ShoppingList) -> some View {
        let checked = list.checked.contains(line.key)
        return Button {
            var l = list
            if checked { l.checked.remove(line.key) } else { l.checked.insert(line.key) }
            model.update(l)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(checked ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.name).strikethrough(checked).foregroundStyle(checked ? .secondary : .primary)
                    if !line.buyText.isEmpty {
                        Text(line.buyText).font(.caption).foregroundStyle(.secondary)
                    }
                    if line.inStock > 0, let unit = line.unit {
                        Text("You have \(Format.amount(line.inStock, unit))").font(.caption2).foregroundStyle(.secondary)
                    }
                    if let note = line.savingNote {
                        Label(note, systemImage: "tag").font(.caption2).foregroundStyle(.green)
                    }
                    if !line.meals.isEmpty {
                        Text("For " + line.meals.joined(separator: ", ")).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                    }
                }
                Spacer()
                if let cost = line.cost { Text(Format.money(cost)).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    func addManual() {
        guard var l = model.list(listId), !manual.isEmpty else { return }
        let parsed = IngredientParser.parse(manual)
        let food = parsed?.food
        var amount: Double?
        var unit: BaseUnit?
        if let q = parsed?.quantity {
            if let food, let v = Units.amountInFoodUnit(q, food: food) { amount = v; unit = food.unit }
            else { amount = q.amount * q.unit.factor; unit = q.unit.base }
        }
        l.manualItems.append(ManualItem(name: food?.name ?? manual, foodId: food?.id, amount: amount, unit: unit))
        model.update(l)
        manual = ""
    }

    func shareText(_ list: ShoppingList, _ res: ShoppingResult) -> String {
        var out = [list.name]
        for line in res.toBuy {
            out.append("☐ \(line.name)\(line.buyText.isEmpty ? "" : " – \(line.buyText)")\(line.store.map { " (\($0.title))" } ?? "")")
        }
        return out.joined(separator: "\n")
    }
}

/// Pick meals for a list, or let Plate suggest a set of breakfasts, lunches and dinners.
struct MealPickerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let listId: UUID
    @State private var picked: [UUID: Int] = [:]
    @State private var search = ""
    @State private var suggest = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { suggest = true } label: { Label("Suggest meals for me", systemImage: "wand.and.stars") }
                }
                ForEach(MealType.allCases) { meal in
                    let rs = model.recipes.filter { !$0.isSauce && $0.mealTypes.first == meal }
                        .filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
                    if !rs.isEmpty {
                        Section(meal.title) {
                            ForEach(rs) { r in row(r) }
                        }
                    }
                }
                let sauces = model.recipes.filter { $0.isSauce }
                    .filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
                if !sauces.isEmpty {
                    Section("Sauces") {
                        ForEach(sauces) { r in row(r) }
                    }
                }
            }
            .searchable(text: $search)
            .navigationTitle("Add meals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add \(picked.count)") {
                        if var l = model.list(listId) {
                            for (id, servings) in picked {
                                if let i = l.meals.firstIndex(where: { $0.recipeId == id }) { l.meals[i].servings += servings }
                                else { l.meals.append(ListMeal(recipeId: id, servings: servings)) }
                            }
                            model.update(l)
                        }
                        dismiss()
                    }
                    .disabled(picked.isEmpty)
                }
            }
            .sheet(isPresented: $suggest) {
                SuggestMealsView { suggestions in
                    for (id, s) in suggestions { picked[id, default: 0] += s }
                }
            }
        }
    }

    func row(_ r: Recipe) -> some View {
        let people = max(1, model.household.planSettings.people)
        let on = picked[r.id] != nil
        return HStack {
            Button {
                if on { picked[r.id] = nil } else { picked[r.id] = people }
            } label: {
                HStack {
                    Image(systemName: on ? "checkmark.circle.fill" : "circle").foregroundStyle(on ? Color.accentColor : .secondary)
                    VStack(alignment: .leading) {
                        Text(r.name)
                        MacroLine(macros: Nutrition.perServing(r))
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer()
            if let n = picked[r.id] {
                Stepper("\(n)", value: Binding(get: { n }, set: { picked[r.id] = $0 }), in: 1...60)
                    .labelsHidden()
                Text("\(n)").monospacedDigit().frame(minWidth: 20)
            }
        }
    }
}

/// "3 breakfasts, 5 lunches, 4 dinners for 2": picks a set that shares ingredients, using the planner.
struct SuggestMealsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let onPick: ([UUID: Int]) -> Void
    @State private var people = 1
    @State private var breakfasts = 5
    @State private var lunches = 5
    @State private var dinners = 5
    @State private var snacks = 0

    var body: some View {
        NavigationStack {
            Form {
                Stepper("For \(people) \(people == 1 ? "person" : "people")", value: $people, in: 1...12)
                Stepper("\(breakfasts) breakfasts", value: $breakfasts, in: 0...14)
                Stepper("\(lunches) lunches", value: $lunches, in: 0...14)
                Stepper("\(dinners) dinners", value: $dinners, in: 0...14)
                Stepper("\(snacks) snacks", value: $snacks, in: 0...14)
                Section {
                    Text("Plate picks fewer different recipes than meals so you can batch-cook, and prefers ones that share ingredients so nothing goes to waste.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Suggest meals")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { people = max(1, model.household.planSettings.people) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Suggest") {
                        let s = PlanSettings(people: people, breakfasts: breakfasts, lunches: lunches, dinners: dinners, snacks: snacks,
                                             breakfastVariety: max(1, (breakfasts + 3) / 4), lunchVariety: max(1, (lunches + 2) / 3),
                                             dinnerVariety: max(1, (dinners + 1) / 2), snackVariety: max(1, (snacks + 3) / 4))
                        let entries = Planner.generate(recipes: model.recipes, inventory: model.household.inventory,
                                                       options: .init(settings: s, seed: UInt64.random(in: 1...999_999), dailyKcal: model.targets.kcal),
                                                       now: Date())
                        var out: [UUID: Int] = [:]
                        for e in entries { out[e.recipeId, default: 0] += e.servings }
                        onPick(out)
                        dismiss()
                    }
                }
            }
        }
    }
}
