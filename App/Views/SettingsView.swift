import PlateCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var hasKey = Keychain.claudeKey != nil
    @State private var confirmReset = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section("Household") {
                    TextField("Name", text: $model.household.name)
                    Stepper("Cooking for \(model.household.planSettings.people)", value: $model.household.planSettings.people, in: 1...12)
                }
                if !model.household.members.isEmpty {
                    Section {
                        TextField("Your name", text: $model.household.members[0].name)
                        targetField("Calories", value: $model.household.members[0].targets.kcal, unit: "kcal")
                        targetField("Protein", value: $model.household.members[0].targets.protein, unit: "g")
                        targetField("Carbs", value: $model.household.members[0].targets.carbs, unit: "g")
                        targetField("Fat", value: $model.household.members[0].targets.fat, unit: "g")
                    } header: { Text("Daily targets") } footer: { Text("Used for the Today screen and to pick sensible portions when planning.") }
                }
                Section {
                    ForEach(Store.allCases) { store in
                        Toggle(store.title, isOn: Binding(
                            get: { model.household.stores.contains(store) },
                            set: { on in
                                if on { if !model.household.stores.contains(store) { model.household.stores.append(store) } }
                                else if model.household.stores.count > 1 { model.household.stores.removeAll { $0 == store } }
                            }))
                    }
                } header: { Text("Where you shop") } footer: { Text("New shopping lists compare packs at these shops. Prices are rough guides.") }

                Section {
                    Picker("AI", selection: Binding(get: { model.aiChoice }, set: { model.aiChoice = $0 })) {
                        ForEach(AIChoice.allCases) { Text($0.title).tag($0) }
                    }
                    Text(model.aiChoice.detail).font(.caption).foregroundStyle(.secondary)
                    LabeledContent("Apple Intelligence", value: AIService.appleStatus)
                        .font(.subheadline)
                } header: { Text("AI") } footer: {
                    Text("AI tidies up recipes from captions and suggests new dishes from what's in your kitchen. Everything else works without it.")
                }
                Section {
                    if hasKey {
                        LabeledContent("Claude API key", value: "Saved")
                        Picker("Model", selection: Binding(get: { model.claudeModel }, set: { model.claudeModel = $0 })) {
                            ForEach(ClaudeModel.allCases) { Text($0.title).tag($0) }
                        }
                        Button("Remove key", role: .destructive) { Keychain.claudeKey = nil; hasKey = false }
                    } else {
                        SecureField("sk-ant-…", text: $key)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Save key") { Keychain.claudeKey = key; key = ""; hasKey = Keychain.claudeKey != nil }
                            .disabled(!key.hasPrefix("sk-"))
                    }
                } header: { Text("Claude (optional)") } footer: {
                    Text("A Claude subscription can't be used by other apps, but an API key from console.anthropic.com can. It's kept in this iPhone's keychain and only sent to Anthropic.")
                }
                Section {
                    LabeledContent("Recipes", value: "\(model.recipes.count)")
                    LabeledContent("Items in the kitchen", value: "\(model.household.inventory.count)")
                    Button("Clear everything", role: .destructive) { confirmReset = true }
                } header: { Text("Data") } footer: {
                    Text("Everything is kept on this iPhone. Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "")). Food barcodes are looked up on Open Food Facts.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Clear your kitchen, recipes, plan, lists and food log?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Clear everything", role: .destructive) { model.household = Household() }
            }
        }
    }

    func targetField(_ title: String, value: Binding<Double>, unit: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, value: value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 90)
            Text(unit).foregroundStyle(.secondary)
        }
    }
}
