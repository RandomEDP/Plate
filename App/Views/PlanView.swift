import PlateCore
import SwiftUI

struct PlanView: View {
    @Environment(AppModel.self) private var model
    @State private var settings = false
    @State private var cookingEntry: PlanEntry?

    var body: some View {
        NavigationStack {
            List {
                if model.household.plan.entries.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Plan your week").font(.headline)
                            Text("Choose how many breakfasts, lunches and dinners you want and for how many people. Plate picks recipes that use what you've got, share ingredients, and batch-cook well.")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Button { settings = true } label: { Label("Plan my week", systemImage: "wand.and.stars") }
                                .buttonStyle(.borderedProminent)
                        }
                        .padding(.vertical, 6)
                    }
                } else {
                    Section { summary }
                    prepSection
                }
                ForEach(0..<7, id: \.self) { day in
                    let entries = model.household.plan.entries.filter { $0.day == day }
                        .sorted { MealType.allCases.firstIndex(of: $0.meal)! < MealType.allCases.firstIndex(of: $1.meal)! }
                    if !entries.isEmpty {
                        Section(header: dayHeader(day)) {
                            ForEach(entries) { e in
                                if let r = model.recipe(e.recipeId) {
                                    entryRow(e, r)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Plan")
            .navigationDestination(for: Recipe.self) { RecipeDetailView(recipe: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { settings = true } label: { Image(systemName: "slider.horizontal.3") }
                        .accessibilityLabel("Plan settings")
                }
                if !model.household.plan.entries.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            let list = model.makeListFromPlan()
                            model.banner = "Made “\(list.name)”"
                            model.selectedTab = .shop
                        } label: { Label("Shopping list", systemImage: "cart") }
                    }
                }
            }
            .sheet(isPresented: $settings) { PlanSettingsView() }
            .sheet(item: $cookingEntry) { e in
                if let r = model.recipe(e.recipeId) { CookSheet(recipe: r, portions: e.servings, meal: e.meal) }
            }
        }
    }

    func dayHeader(_ day: Int) -> some View {
        let date = model.date(forDay: day)
        let isToday = Calendar.plate.isDateInToday(date)
        return HStack {
            Text(date.formatted(.dateTime.weekday(.wide).day().month()))
            if isToday { Text("Today").font(.caption2.weight(.bold)).foregroundStyle(Color.accentColor) }
        }
    }

    var summary: some View {
        let entries = model.household.plan.entries
        let recipes = entries.compactMap { model.recipe($0.recipeId) }
        let people = max(1, model.household.planSettings.people)
        let kcalPerDay = zip(entries, recipes).reduce(0.0) { $0 + Nutrition.perServing($1.1).kcal } / 7 / 1
        let proteinPerDay = zip(entries, recipes).reduce(0.0) { $0 + Nutrition.perServing($1.1).protein } / 7
        return VStack(alignment: .leading, spacing: 6) {
            Text("\(entries.count) meals · \(Set(entries.map(\.recipeId)).count) recipes · for \(people)")
                .font(.subheadline.weight(.semibold))
            Text("About \(Int(kcalPerDay.rounded())) kcal and \(Int(proteinPerDay.rounded()))g protein a day each, from planned meals.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// What to batch-cook: recipes appearing more than once, with total portions.
    @ViewBuilder var prepSection: some View {
        let groups = Dictionary(grouping: model.household.plan.entries.filter { !$0.cooked }, by: \.recipeId)
            .filter { $0.value.count > 1 }
        if !groups.isEmpty {
            Section {
                ForEach(Array(groups.keys), id: \.self) { id in
                    if let r = model.recipe(id), let es = groups[id] {
                        let portions = es.reduce(0) { $0 + $1.servings }
                        let first = es.map(\.day).min() ?? 0
                        HStack {
                            RecipeThumb(recipe: r, size: 32)
                            VStack(alignment: .leading) {
                                Text(r.name).font(.subheadline.weight(.medium))
                                Text("Cook \(portions) portions on \(model.date(forDay: first).formatted(.dateTime.weekday(.wide)))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Cook") {
                                cookingEntry = PlanEntry(day: first, meal: es[0].meal, recipeId: id, servings: portions)
                            }
                            .buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                }
            } header: { Text("Meal prep") } footer: { Text("Cook these once and keep the rest in the fridge.") }
        }
    }

    func entryRow(_ e: PlanEntry, _ r: Recipe) -> some View {
        NavigationLink(value: r) {
            HStack {
                RecipeThumb(recipe: r, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(e.meal.title).font(.caption).foregroundStyle(.secondary)
                    Text(r.name).strikethrough(e.cooked)
                    Text("\(e.servings) portion\(e.servings == 1 ? "" : "s") · \(Int(Nutrition.perServing(r).kcal.rounded())) kcal each")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if e.locked { Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary) }
                if e.cooked { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { model.household.plan.entries.removeAll { $0.id == e.id } } label: { Label("Remove", systemImage: "trash") }
            Button { model.swap(e) } label: { Label("Swap", systemImage: "arrow.triangle.2.circlepath") }.tint(.blue)
        }
        .swipeActions(edge: .leading) {
            Button { cookingEntry = e } label: { Label("Cook", systemImage: "frying.pan") }.tint(.green)
            Button {
                if let i = model.household.plan.entries.firstIndex(where: { $0.id == e.id }) { model.household.plan.entries[i].locked.toggle() }
            } label: { Label(e.locked ? "Unlock" : "Keep", systemImage: e.locked ? "lock.open" : "lock") }
            .tint(.gray)
        }
    }
}

struct PlanSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section {
                    Stepper("For \(model.household.planSettings.people) \(model.household.planSettings.people == 1 ? "person" : "people")",
                            value: $model.household.planSettings.people, in: 1...12)
                }
                mealSection("Breakfasts", count: $model.household.planSettings.breakfasts, variety: $model.household.planSettings.breakfastVariety)
                mealSection("Lunches", count: $model.household.planSettings.lunches, variety: $model.household.planSettings.lunchVariety)
                mealSection("Dinners", count: $model.household.planSettings.dinners, variety: $model.household.planSettings.dinnerVariety)
                mealSection("Snacks", count: $model.household.planSettings.snacks, variety: $model.household.planSettings.snackVariety)
                Section {
                    Button {
                        model.generatePlan()
                        model.banner = "Here's your week"
                        dismiss()
                    } label: { Label(model.household.plan.entries.isEmpty ? "Plan my week" : "Make a new plan", systemImage: "wand.and.stars") }
                    .buttonStyle(.borderedProminent)
                } footer: {
                    Text("Meals you've locked (swipe right on a meal → Keep) stay where they are.")
                }
            }
            .navigationTitle("Plan settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    func mealSection(_ title: String, count: Binding<Int>, variety: Binding<Int>) -> some View {
        Section(title) {
            Stepper("\(count.wrappedValue) a week", value: count, in: 0...14)
            if count.wrappedValue > 0 {
                Stepper("\(min(variety.wrappedValue, count.wrappedValue)) different recipe\(variety.wrappedValue == 1 ? "" : "s")",
                        value: variety, in: 1...max(1, count.wrappedValue))
            }
        }
    }
}
