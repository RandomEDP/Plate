import PlateCore
import SwiftUI

struct RecipesView: View {
    @Environment(AppModel.self) private var model
    @State private var filter: Filter = .all
    @State private var search = ""
    @State private var importing = false
    @State private var ideas = false
    @State private var newRecipe = false
    @State private var bulkImport = false
    @State private var selecting = false
    @FocusState private var searchFocused: Bool
    @State private var selected: Set<UUID> = []
    @State private var confirmDelete = false
    @State private var reimporting: [UUID]?
    @State private var waiting = false

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", ready = "Can make", favourites = "Favourites", breakfast = "Breakfast", lunch = "Lunch", dinner = "Dinner", snack = "Snacks", saved = "Saved"
        var id: String { rawValue }
    }

    var matches: [RecipeMatch] {
        let ranked = Suggestions.rank(model.recipes, inventory: model.household.inventory, servings: model.household.planSettings.people, now: Date())
        return ranked.filter { m in
            let r = m.recipe
            if !search.isEmpty && !r.name.localizedCaseInsensitiveContains(search)
                && !r.ingredients.contains(where: { $0.name.localizedCaseInsensitiveContains(search) }) { return false }
            switch filter {
            case .all: return true
            case .ready: return m.canCookNow || m.missingCount <= 1
            case .favourites: return r.isFavourite
            case .breakfast: return r.mealTypes.contains(.breakfast)
            case .lunch: return r.mealTypes.contains(.lunch)
            case .dinner: return r.mealTypes.contains(.dinner)
            case .snack: return r.mealTypes.contains(.snack)
            case .saved: return r.source.kind != .builtIn
            }
        }
    }

    func toggle(_ id: UUID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(Filter.allCases) { f in
                                Button(f.rawValue) { filter = f }
                                    .buttonStyle(.bordered)
                                    .tint(filter == f ? .accentColor : .secondary)
                                    .controlSize(.small)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color.clear)
                }
                Section {
                    HStack(spacing: 12) {
                        Button { importing = true } label: {
                            Label("From a Reel or TikTok", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        Button { ideas = true } label: {
                            Label("Ideas", systemImage: "sparkles").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    if !model.waitingVideos.isEmpty {
                        Button { waiting = true } label: {
                            Label("\(model.waitingVideos.count) waiting for a video", systemImage: "film.stack")
                        }
                        .accessibilityHint("Posts you shared whose recipe is only in the video")
                    }
                }
                Section {
                    if matches.isEmpty {
                        Text(filter == .ready ? "Nothing you can make right now. Add more to your kitchen, or try Ideas." : "No recipes here yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(matches) { m in
                        if selecting {
                            Button { toggle(m.recipe.id) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: selected.contains(m.recipe.id) ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                        .foregroundStyle(selected.contains(m.recipe.id) ? Color.accentColor : .secondary)
                                    RecipeRow(recipe: m.recipe, match: m)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selected.contains(m.recipe.id) ? .isSelected : [])
                        } else {
                            NavigationLink(value: m.recipe) { RecipeRow(recipe: m.recipe, match: m) }
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Search recipes or ingredients")
            .searchFocused($searchFocused)
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("Recipes")
            .navigationDestination(for: Recipe.self) { RecipeDetailView(recipe: $0) }
            .toolbar {
                // On the right with the other buttons: iPad (iOS 26) hides the left-hand slot next to the search field.
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        selecting.toggle()
                        selected = []
                        searchFocused = false
                    } label: {
                        if selecting { Text("Done").bold() } else { Label("Select", systemImage: "checkmark.circle") }
                    }
                    .disabled(!selecting && matches.isEmpty)
                    .accessibilityLabel(selecting ? "Done selecting" : "Select recipes")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { searchFocused = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { bulkImport = true } label: { Image(systemName: "square.and.arrow.down.on.square") }
                        .accessibilityLabel("Import many recipes")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { newRecipe = true } label: { Image(systemName: "square.and.pencil") }
                        .accessibilityLabel("Write a recipe")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if selecting {
                    HStack {
                        let shown = Set(matches.map(\.recipe.id))
                        Button(shown.isSubset(of: selected) ? "Select none" : "Select all") {
                            if shown.isSubset(of: selected) { selected.subtract(shown) } else { selected.formUnion(shown) }
                        }
                        Spacer()
                        let linked = model.household.recipes.filter { selected.contains($0.id) && $0.source.url != nil }.map(\.id)
                        Button { reimporting = linked } label: {
                            Label(linked.isEmpty ? "Re-import" : "Re-import \(linked.count)", systemImage: "arrow.clockwise")
                        }
                        .disabled(linked.isEmpty)
                        .accessibilityHint("Reads the chosen recipes again from the links they came from")
                        Spacer()
                        Button(role: .destructive) { confirmDelete = true } label: {
                            Label(selected.isEmpty ? "Delete" : "Delete \(selected.count)", systemImage: "trash")
                        }
                        .disabled(selected.isEmpty)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.bar)
                }
            }
            .confirmationDialog("Delete \(selected.count) recipe\(selected.count == 1 ? "" : "s")?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete \(selected.count) recipe\(selected.count == 1 ? "" : "s")", role: .destructive) {
                    let n = selected.count
                    model.delete(selected)
                    selected = []
                    selecting = false
                    model.banner = "Deleted \(n) recipe\(n == 1 ? "" : "s")"
                }
            } message: {
                Text("They'll also come off your meal plan and shopping lists. Built-in recipes are only hidden.")
            }
            .sheet(isPresented: $importing) { ImportRecipeView() }
            .sheet(isPresented: $ideas) { IdeasView() }
            .sheet(isPresented: $bulkImport) { BulkImportView() }
            .sheet(isPresented: $waiting) { WaitingVideosView() }
            .sheet(isPresented: Binding(get: { reimporting != nil }, set: { if !$0 { reimporting = nil } })) {
                ReimportView(ids: reimporting ?? [])
                    .onDisappear { selected = []; selecting = false }
            }
            .sheet(isPresented: $newRecipe) {
                RecipeEditor(recipe: Recipe(name: "", mealTypes: [.dinner], servings: 2, ingredients: [], steps: [])) { model.save($0) }
            }
        }
    }
}

struct RecipeDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let recipe: Recipe
    @State private var servings: Int = 0
    @State private var cooking = false
    @State private var addingToList = false
    @State private var addingToPlan = false
    @State private var editing = false
    @State private var confirmDelete = false

    /// The latest saved copy (favourite, edits), falling back to what was passed in (e.g. an unsaved variation).
    var current: Recipe { model.recipe(recipe.id) ?? recipe }
    var isSaved: Bool { model.recipe(recipe.id) != nil }

    var body: some View {
        let r = current
        let s = servings == 0 ? max(model.household.planSettings.people, 1) : servings
        let match = Suggestions.evaluate(r, servings: s, stock: model.stock)
        let missingKeys = Set((match.missing + match.short).map(\.key))
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        RecipeThumb(recipe: r, size: 64)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(r.name).font(.title2.weight(.bold))
                            if !r.summary.isEmpty { Text(r.summary).font(.subheadline).foregroundStyle(.secondary) }
                            HStack(spacing: 10) {
                                if let m = r.minutes { Label("\(m) min", systemImage: "clock") }
                                Text(r.mealTypes.map(\.title).joined(separator: " · "))
                                if r.mealPrepFriendly { Label("Meal prep", systemImage: "takeoutbag.and.cup.and.straw") }
                            }
                            .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text("Per portion").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    MacroLine(macros: Nutrition.perServing(r))
                    if r.statedPerServing != nil {
                        Text("Macros as given by the creator.").font(.caption2).foregroundStyle(.secondary)
                    } else if Nutrition.computed(r).coverage < 0.9 {
                        Text("Some ingredients couldn't be counted, so these are a low estimate.").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .listRowBackground(Color.clear)
            }
            Section {
                if isSaved {
                    Button { cooking = true } label: { Label("Cook this", systemImage: "frying.pan") }
                    Button { addingToList = true } label: { Label("Add to a shopping list", systemImage: "cart.badge.plus") }
                    Button { addingToPlan = true } label: { Label("Add to the plan", systemImage: "calendar.badge.plus") }
                } else {
                    Button { model.save(r); model.banner = "Saved \(r.name)" } label: { Label("Save this recipe", systemImage: "square.and.arrow.down") }
                }
            }
            Section {
                Stepper("\(s) portion\(s == 1 ? "" : "s")", value: Binding(get: { s }, set: { servings = $0 }), in: 1...40)
                ForEach(Array(zip(r.ingredients, Nutrition.needs(r, servings: s))), id: \.0.id) { ing, need in
                    HStack(alignment: .firstTextBaseline) {
                        if !need.isStaple && !need.optional {
                            Image(systemName: missingKeys.contains(need.key) ? "circle" : "checkmark.circle.fill")
                                .foregroundStyle(missingKeys.contains(need.key) ? Color.secondary : Color.green)
                        } else {
                            Image(systemName: "circle.dotted").foregroundStyle(.tertiary)
                        }
                        VStack(alignment: .leading) {
                            Text(ingredientText(ing, scale: Double(s) / Double(r.servings)))
                            if let note = ing.note { Text(note).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            } header: {
                Text("Ingredients")
            } footer: {
                if !match.canCookNow { Text("Ticked: you have enough in the kitchen. Dotted: store-cupboard basics or optional.") }
            }
            if !r.steps.isEmpty {
                Section("Method") {
                    ForEach(Array(r.steps.enumerated()), id: \.offset) { i, step in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(i + 1)").font(.subheadline.weight(.bold)).foregroundStyle(Color.accentColor)
                            Text(step)
                        }
                    }
                }
            }
            VariationsSection(recipe: r)
            if let link = r.source.url, let url = URL(string: link) {
                Section("Source") {
                    Link(destination: url) {
                        Label(r.source.author.map { "Watch @\($0)'s video" } ?? "Open the original", systemImage: "play.rectangle")
                    }
                }
            }
            if isSaved {
                Section {
                    Button("Edit recipe") { editing = true }
                    Button(model.isBuiltIn(r) ? "Remove from my recipes" : "Delete recipe", role: .destructive) { confirmDelete = true }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isSaved {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { model.toggleFavourite(r) } label: { Image(systemName: r.isFavourite ? "heart.fill" : "heart") }
                        .tint(.pink)
                        .accessibilityLabel(r.isFavourite ? "Unfavourite" : "Favourite")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: shareText(r)) { Image(systemName: "square.and.arrow.up") }
                }
            }
        }
        .sheet(isPresented: $cooking) { CookSheet(recipe: r, portions: s, meal: r.mealTypes.first ?? .dinner) }
        .sheet(isPresented: $addingToList) { AddToListSheet(recipe: r, servings: s) }
        .sheet(isPresented: $addingToPlan) { AddToPlanSheet(recipe: r, servings: s) }
        .sheet(isPresented: $editing) { RecipeEditor(recipe: r) { model.save($0) } }
        .confirmationDialog("Remove \(r.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { model.delete(r); dismiss() }
        }
    }

    func ingredientText(_ ing: RecipeIngredient, scale: Double) -> String {
        guard let q = ing.quantity else { return ing.name.prefix(1).uppercased() + ing.name.dropFirst() }
        let scaled = Quantity(q.amount * scale, q.unit)
        return "\(Format.quantity(scaled)) \(ing.name)"
    }

    func shareText(_ r: Recipe) -> String {
        var lines = [r.name, ""]
        lines += r.ingredients.map { ingredientText($0, scale: 1) }.map { "• " + $0 }
        lines.append("")
        lines += r.steps.enumerated().map { "\($0.offset + 1). \($0.element)" }
        lines += ["", "Serves \(r.servings) · \(Format.macros(Nutrition.perServing(r))) per portion", "Made with Plate"]
        return lines.joined(separator: "\n")
    }
}

struct VariationsSection: View {
    @Environment(AppModel.self) private var model
    let recipe: Recipe

    var body: some View {
        let vs = Variations.of(recipe, inventory: model.household.inventory)
        if !vs.isEmpty {
            Section {
                ForEach(vs) { v in
                    NavigationLink(value: v.recipe) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(v.recipe.name).font(.subheadline.weight(.medium))
                            Text(v.swaps.map { "\($0.from) → \($0.to)" }.joined(separator: ", "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Variations")
            } footer: {
                Text("Swaps that use what's in your kitchen, or a different main ingredient for a change.")
            }
        }
    }
}

/// Cook a recipe: how many portions you're making, how many you're eating now, and whether to take the ingredients
/// out of the kitchen. Extra portions go in the fridge as prepped meals.
struct CookSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let recipe: Recipe
    @State var portions: Int
    @State var meal: MealType
    @State private var eating = 1.0
    @State private var useKitchen = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper("Making \(portions) portion\(portions == 1 ? "" : "s")", value: $portions, in: 1...40)
                    Stepper("Eating \(Format.number(eating, places: 1)) now", value: $eating, in: 0...Double(portions), step: 0.5)
                    Picker("Meal", selection: $meal) { ForEach(MealType.allCases) { Text($0.title).tag($0) } }
                    Toggle("Take the ingredients out of my kitchen", isOn: $useKitchen)
                } footer: {
                    let left = Double(portions) - eating
                    if left >= 1 {
                        Text("\(Int(left)) portion\(Int(left) == 1 ? "" : "s") will go in the fridge as prepped meals for later.")
                    }
                }
                Section("You'll log") { MacroLine(macros: Nutrition.perServing(recipe) * eating) }
            }
            .navigationTitle(recipe.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        model.cook(recipe, portionsMade: portions, portionsEaten: eating, meal: meal, useKitchen: useKitchen)
                        model.banner = "Enjoy your \(recipe.name.lowercased())"
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct AddToListSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let recipe: Recipe
    @State var servings: Int
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            Form {
                Stepper("\(servings) portion\(servings == 1 ? "" : "s")", value: $servings, in: 1...40)
                Section("Add to") {
                    ForEach(model.household.lists) { list in
                        Button(list.name) { add(to: list.id) }
                    }
                    HStack {
                        TextField("New list", text: $newName)
                        Button("Create") {
                            let l = ShoppingList(name: newName.isEmpty ? "Shopping" : newName, stores: model.household.stores)
                            model.household.lists.insert(l, at: 0)
                            add(to: l.id)
                        }
                    }
                }
            }
            .navigationTitle("Add to a list")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    func add(to id: UUID) {
        guard var l = model.list(id) else { return }
        if let i = l.meals.firstIndex(where: { $0.recipeId == recipe.id }) { l.meals[i].servings += servings }
        else { l.meals.append(ListMeal(recipeId: recipe.id, servings: servings)) }
        model.update(l)
        model.banner = "Added to \(l.name)"
        dismiss()
    }
}

struct AddToPlanSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let recipe: Recipe
    @State var servings: Int
    @State private var day = 0
    @State private var meal: MealType = .dinner

    var body: some View {
        NavigationStack {
            Form {
                Picker("Day", selection: $day) {
                    ForEach(0..<7, id: \.self) { d in Text(model.date(forDay: d).formatted(.dateTime.weekday(.wide).day())).tag(d) }
                }
                Picker("Meal", selection: $meal) { ForEach(MealType.allCases) { Text($0.title).tag($0) } }
                Stepper("\(servings) portion\(servings == 1 ? "" : "s")", value: $servings, in: 1...40)
            }
            .navigationTitle("Add to the plan")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                meal = recipe.mealTypes.first ?? .dinner
                day = max(0, model.dayIndex(for: Date()))
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        model.addToPlan(recipe, day: day, meal: meal, servings: servings)
                        model.banner = "Added to the plan"
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// Write or edit a recipe. Ingredients are typed one per line, the same way they appear in captions.
struct RecipeEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var recipe: Recipe
    let onSave: (Recipe) -> Void
    @State private var ingredientText = ""
    @State private var stepText = ""
    @State private var kcal = ""
    @State private var protein = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $recipe.name)
                    Stepper("Makes \(recipe.servings) portion\(recipe.servings == 1 ? "" : "s")", value: $recipe.servings, in: 1...40)
                    HStack {
                        ForEach(MealType.allCases) { m in
                            Button(m.title) {
                                if recipe.mealTypes.contains(m) { recipe.mealTypes.removeAll { $0 == m } } else { recipe.mealTypes.append(m) }
                            }
                            .buttonStyle(.bordered)
                            .tint(recipe.mealTypes.contains(m) ? .accentColor : .secondary)
                            .controlSize(.small)
                        }
                    }
                    Toggle("Good for meal prep", isOn: $recipe.mealPrepFriendly)
                }
                Section {
                    TextEditor(text: $ingredientText).frame(minHeight: 140)
                } header: { Text("Ingredients") } footer: { Text("One per line, e.g. “200g chicken breast”.") }
                Section("Method") {
                    TextEditor(text: $stepText).frame(minHeight: 140)
                }
                Section {
                    TextField("Calories per portion", text: $kcal).keyboardType(.numberPad)
                    TextField("Protein per portion (g)", text: $protein).keyboardType(.numberPad)
                } header: { Text("Macros (optional)") } footer: { Text("Leave blank and Plate works them out from the ingredients.") }
            }
            .navigationTitle(recipe.name.isEmpty ? "New recipe" : "Edit recipe")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                ingredientText = recipe.ingredients.map { ing in
                    let q = ing.quantity.map { Format.quantity($0) + " " } ?? ""
                    return q + ing.name + (ing.note.map { ", " + $0 } ?? "")
                }.joined(separator: "\n")
                stepText = recipe.steps.joined(separator: "\n")
                if let s = recipe.statedPerServing {
                    kcal = String(Int(s.kcal)); protein = String(Int(s.protein))
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var r = recipe
                        r.ingredients = ingredientText.split(separator: "\n").compactMap { line in
                            IngredientParser.ingredient(String(line)) ?? {
                                let t = line.trimmingCharacters(in: .whitespaces)
                                return t.isEmpty ? nil : RecipeIngredient(name: t, foodId: nil, quantity: nil)
                            }()
                        }
                        r.steps = stepText.split(separator: "\n").map { RecipeTextParser.stripStepNumber(String($0)) }.filter { !$0.isEmpty }
                        if let k = Double(kcal) {
                            r.statedPerServing = Macros(kcal: k, protein: Double(protein) ?? 0,
                                                        carbs: r.statedPerServing?.carbs ?? 0, fat: r.statedPerServing?.fat ?? 0)
                        } else {
                            r.statedPerServing = nil
                        }
                        if r.mealTypes.isEmpty { r.mealTypes = [.dinner] }
                        onSave(r)
                        dismiss()
                    }
                    .disabled(recipe.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
