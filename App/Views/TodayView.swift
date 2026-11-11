import PlateCore
import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var model
    @State private var showSettings = false
    @State private var showQuickLog = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    macrosCard
                    planToday
                    cookNow
                    useSoon
                    runningLow
                    eatenToday
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button { showQuickLog = true } label: { Label("Log food", systemImage: "plus.circle") }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showQuickLog) { QuickLogView() }
            .navigationDestination(for: Recipe.self) { RecipeDetailView(recipe: $0) }
        }
    }

    var macrosCard: some View {
        let t = model.totals(on: Date())
        let target = model.targets
        return HStack(spacing: 18) {
            CalorieRing(value: t.kcal, target: target.kcal)
            VStack(spacing: 10) {
                MacroBar(title: "Protein", value: t.protein, target: target.protein, unit: "g", color: .protein)
                MacroBar(title: "Carbs", value: t.carbs, target: target.carbs, unit: "g", color: .carbs)
                MacroBar(title: "Fat", value: t.fat, target: target.fat, unit: "g", color: .fat)
            }
        }
        .card()
    }

    @ViewBuilder var planToday: some View {
        let day = model.dayIndex(for: Date())
        let entries = model.household.plan.entries.filter { $0.day == day }
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("On the plan today").font(.headline)
                ForEach(entries) { e in
                    if let r = model.recipe(e.recipeId) {
                        PlannedMealRow(entry: e, recipe: r)
                    }
                }
            }
            .card()
        }
    }

    @ViewBuilder var cookNow: some View {
        let ranked = Suggestions.rank(model.recipes, inventory: model.household.inventory, servings: model.household.planSettings.people, now: Date())
        let ready = ranked.filter(\.canCookNow)
        let nearly = ranked.filter { !$0.canCookNow && $0.missingCount <= 2 }
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(ready.isEmpty ? "Nearly there" : "You can make").font(.headline)
                Spacer()
                Button("See all") { model.selectedTab = .recipes }.font(.subheadline)
            }
            if model.household.inventory.isEmpty {
                Text("Add what's in your fridge and cupboards and Plate will tell you what you can make.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button { model.selectedTab = .kitchen } label: { Label("Fill your kitchen", systemImage: "refrigerator") }
                    .buttonStyle(.borderedProminent)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach((ready.isEmpty ? nearly : ready).prefix(8)) { m in
                            NavigationLink(value: m.recipe) { SuggestionCard(match: m) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                if ready.isEmpty && nearly.isEmpty {
                    Text("Nothing quite matches yet. Try Recipes → Ideas for something new from what you've got.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder var useSoon: some View {
        let soon = Kitchen.expiringSoon(model.household.inventory, within: 3, now: Date())
        if !soon.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Use soon").font(.headline)
                ForEach(soon.prefix(6)) { item in
                    HStack {
                        Text(item.name)
                        Spacer()
                        Text(item.amountText).foregroundStyle(.secondary)
                        ExpiryBadge(date: item.expiry)
                    }
                    .font(.subheadline)
                }
            }
            .card()
        }
    }

    @ViewBuilder var runningLow: some View {
        let low = Kitchen.runningLow(model.household.inventory, usage: model.household.usage, now: Date())
        if !low.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Running low").font(.headline)
                Text("Based on how quickly you've been using them.").font(.caption).foregroundStyle(.secondary)
                ForEach(low.prefix(6), id: \.foodId) { l in
                    if let food = FoodDatabase.food(l.foodId) {
                        HStack {
                            Text(food.name)
                            Spacer()
                            Text(l.daysLeft.map { "about \(max(0, Int($0.rounded()))) days left" } ?? "run out")
                                .foregroundStyle(.secondary)
                            Button {
                                addToShopping(food)
                            } label: { Image(systemName: "cart.badge.plus") }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Add \(food.name) to shopping list")
                        }
                        .font(.subheadline)
                    }
                }
            }
            .card()
        }
    }

    @ViewBuilder var eatenToday: some View {
        let entries = model.entries(on: Date())
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Eaten today").font(.headline)
                ForEach(entries) { e in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(e.title).font(.subheadline)
                            Text(e.meal.title).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(Int(e.macros.kcal.rounded())) kcal").font(.subheadline.monospacedDigit())
                        Button(role: .destructive) {
                            model.household.log.removeAll { $0.id == e.id }
                        } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove")
                    }
                }
            }
            .card()
        }
    }

    func addToShopping(_ food: Food) {
        if model.household.lists.isEmpty {
            model.household.lists.append(ShoppingList(name: "Shopping", stores: model.household.stores))
        }
        if !model.household.lists[0].manualItems.contains(where: { $0.foodId == food.id }) {
            model.household.lists[0].manualItems.append(ManualItem(name: food.name, foodId: food.id))
        }
        model.banner = "Added \(food.name) to \(model.household.lists[0].name)"
    }
}

struct SuggestionCard: View {
    let match: RecipeMatch
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RecipeThumb(recipe: match.recipe, size: 56)
            Text(match.recipe.name).font(.subheadline.weight(.semibold)).lineLimit(2, reservesSpace: true)
            Text("\(Int(Nutrition.perServing(match.recipe).kcal.rounded())) kcal · \(Int(Nutrition.perServing(match.recipe).protein.rounded()))g protein")
                .font(.caption).foregroundStyle(.secondary)
            MatchBadge(match: match)
            if match.usesExpiring > 0 {
                Label("Uses food going off", systemImage: "leaf").font(.caption2).foregroundStyle(.orange)
            }
        }
        .frame(width: 160, alignment: .leading)
        .card()
    }
}

struct PlannedMealRow: View {
    @Environment(AppModel.self) private var model
    let entry: PlanEntry
    let recipe: Recipe
    @State private var cooking = false

    var body: some View {
        HStack {
            NavigationLink(value: recipe) {
                HStack {
                    RecipeThumb(recipe: recipe, size: 36)
                    VStack(alignment: .leading) {
                        Text(entry.meal.title).font(.caption).foregroundStyle(.secondary)
                        Text(recipe.name).font(.subheadline.weight(.medium))
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer()
            if entry.cooked {
                Label("Done", systemImage: "checkmark.circle.fill").labelStyle(.iconOnly).foregroundStyle(.green)
            } else {
                Button("Cook") { cooking = true }.buttonStyle(.bordered).controlSize(.small)
            }
        }
        .sheet(isPresented: $cooking) {
            CookSheet(recipe: recipe, portions: entry.servings, meal: entry.meal)
        }
    }
}

/// Log something eaten that isn't a recipe: a food from the list, or calories typed in.
struct QuickLogView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var food: Food?
    @State private var grams = 100.0
    @State private var meal: MealType = .snack
    @State private var title = ""
    @State private var kcal = ""
    @State private var protein = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker("Meal", selection: $meal) {
                    ForEach(MealType.allCases) { Text($0.title).tag($0) }
                }
                Section("From the food list") {
                    TextField("Search, e.g. banana", text: $search)
                    if food == nil && !search.isEmpty {
                        ForEach(FoodMatcher.search(search, limit: 6)) { f in
                            Button(f.name) { food = f; grams = f.gramsPerPiece ?? 100 }
                        }
                    }
                    if let food {
                        HStack {
                            Text(food.name).fontWeight(.medium)
                            Spacer()
                            Button("Change") { self.food = nil }
                        }
                        Stepper("\(Int(grams)) g", value: $grams, in: 5...2000, step: food.gramsPerPiece.map { $0 >= 20 ? $0 : 10 } ?? 10)
                        MacroLine(macros: food.per100 * (grams / 100))
                    }
                }
                Section("Or type it in") {
                    TextField("What was it?", text: $title)
                    TextField("Calories", text: $kcal).keyboardType(.numberPad)
                    TextField("Protein (g)", text: $protein).keyboardType(.numberPad)
                }
            }
            .navigationTitle("Log food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") {
                        if let food {
                            model.logQuick(title: "\(food.name) (\(Int(grams))g)", macros: food.per100 * (grams / 100), meal: meal)
                        } else if let k = Double(kcal) {
                            model.logQuick(title: title.isEmpty ? "Food" : title, macros: Macros(kcal: k, protein: Double(protein) ?? 0), meal: meal)
                        }
                        dismiss()
                    }
                    .disabled(food == nil && Double(kcal) == nil)
                }
            }
        }
    }
}
