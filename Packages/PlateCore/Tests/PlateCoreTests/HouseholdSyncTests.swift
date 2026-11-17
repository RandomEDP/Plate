import XCTest
@testable import PlateCore

final class HouseholdSyncTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_794_000_000.25) // Nov 2026, with a fraction of a second as Date() has

    func caption(_ title: String, _ lines: [String]) -> Recipe {
        RecipeTextParser.parse("\(title)\nIngredients:\n" + lines.joined(separator: "\n") + "\nMethod:\n1. Cook it.")
            .recipe(source: RecipeSource(kind: .manual))
    }

    /// A household with a bit of everything in it.
    func sample() -> Household {
        var h = Household(name: "Academy Square")
        h.recipes = [caption("Chickpea curry", ["1 tin chickpeas", "1 onion", "2 garlic cloves", "400ml coconut milk"]),
                     caption("Pesto pasta", ["200g pasta", "2 tbsp pesto", "50g parmesan"])]
        h.inventory = [InventoryItem(foodId: "onion", name: "Onion", amount: 3, unit: .piece, location: .cupboard, addedAt: now),
                       InventoryItem(foodId: "milk", name: "Milk", amount: 2000, unit: .ml, location: .fridge, addedAt: now)]
        h.lists = [ShoppingList(name: "Big shop", createdAt: now, meals: [ListMeal(recipeId: h.recipes[0].id, servings: 4)],
                                checked: ["onion", "garlic", "milk"])]
        h.usage = [UsageRecord(foodId: "onion", amount: 1, unit: .piece, date: now)]
        h.plan.entries = [PlanEntry(day: 0, meal: .dinner, recipeId: h.recipes[0].id, servings: 2)]
        h.log = [FoodLogEntry(date: now, meal: .lunch, title: "Sandwich", macros: Macros(kcal: 400))]
        h.extras["ai"] = "claude"
        h.extras["favouriteBuiltIns"] = "x"
        h.dashboard.tiles = Array(h.dashboard.tiles.prefix(3))
        return h
    }

    /// The household as it comes back from the file (dates to the second, as the file writes them).
    func reloaded(_ h: Household) -> Household {
        try! HouseholdSync.decoder.decode(Household.self, from: HouseholdSync.encoder.encode(h))
    }

    // MARK: Cutting up and putting back

    func testPartsPutBackGiveTheSameHousehold() {
        let h = reloaded(sample())
        let back = HouseholdSync.assemble(HouseholdSync.parts(of: h), keeping: Household())
        XCTAssertEqual(back.name, "Academy Square")
        XCTAssertEqual(back.recipes, h.recipes)
        XCTAssertEqual(back.inventory, h.inventory)
        XCTAssertEqual(back.lists, h.lists)
        XCTAssertEqual(back.plan, h.plan)
        XCTAssertEqual(back.usage, h.usage)
        XCTAssertEqual(back.dashboard, h.dashboard)
        XCTAssertEqual(back.members, h.members)
        XCTAssertEqual(back.extras["favouriteBuiltIns"], "x")
    }

    func testFoodLogAndThisPhonesAISettingStayOnThePhone() {
        let h = sample()
        let parts = HouseholdSync.parts(of: h)
        XCTAssertNil(parts["extra.ai"], "the AI choice goes with this phone's Claude key")
        XCTAssertFalse(parts.keys.contains { $0.hasPrefix("log") })
        var mine = Household()
        mine.log = [FoodLogEntry(date: now, meal: .dinner, title: "Mine", macros: .zero)]
        mine.extras["ai"] = "apple"
        let back = HouseholdSync.assemble(parts, keeping: mine)
        XCTAssertEqual(back.log.map(\.title), ["Mine"])
        XCTAssertEqual(back.extras["ai"], "apple")
    }

    func testEachRecipeItemAndListIsItsOwnPart() {
        let h = sample()
        let keys = Set(HouseholdSync.parts(of: h).keys)
        for r in h.recipes { XCTAssertTrue(keys.contains("recipe.\(r.id.uuidString)")) }
        for i in h.inventory { XCTAssertTrue(keys.contains("item.\(i.id.uuidString)")) }
        XCTAssertTrue(keys.contains("list.\(h.lists[0].id.uuidString)"))
        XCTAssertTrue(keys.isSuperset(of: ["name", "members", "usage", "hidden", "plan", "planSettings", "stores", "dashboard"]))
    }

    func testDishPhotosAreParts() {
        var h = sample()
        h.recipes[0].photo = RecipePhoto(file: "ABC.jpg", origin: .own)
        XCTAssertEqual(HouseholdSync.parts(of: h)["photo.ABC.jpg"], Data())
        XCTAssertEqual(HouseholdSync.split("photo.ABC.jpg")?.id, "ABC.jpg")
    }

    func testKeysICloudCantNameAreLeftOut() {
        var h = sample()
        h.extras["has space"] = "1"
        XCTAssertNil(HouseholdSync.parts(of: h)["extra.has space"])
    }

    func testUnknownKindsAreNotRead() {
        XCTAssertNil(HouseholdSync.split("gadget.1"))
        XCTAssertNil(HouseholdSync.split("recipe."))
        var h = sample()
        XCTAssertFalse(HouseholdSync.apply("gadget.1", Data("1".utf8), to: &h))
    }

    // MARK: What changed

    func testNothingChangedSendsNothing() {
        let h = sample()
        let parts = HouseholdSync.parts(of: h)
        let c = HouseholdSync.changes(from: parts, to: HouseholdSync.parts(of: h))
        XCTAssertEqual(c.save, [])
        XCTAssertEqual(c.delete, [])
    }

    func testOneEditSendsOnlyThatPart() {
        var h = sample()
        let before = HouseholdSync.parts(of: h)
        h.recipes[1].isFavourite = true
        h.inventory.removeAll { $0.foodId == "milk" }
        let c = HouseholdSync.changes(from: before, to: HouseholdSync.parts(of: h))
        XCTAssertEqual(c.save, ["recipe.\(h.recipes[1].id.uuidString)"])
        XCTAssertEqual(c.delete.count, 1)
        XCTAssertTrue(c.delete[0].hasPrefix("item."))
    }

    func testTickedItemsInADifferentOrderAreNotAChange() {
        var a = ShoppingList(name: "Shop", createdAt: now)
        var b = a
        a.checked = []
        for k in ["milk", "eggs", "bread", "onion", "garlic", "rice", "pasta", "cheese"] { a.checked.insert(k) }
        b.checked = []
        for k in ["cheese", "pasta", "rice", "garlic", "onion", "bread", "eggs", "milk"] { b.checked.insert(k) }
        let key = "list.\(a.id.uuidString)"
        XCTAssertTrue(HouseholdSync.same(key, try! HouseholdSync.encoder.encode(a), try! HouseholdSync.encoder.encode(b)))
    }

    func testReopeningTheAppIsNotAChange() {
        // Dates in the file lose their fractions of a second; that mustn't look like an edit to everything.
        let h = sample()
        var ledger = SyncLedger()
        _ = ledger.take(h)
        let again = ledger.take(reloaded(h))
        XCTAssertEqual(again.save, [])
        XCTAssertEqual(again.delete, [])
    }

    func testHiddenBuiltInsSendTheSameWhateverTheOrder() {
        var h = sample()
        h.hiddenBuiltIns = Set(BuiltInRecipes.all.prefix(6).map(\.id))
        let a = HouseholdSync.part("hidden", of: h)
        h.hiddenBuiltIns = Set(BuiltInRecipes.all.prefix(6).reversed().map(\.id))
        XCTAssertEqual(a, HouseholdSync.part("hidden", of: h))
    }

    func testOneOffPartsAreNeverDeleted() {
        let c = HouseholdSync.changes(from: ["plan": Data("{}".utf8)], to: [:])
        XCTAssertEqual(c.delete, [])
    }

    // MARK: The ledger

    func testFirstTakeSendsEverythingThenNothing() {
        let h = sample()
        var ledger = SyncLedger()
        let first = ledger.take(h)
        XCTAssertEqual(Set(first.save), Set(HouseholdSync.parts(of: h).keys))
        XCTAssertEqual(ledger.take(h).save, [])
    }

    func testARecipeFromSomeoneElseIsAddedAndNotSentBack() {
        var mine = sample()
        var ledger = SyncLedger()
        _ = ledger.take(mine)
        let theirs = caption("Lentil soup", ["200g red lentils", "1 onion", "1 carrot"])
        let key = "recipe.\(theirs.id.uuidString)"
        XCTAssertTrue(ledger.receive(key, try! HouseholdSync.encoder.encode(theirs), into: &mine, pending: false))
        XCTAssertTrue(mine.recipes.contains { $0.name == theirs.name })
        XCTAssertEqual(ledger.take(mine).save, [], "what arrived mustn't be sent straight back")
    }

    func testTheirEditReplacesMine() {
        var mine = sample()
        var ledger = SyncLedger()
        _ = ledger.take(mine)
        var item = mine.inventory[0]
        item.amount = 1
        ledger.receive("item.\(item.id.uuidString)", try! HouseholdSync.encoder.encode(item), into: &mine, pending: false)
        XCTAssertEqual(mine.inventory[0].amount, 1)
    }

    func testMyWaitingEditBeatsOneThatArrives() {
        var mine = sample()
        var ledger = SyncLedger()
        _ = ledger.take(mine)
        mine.inventory[0].amount = 5            // edited here, not sent yet
        var theirs = mine.inventory[0]
        theirs.amount = 1
        let key = "item.\(theirs.id.uuidString)"
        XCTAssertFalse(ledger.receive(key, try! HouseholdSync.encoder.encode(theirs), into: &mine, pending: false))
        XCTAssertEqual(mine.inventory[0].amount, 5)
        XCTAssertEqual(ledger.take(mine).save, [key], "mine goes up and wins")
    }

    func testFoodUsedOnBothPhonesIsKept() {
        var mine = sample()
        var ledger = SyncLedger()
        _ = ledger.take(mine)
        mine.usage.append(UsageRecord(foodId: "milk", amount: 200, unit: .ml, date: now.addingTimeInterval(60)))
        var theirs = sample().usage
        theirs.append(UsageRecord(foodId: "rice", amount: 100, unit: .g, date: now.addingTimeInterval(120)))
        ledger.receive("usage", try! HouseholdSync.encoder.encode(theirs), into: &mine, pending: true)
        XCTAssertEqual(Set(mine.usage.map(\.foodId)), ["onion", "milk", "rice"])
        XCTAssertEqual(mine.usage.count, 3)
        XCTAssertEqual(ledger.take(mine).save, ["usage"], "the combined list goes back up")
    }

    func testResolveKeepsMineExceptForFoodUsed() {
        let a = Data("\"mine\"".utf8), b = Data("\"theirs\"".utf8)
        XCTAssertEqual(HouseholdSync.resolve("name", mine: a, theirs: b), a)
    }

    func testDeletedElsewhereIsDeletedHere() {
        var mine = sample()
        var ledger = SyncLedger()
        _ = ledger.take(mine)
        let key = "item.\(mine.inventory[1].id.uuidString)"
        XCTAssertTrue(ledger.receiveDeletion(key, into: &mine))
        XCTAssertEqual(mine.inventory.count, 1)
        XCTAssertEqual(ledger.take(mine).delete, [], "it's already gone from iCloud")
    }

    func testPartsFromANewerPlateAreLeftAlone() {
        var mine = sample()
        var ledger = SyncLedger()
        _ = ledger.take(mine)
        XCTAssertFalse(ledger.receive("gadget.1", Data("{}".utf8), into: &mine, pending: false))
        XCTAssertFalse(ledger.receive("recipe.\(UUID().uuidString)", Data("not json".utf8), into: &mine, pending: false))
        let next = ledger.take(mine)
        XCTAssertEqual(next.delete, [], "nothing this Plate can't read is deleted")
        XCTAssertEqual(next.save, [])
    }

    // MARK: Joining

    func testJoiningAnEmptyICloudSendsEverything() {
        var ledger = SyncLedger()
        let h = sample()
        let joined = ledger.join(h, cloud: [:], me: h.members[0].id)
        XCTAssertEqual(joined.household, h)
        XCTAssertTrue(ledger.joined)
        XCTAssertEqual(joined.me, h.members[0].id)
        XCTAssertEqual(Set(ledger.take(joined.household).save), Set(HouseholdSync.parts(of: h).keys))
    }

    func testJoiningTakesTheSharedHouseholdAndBringsMyOwnRecipes() {
        let shared = sample()
        var mine = Household(name: "My kitchen")
        mine.inventory = [InventoryItem(foodId: "rice", name: "Rice", amount: 1000, unit: .g, location: .cupboard)]
        mine.log = [FoodLogEntry(date: now, meal: .dinner, title: "Mine", macros: .zero)]
        let soup = caption("Lentil soup", ["200g red lentils", "1 onion", "1 carrot"])
        // The same curry, saved separately on this phone: not brought twice.
        let curryAgain = caption("Chickpea curry", ["1 tin chickpeas", "1 onion", "2 garlic cloves", "400ml coconut milk"])
        mine.recipes = [soup, curryAgain]
        mine.extras["ai"] = "apple"

        var ledger = SyncLedger()
        mine.members = [Member(name: "Sam", targets: MacroTargets(kcal: 1800))]
        let joined = ledger.join(mine, cloud: HouseholdSync.parts(of: shared), me: mine.members[0].id, addMe: true)
        let h = joined.household
        XCTAssertEqual(joined.broughtRecipes, 1)
        XCTAssertEqual(h.members.map(\.name), ["Me", "Sam"], "Sam joins the household with their own targets")
        XCTAssertEqual(joined.me, mine.members[0].id)
        XCTAssertEqual(h.name, "Academy Square")
        XCTAssertEqual(Set(h.recipes.map(\.name)), ["Chickpea curry", "Pesto pasta", "Lentil soup"])
        XCTAssertEqual(h.inventory.map(\.name), ["Onion", "Milk"], "the kitchen is the shared one")
        XCTAssertEqual(h.log.map(\.title), ["Mine"])
        XCTAssertEqual(h.extras["ai"], "apple")
        XCTAssertEqual(ledger.take(h).save, ["members", "recipe.\(soup.id.uuidString)"], "only Sam and the brought recipe go up")
    }

    func testMyOwnIPadBecomesThePersonAlreadyThere() {
        let shared = sample()
        let iPad = Household(name: "My kitchen")
        var ledger = SyncLedger()
        let joined = ledger.join(iPad, cloud: HouseholdSync.parts(of: shared), me: iPad.members[0].id, addMe: false)
        XCTAssertEqual(joined.household.members.count, 1)
        XCTAssertEqual(joined.me, shared.members[0].id)
    }
}
