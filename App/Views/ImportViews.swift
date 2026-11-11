import PlateCore
import SwiftUI

extension AppModel {
    var aiChoice: AIChoice {
        get { AIChoice(rawValue: household.extras["ai"] ?? "") ?? .automatic }
        set { household.extras["ai"] = newValue.rawValue }
    }
    var claudeModel: ClaudeModel {
        get { ClaudeModel(rawValue: household.extras["claudeModel"] ?? "") ?? .opus }
        set { household.extras["claudeModel"] = newValue.rawValue }
    }
    var aiEngine: RecipeAIEngine? { AIService.engine(choice: aiChoice, claudeModel: claudeModel) }
}

/// Paste a Reel or TikTok link (or the caption itself). Plate fetches the caption, reads the recipe, and lets you
/// check it before saving.
struct ImportRecipeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var caption = ""
    @State private var link: String?
    @State private var author: String?
    @State private var platform: SocialImport.Platform?
    @State private var working = false
    @State private var error: String?
    @State private var result: Recipe?
    @State private var usedAI: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Paste a link or the recipe text", text: $input, axis: .vertical)
                        .lineLimit(1...6)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    PasteButton(payloadType: String.self) { strings in
                        if let s = strings.first { input = s; Task { await go() } }
                    }
                    Button { Task { await go() } } label: {
                        if working { ProgressView() } else { Label("Read the recipe", systemImage: "text.viewfinder") }
                    }
                    .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || working)
                } footer: {
                    Text("In Instagram or TikTok tap Share → Copy link, then paste it here. Even quicker: tap Share → More → Save to Plate, straight from the video.")
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
                if let r = result {
                    Section {
                        Text(r.name).font(.headline)
                        Text("\(r.ingredients.count) ingredients · \(r.steps.count) steps · serves \(r.servings)")
                            .font(.subheadline).foregroundStyle(.secondary)
                        MacroLine(macros: Nutrition.perServing(r))
                        if let usedAI { Text("Tidied up by \(usedAI).").font(.caption).foregroundStyle(.secondary) }
                    } header: { Text("Found") }
                    Section("Ingredients") {
                        ForEach(r.ingredients) { ing in
                            HStack {
                                Text((ing.quantity.map { Format.quantity($0) + " " } ?? "") + ing.name)
                                Spacer()
                                if ing.foodId == nil {
                                    Image(systemName: "questionmark.circle").foregroundStyle(.orange)
                                        .accessibilityLabel("Not recognised")
                                }
                            }
                        }
                    }
                    if !r.steps.isEmpty {
                        Section("Method") { ForEach(Array(r.steps.enumerated()), id: \.offset) { Text("\($0.offset + 1). \($0.element)") } }
                    }
                    Section {
                        Button {
                            model.save(r)
                            model.banner = "Saved \(r.name)"
                            dismiss()
                        } label: { Label("Save recipe", systemImage: "checkmark") }
                        .buttonStyle(.borderedProminent)
                        NavigationLink("Edit before saving") {
                            RecipeEditorInline(recipe: r) { edited in model.save(edited); model.banner = "Saved \(edited.name)"; dismiss() }
                        }
                    }
                }
                if !caption.isEmpty {
                    Section("Caption") { Text(caption).font(.caption).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("Import a recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }

    func go() async {
        error = nil; result = nil; usedAI = nil
        working = true
        defer { working = false }
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        // A link on its own: fetch the caption. Anything longer is the caption itself (maybe with a link in it).
        if let (url, p) = SocialImport.link(in: text), text.count < url.absoluteString.count + 40 {
            do {
                let (c, _, _) = try await CaptionFetcher.fetch(text)
                caption = c.text; author = c.author; link = url.absoluteString; platform = p
            } catch {
                self.error = error.localizedDescription
                return
            }
        } else {
            caption = text
            if let (url, p) = SocialImport.link(in: text) { link = url.absoluteString; platform = p }
        }
        await read()
    }

    func read() async {
        let kind: RecipeSourceKind = platform == .tiktok ? .tiktok : platform == .instagram ? .instagram : (link == nil ? .manual : .web)
        let source = RecipeSource(kind: kind, url: link, author: author)
        let parsed = RecipeTextParser.parse(caption)
        var recipe = parsed.recipe(source: source)
        // Ask the AI to tidy up when it's switched on, keeping Plate's reading if the AI fails.
        if let engine = model.aiEngine {
            do {
                let draft = try await engine.tidy(caption: caption)
                var tidy = draft.recipe(source: source)
                if tidy.ingredients.count >= max(2, parsed.ingredients.count / 2) {
                    // The creator's stated macros win over the model's estimate.
                    if let stated = parsed.statedPerServing { tidy.statedPerServing = stated }
                    tidy.tags = parsed.tags
                    recipe = tidy
                    usedAI = engine.name
                }
            } catch {
                // Fall back silently to Plate's own reading.
            }
        }
        if recipe.ingredients.count < 2 {
            self.error = "Couldn't find a recipe in that caption. If the recipe is in the video rather than the caption, type it in with Recipes → ✎."
            return
        }
        result = recipe
    }
}

struct RecipeEditorInline: View {
    let recipe: Recipe
    let onSave: (Recipe) -> Void
    @State private var show = true
    var body: some View {
        RecipeEditor(recipe: recipe, onSave: onSave)
    }
}

/// New meal ideas from what's in the kitchen: AI when it's on, otherwise the closest recipes and their variations.
struct IdeasView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var meal: MealType? = .dinner
    @State private var working = false
    @State private var ideas: [Recipe] = []
    @State private var error: String?
    @State private var engineName: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Meal", selection: $meal) {
                        Text("Any").tag(MealType?.none)
                        ForEach(MealType.allCases) { Text($0.title).tag(MealType?.some($0)) }
                    }
                    .pickerStyle(.segmented)
                    Button { Task { await generate() } } label: {
                        if working { HStack { ProgressView(); Text("Thinking…") } }
                        else { Label(ideas.isEmpty ? "Give me ideas" : "More ideas", systemImage: "sparkles") }
                    }
                    .disabled(working)
                } footer: {
                    Text(model.aiEngine.map { "Using \($0.name), from what's in your kitchen." }
                         ?? "AI is off, so these come from your recipes and their variations. Turn on AI in Settings for brand-new dishes.")
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                ForEach(ideas) { r in
                    NavigationLink(value: r) { RecipeRow(recipe: r, match: Suggestions.evaluate(r, stock: model.stock)) }
                }
            }
            .navigationTitle("Ideas")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Recipe.self) { RecipeDetailView(recipe: $0) }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }

    func kitchenLines() -> [String] {
        model.household.inventory.map { "\($0.name): \($0.amountText)" }
    }

    func generate() async {
        working = true; error = nil
        defer { working = false }
        let people = max(1, model.household.planSettings.people)
        if let engine = model.aiEngine, !model.household.inventory.isEmpty {
            do {
                let drafts = try await engine.ideas(kitchen: kitchenLines(), meal: meal, count: 3, people: people)
                ideas = drafts.map { $0.recipe(source: RecipeSource(kind: .ai, author: engine.name)) } + ideas
                return
            } catch {
                self.error = "\(engine.name) couldn't come up with ideas: \(error.localizedDescription). Showing ideas from your recipes instead."
            }
        }
        // Without AI: near matches and variations that use what you have.
        let ranked = Suggestions.rank(model.recipes, inventory: model.household.inventory, servings: people, now: Date(), mealType: meal)
        var out: [Recipe] = []
        for m in ranked.prefix(8) {
            for v in Variations.of(m.recipe, inventory: model.household.inventory, limit: 2) where !out.contains(where: { $0.name == v.recipe.name }) {
                out.append(v.recipe)
            }
        }
        let fresh = out.filter { o in !ideas.contains { $0.name == o.name } }
        ideas = Array(fresh.shuffled().prefix(5)) + ideas
        if ideas.isEmpty { error = "Add a few things to your kitchen first, then try again." }
    }
}
