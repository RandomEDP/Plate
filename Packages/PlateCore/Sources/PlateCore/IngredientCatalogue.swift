import Foundation

// Plate's big list of vegetarian cooking ingredients (Ethan, 14 November 2026: "any cooking ingredient that might be
// needed, vegetarian only"). It sits on top of the original food list in FoodDatabase.swift, so recipes imported from
// captions, Osta or videos match far more of their ingredients and get macros and a shopping-list line for them.
//
// Each ingredient has one unit, chosen for how you'd count it while cooking:
//   • items for things you pick up one at a time (aubergines, leeks, chillies, cinnamon sticks, filo sheets);
//   • ml for liquids (plant milks, cream, wine, vinegars, syrups you pour);
//   • grams for everything you weigh or scoop (greens, grains, flours, cheese, nuts, spices, pastes).
// UnitStandard converts what a recipe says into that unit and keeps the original so it can be put back.
//
// Nutrition is per 100 g (or 100 ml) from typical UK labels, and the one Sainsbury's pack each is a rough guide
// (November 2026). Pack sizes are in the ingredient's unit: grams, ml or a count.

private func n(_ kcal: Double, _ p: Double, _ c: Double, _ f: Double, _ fibre: Double = 0) -> Macros {
    Macros(kcal: kcal, protein: p, carbs: c, fat: f, fibre: fibre)
}

/// id, name, aliases, unit, grams per item, nutrition per 100, Sainsbury's pack (size, price).
typealias CatalogueRow = @Sendable (String, String, [String], BaseUnit, Double?, Macros, (Double, Double)) -> Food

private func kind(_ category: FoodCategory, _ storage: StorageLocation, keeps: Int, density: Double = 1,
                  staple: Bool = false, swap: String? = nil) -> CatalogueRow {
    { id, name, aliases, unit, each, macros, pack in
        Food(id: id, name: name, aliases: aliases, category: category, storage: storage, unit: unit, per100: macros,
             gramsPerPiece: each, gramsPerMl: density, shelfLifeDays: keeps, isStaple: staple, swapGroup: swap,
             packs: [PackOption(.sainsburys, pack.0, pack.1)])
    }
}

private extension Food {
    func keeps(_ days: Int) -> Food { var f = self; f.shelfLifeDays = days; return f }
    func dense(_ gramsPerMl: Double) -> Food { var f = self; f.gramsPerMl = gramsPerMl; return f }
    func tin(_ size: Double) -> Food { var f = self; f.canSize = size; return f }
    func kept(_ place: StorageLocation) -> Food { var f = self; f.storage = place; return f }
    func group(_ swap: String) -> Food { var f = self; f.swapGroup = swap; return f }
    func sort(_ category: FoodCategory) -> Food { var f = self; f.category = category; return f }
    var staple: Food { var f = self; f.isStaple = true; return f }
}

public enum IngredientCatalogue {
    static let veg = kind(.produce, .fridge, keeps: 7)
    static let fruit = kind(.produce, .fridge, keeps: 7, swap: "fruit")
    static let herb = kind(.produce, .fridge, keeps: 6, density: 0.1, swap: "herb")
    static let spice = kind(.spices, .cupboard, keeps: 700, density: 0.5, staple: true)
    static let pulse = kind(.tins, .cupboard, keeps: 700, density: 0.7, swap: "beans")
    static let grain = kind(.grains, .cupboard, keeps: 365, density: 0.8)
    static let baking = kind(.grains, .cupboard, keeps: 365, density: 0.55)
    static let sweet = kind(.condiments, .cupboard, keeps: 700, density: 0.85)
    static let dairy = kind(.dairy, .fridge, keeps: 14, density: 1.03)
    static let plant = kind(.other, .fridge, keeps: 14)
    static let nut = kind(.snacks, .cupboard, keeps: 300, density: 0.6)
    static let sauce = kind(.condiments, .cupboard, keeps: 365, density: 1.1)
    static let jar = kind(.tins, .cupboard, keeps: 700, density: 1.02)
    static let frozen = kind(.frozen, .freezer, keeps: 365, density: 0.6)
    static let bakery = kind(.bakery, .cupboard, keeps: 7)
    static let drink = kind(.drinks, .cupboard, keeps: 365)

    /// Every ingredient in the catalogue.
    public static let all: [Food] = vegetables + mushroomsAndChillies + fruits + herbs + spices + seasonings + pulses
        + grains + pastaAndNoodles + breadAndPastry + flours + sugars + bakingExtras + dairyFoods + plantFoods + nuts
        + pastes + sauces + vinegarsAndOils + jars + frozenFoods + drinksAndOther

    static let vegetables: [Food] = [
        veg("aubergine", "Aubergines", ["aubergine", "eggplant", "eggplants", "baby aubergines"], .piece, 250, n(25, 1, 6, 0.2, 3), (1, 0.85)),
        veg("butternut-squash", "Butternut squash", ["butternut squash", "squash", "butternut", "butternut squash cubes"], .g, 1000, n(45, 1, 12, 0.1, 2), (1000, 1.20)).keeps(30).kept(.cupboard).dense(0.6),
        veg("pumpkin", "Pumpkin", ["pumpkin flesh", "pumpkin puree", "pumpkin purée"], .g, nil, n(26, 1, 6.5, 0.1, 0.5), (1000, 1.50)).keeps(30).kept(.cupboard).dense(0.6),
        veg("leek", "Leeks", ["leek", "leeks", "baby leeks"], .piece, 200, n(31, 1.5, 6, 0.3, 2.2), (3, 1.25)).keeps(10),
        veg("celery", "Celery", ["celery sticks", "celery stick", "sticks of celery", "stick of celery", "celery stalks", "celery stalk"], .piece, 40, n(16, 0.7, 3, 0.2, 1.6), (10, 0.75)).keeps(14),
        veg("fennel", "Fennel", ["fennel bulb", "fennel bulbs", "baby fennel"], .piece, 250, n(31, 1.2, 7, 0.2, 3), (2, 1.20)),
        veg("beetroot", "Beetroot", ["beetroots", "beets", "beet", "cooked beetroot", "raw beetroot", "golden beetroot"], .piece, 100, n(43, 1.6, 10, 0.2, 2.8), (4, 1.00)).keeps(14),
        veg("parsnip", "Parsnips", ["parsnip", "parsnips"], .piece, 150, n(75, 1.2, 18, 0.3, 4.9), (4, 0.75)).keeps(14),
        veg("swede", "Swede", ["swede", "rutabaga"], .g, 800, n(37, 1.1, 8.6, 0.2, 2.3), (800, 0.75)).keeps(21),
        veg("turnip", "Turnips", ["turnip", "turnips"], .piece, 150, n(28, 0.9, 6.4, 0.1, 1.8), (4, 1.00)).keeps(14),
        veg("celeriac", "Celeriac", ["celeriac", "celery root"], .g, 800, n(42, 1.5, 9, 0.3, 1.8), (800, 1.25)).keeps(21),
        veg("kohlrabi", "Kohlrabi", ["kohlrabi"], .piece, 300, n(27, 1.7, 6, 0.1, 3.6), (1, 1.00)),
        veg("jerusalem-artichoke", "Jerusalem artichokes", ["jerusalem artichoke", "jerusalem artichokes", "sunchokes"], .g, nil, n(73, 2, 17, 0, 1.6), (500, 2.00)).keeps(14),
        veg("kale", "Kale", ["kale", "curly kale", "chopped kale", "kale leaves"], .g, nil, n(35, 2.9, 4.4, 1.5, 4.1), (200, 1.00)).keeps(5).dense(0.07).group("leafy"),
        veg("cavolo-nero", "Cavolo nero", ["cavolo nero", "black kale", "tuscan kale", "lacinato kale"], .g, nil, n(30, 2.5, 4, 0.6, 3.5), (200, 1.75)).keeps(5).dense(0.07).group("leafy"),
        veg("chard", "Swiss chard", ["chard", "swiss chard", "rainbow chard", "ruby chard"], .g, nil, n(19, 1.8, 3.7, 0.2, 1.6), (200, 1.75)).keeps(5).dense(0.1).group("leafy"),
        veg("spring-greens", "Spring greens", ["spring greens", "greens", "collard greens", "collards"], .g, nil, n(33, 3, 3, 1, 3.4), (300, 1.20)).keeps(5).dense(0.1).group("leafy"),
        veg("pak-choi", "Pak choi", ["pak choi", "bok choy", "bok choi", "baby pak choi", "pak choy", "baby bok choy"], .piece, 120, n(13, 1.5, 2.2, 0.2, 1), (2, 1.25)).keeps(5),
        veg("savoy-cabbage", "Savoy cabbage", ["savoy cabbage", "cabbage", "green cabbage", "sweetheart cabbage", "pointed cabbage", "hispi cabbage"], .piece, 700, n(27, 2, 6, 0.1, 3), (1, 0.90)).keeps(14),
        veg("red-cabbage", "Red cabbage", ["red cabbage", "purple cabbage"], .piece, 900, n(31, 1.4, 7, 0.2, 2.1), (1, 0.90)).keeps(21),
        veg("white-cabbage", "White cabbage", ["white cabbage", "coleslaw cabbage"], .piece, 900, n(25, 1.3, 5.8, 0.1, 2.5), (1, 0.80)).keeps(21),
        veg("brussels-sprouts", "Brussels sprouts", ["brussels sprouts", "sprouts", "brussel sprouts", "brussels sprout"], .g, 15, n(43, 3.4, 9, 0.3, 3.8), (500, 1.00)).keeps(10).dense(0.4).group("greenveg"),
        veg("asparagus", "Asparagus", ["asparagus spears", "asparagus tips", "asparagus spear", "green asparagus", "british asparagus"], .g, 16, n(20, 2.2, 3.9, 0.1, 2.1), (250, 2.50)).keeps(4).group("greenveg"),
        veg("runner-beans", "Runner beans", ["runner beans", "runner bean", "flat beans"], .g, nil, n(22, 1.6, 3.2, 0.4, 2.5), (200, 1.75)).keeps(5).group("greenveg"),
        veg("mangetout", "Mangetout", ["mangetout", "snow peas", "mange tout"], .g, nil, n(42, 2.8, 7.5, 0.2, 2.6), (150, 1.25)).keeps(5).group("greenveg"),
        veg("sugar-snap-peas", "Sugar snap peas", ["sugar snap peas", "sugar snaps", "sugarsnap peas", "sugarsnaps"], .g, nil, n(42, 2.8, 7.5, 0.2, 2.6), (150, 1.25)).keeps(5).group("greenveg"),
        veg("baby-corn", "Baby corn", ["baby corn", "baby sweetcorn", "babycorn", "mini corn"], .g, 10, n(26, 2.5, 3, 0.4, 2), (125, 1.10)).keeps(6),
        veg("beansprouts", "Beansprouts", ["beansprouts", "bean sprouts", "mung bean sprouts", "beansprout"], .g, nil, n(31, 3, 6, 0.2, 1.8), (300, 0.80)).keeps(3).dense(0.25),
        veg("watercress", "Watercress", ["watercress"], .g, nil, n(11, 2.3, 1.3, 0.1, 0.5), (85, 1.00)).keeps(4).dense(0.1).group("leafy"),
        veg("rocket", "Rocket", ["rocket", "arugula", "wild rocket", "rocket leaves"], .g, nil, n(25, 2.6, 3.7, 0.7, 1.6), (60, 1.00)).keeps(4).dense(0.08).group("leafy"),
        veg("little-gem", "Little gem lettuce", ["little gem", "little gem lettuce", "little gems", "baby gem", "baby gem lettuce", "baby gems"], .piece, 90, n(15, 1.2, 2.9, 0.2, 1.3), (2, 0.85)).keeps(6).group("leafy"),
        veg("iceberg", "Iceberg lettuce", ["iceberg lettuce", "iceberg"], .piece, 500, n(14, 0.9, 3, 0.1, 1.2), (1, 0.65)).keeps(7).group("leafy"),
        veg("romaine", "Romaine lettuce", ["romaine", "romaine lettuce", "cos lettuce", "cos"], .piece, 300, n(17, 1.2, 3.3, 0.3, 2.1), (1, 0.95)).keeps(6).group("leafy"),
        veg("radicchio", "Radicchio", ["radicchio", "chicory", "endive", "red chicory", "treviso"], .piece, 200, n(23, 1.4, 4.5, 0.3, 0.9), (1, 1.20)),
        veg("radishes", "Radishes", ["radish", "radishes", "breakfast radishes", "mooli", "daikon"], .piece, 10, n(16, 0.7, 3.4, 0.1, 1.6), (20, 0.70)),
        veg("shallots", "Shallots", ["shallot", "shallots", "echalion shallots", "banana shallots", "banana shallot", "french shallots", "echalion shallot"], .piece, 40, n(72, 2.5, 17, 0.1, 3.2), (10, 1.10)).keeps(30).kept(.cupboard),
        veg("pointed-pepper", "Sweet pointed peppers", ["sweet pointed pepper", "sweet pointed peppers", "romano pepper", "romano peppers", "ramiro pepper", "pointed red pepper"], .piece, 120, n(31, 1, 6, 0.3, 2.1), (2, 1.25)).keeps(10).group("veg"),
        veg("padron-peppers", "Padrón peppers", ["padron peppers", "padrón peppers", "padron pepper", "shishito peppers"], .g, nil, n(20, 1, 4, 0.2, 1.8), (150, 2.00)),
        veg("okra", "Okra", ["okra", "ladies fingers", "ladies' fingers", "bhindi"], .g, 12, n(33, 1.9, 7, 0.2, 3.2), (200, 1.50)).keeps(5),
        veg("corn-on-the-cob", "Corn on the cob", ["corn on the cob", "corn cob", "corn cobs", "sweetcorn cob", "sweetcorn cobs", "corn on cob", "ears of corn"], .piece, 250, n(86, 3.3, 19, 1.4, 2.7), (2, 1.25)).keeps(5),
        veg("lemongrass", "Lemongrass", ["lemongrass", "lemon grass", "lemongrass stalks", "lemongrass stalk", "stalks of lemongrass", "stalk of lemongrass"], .piece, 15, n(99, 1.8, 25, 0.5, 0), (4, 1.00)).keeps(14),
        veg("galangal", "Galangal", ["galangal", "galangal paste"], .g, 20, n(71, 1, 15, 1, 2), (50, 1.25)).keeps(14),
        veg("fresh-turmeric", "Fresh turmeric", ["fresh turmeric", "turmeric root", "root turmeric"], .g, 10, n(80, 2, 17, 1, 4), (100, 1.50)).keeps(21),
        veg("horseradish-root", "Horseradish root", ["horseradish", "fresh horseradish", "horseradish root"], .g, nil, n(48, 1.2, 11, 0.7, 3.3), (100, 1.50)).keeps(21),
        veg("wild-garlic", "Wild garlic", ["wild garlic", "ramsons", "wild garlic leaves"], .g, nil, n(30, 2, 5, 0.5, 2), (50, 1.50)).keeps(4),
        veg("black-garlic", "Black garlic", ["black garlic", "black garlic cloves", "black garlic clove"], .piece, 5, n(220, 9, 48, 0.5, 2), (12, 2.50)).keeps(180).kept(.cupboard),
        veg("plantain", "Plantain", ["plantain", "plantains", "ripe plantain", "green plantain"], .piece, 250, n(122, 1.3, 32, 0.4, 2.3), (1, 0.65)).kept(.cupboard).group("starch"),
        veg("cassava", "Cassava", ["cassava", "yuca", "yucca"], .g, nil, n(160, 1.4, 38, 0.3, 1.8), (1000, 2.00)).keeps(14).kept(.cupboard).group("starch"),
        veg("courgetti", "Courgetti", ["courgetti", "courgette spaghetti", "spiralised courgette", "spiralized zucchini", "zoodles"], .g, nil, n(17, 1.2, 3.1, 0.3, 1), (250, 1.50)).keeps(4),
        veg("pea-shoots", "Pea shoots", ["pea shoots", "microgreens", "micro greens", "cress", "salad cress", "micro herbs"], .g, nil, n(30, 3, 4, 0.5, 2), (40, 1.25)).keeps(4).dense(0.05),
        veg("artichoke", "Globe artichokes", ["globe artichoke", "globe artichokes", "fresh artichokes"], .piece, 300, n(47, 3.3, 10.5, 0.2, 5.4), (1, 1.75)).keeps(5),
        veg("samphire", "Samphire", ["samphire", "sea asparagus"], .g, nil, n(20, 1.5, 3, 0.2, 1.5), (90, 2.00)).keeps(4),
        veg("squash-other", "Squash (other)", ["acorn squash", "kabocha", "kabocha squash", "delica squash", "spaghetti squash", "onion squash", "crown prince squash"], .g, 1200, n(40, 1, 10, 0.1, 1.5), (1200, 2.00)).keeps(30).kept(.cupboard),
    ]

    static let mushroomsAndChillies: [Food] = [
        veg("portobello", "Portobello mushrooms", ["portobello mushrooms", "portobello mushroom", "portabella mushrooms", "portobellos", "flat mushrooms", "large flat mushrooms", "field mushrooms"], .piece, 80, n(22, 2.1, 3.9, 0.4, 1.3), (4, 2.00)).keeps(6).group("veg"),
        veg("shiitake", "Shiitake mushrooms", ["shiitake", "shiitake mushrooms", "shitake mushrooms", "fresh shiitake", "shitake"], .g, 15, n(34, 2.2, 6.8, 0.5, 2.5), (150, 2.00)).keeps(6).dense(0.3),
        veg("oyster-mushrooms", "Oyster mushrooms", ["oyster mushrooms", "oyster mushroom", "king oyster mushrooms", "king oyster mushroom", "trumpet mushrooms", "pink oyster mushrooms"], .g, nil, n(33, 3.3, 6, 0.4, 2.3), (150, 2.00)).keeps(5).dense(0.3),
        veg("enoki", "Enoki mushrooms", ["enoki", "enoki mushrooms"], .g, nil, n(37, 2.7, 7.8, 0.3, 2.7), (150, 1.50)).keeps(6),
        veg("wild-mushrooms", "Mixed wild mushrooms", ["wild mushrooms", "mixed mushrooms", "exotic mushrooms", "mixed exotic mushrooms", "chanterelles", "girolles"], .g, nil, n(30, 3, 4, 0.4, 2), (150, 2.50)).keeps(5).dense(0.3),
        veg("dried-porcini", "Dried porcini", ["dried porcini", "porcini", "porcini mushrooms", "dried mushrooms", "dried shiitake", "dried porcini mushrooms", "dried wild mushrooms"], .g, nil, n(300, 25, 40, 3, 20), (30, 2.50)).keeps(365).kept(.cupboard),
        veg("jalapeno", "Jalapeños", ["jalapeno", "jalapeño", "jalapenos", "jalapeños", "fresh jalapeno", "green jalapeno", "jalapeno pepper", "jalapeno peppers"], .piece, 15, n(29, 0.9, 6.5, 0.4, 2.8), (4, 0.85)).keeps(10),
        veg("birds-eye-chilli", "Bird's eye chillies", ["bird's eye chilli", "birds eye chilli", "bird's eye chillies", "birdseye chillies", "thai chillies", "thai chilli", "bird's eye chili"], .piece, 3, n(40, 1.9, 9, 0.4, 1.5), (6, 0.85)).keeps(10),
        veg("scotch-bonnet", "Scotch bonnet chillies", ["scotch bonnet", "scotch bonnets", "scotch bonnet chilli", "scotch bonnet chillies", "scotch bonnet pepper", "habanero", "habaneros"], .piece, 10, n(40, 1.9, 9, 0.4, 1.5), (3, 0.85)).keeps(10),
        spice("dried-chillies", "Dried chillies", ["dried chillies", "dried chilli", "whole dried chillies", "dried red chillies", "kashmiri chillies", "ancho chilli", "ancho chillies", "chipotle chillies", "guajillo chillies", "arbol chillies", "dried chipotle"], .piece, 1, n(320, 12, 56, 6, 28), (30, 1.25)).keeps(365),
    ]

    static let fruits: [Food] = [
        fruit("orange", "Oranges", ["orange", "oranges", "navel orange", "navel oranges", "blood orange", "blood oranges", "seville oranges"], .piece, 180, n(47, 0.9, 12, 0.1, 2.4), (5, 1.75)).keeps(14).kept(.cupboard),
        fruit("clementine", "Clementines", ["clementine", "clementines", "satsuma", "satsumas", "easy peelers", "easy peeler", "mandarin", "mandarins", "tangerine", "tangerines"], .piece, 70, n(47, 0.9, 12, 0.2, 1.7), (9, 1.75)).keeps(14).kept(.cupboard),
        fruit("grapefruit", "Grapefruit", ["grapefruit", "pink grapefruit", "grapefruits", "ruby grapefruit"], .piece, 300, n(42, 0.8, 11, 0.1, 1.6), (1, 0.70)).keeps(14),
        fruit("pear", "Pears", ["pear", "pears", "conference pears", "conference pear", "williams pears"], .piece, 170, n(57, 0.4, 15, 0.1, 3.1), (4, 1.60)).keeps(10).kept(.cupboard),
        fruit("peach", "Peaches", ["peach", "peaches", "flat peaches", "doughnut peaches"], .piece, 150, n(39, 0.9, 10, 0.3, 1.5), (4, 2.00)).keeps(5),
        fruit("nectarine", "Nectarines", ["nectarine", "nectarines"], .piece, 140, n(44, 1.1, 11, 0.3, 1.7), (4, 2.00)).keeps(5),
        fruit("plum", "Plums", ["plum", "plums", "greengages", "damsons"], .piece, 70, n(46, 0.7, 11, 0.3, 1.4), (6, 1.75)).keeps(5),
        fruit("apricot", "Fresh apricots", ["apricot", "apricots", "fresh apricots", "fresh apricot"], .piece, 40, n(48, 1.4, 11, 0.4, 2), (7, 2.00)).keeps(5),
        fruit("cherries", "Cherries", ["cherries", "cherry", "fresh cherries", "pitted cherries", "black cherries"], .g, 8, n(63, 1.1, 16, 0.2, 2.1), (200, 2.50)).keeps(5).dense(0.6).group("berries"),
        fruit("grapes", "Grapes", ["grapes", "grape", "red grapes", "green grapes", "seedless grapes", "white grapes", "black grapes"], .g, 6, n(69, 0.7, 18, 0.2, 0.9), (500, 2.00)).dense(0.6),
        fruit("mango", "Mangoes", ["mango", "mangoes", "mangos", "ripe mango", "fresh mango", "alphonso mango"], .piece, 300, n(60, 0.8, 15, 0.4, 1.6), (1, 1.00)).keeps(5).kept(.cupboard),
        fruit("pineapple", "Pineapple", ["pineapple", "fresh pineapple", "pineapple chunks", "tinned pineapple", "pineapple rings", "pineapple pieces"], .g, 1000, n(50, 0.5, 13, 0.1, 1.4), (1000, 1.50)).keeps(5).kept(.cupboard).dense(0.7),
        fruit("melon", "Melon", ["melon", "cantaloupe", "honeydew melon", "galia melon", "honeydew", "cantaloupe melon"], .g, 1000, n(34, 0.8, 8, 0.2, 0.9), (1000, 1.50)).dense(0.65),
        fruit("watermelon", "Watermelon", ["watermelon", "watermelon chunks"], .g, nil, n(30, 0.6, 7.6, 0.2, 0.4), (1500, 2.50)).dense(0.65),
        fruit("kiwi", "Kiwi fruit", ["kiwi", "kiwis", "kiwi fruit", "kiwifruit", "golden kiwi"], .piece, 75, n(61, 1.1, 15, 0.5, 3), (6, 1.50)).keeps(14),
        fruit("pomegranate", "Pomegranates", ["pomegranate", "pomegranates", "whole pomegranate"], .piece, 250, n(83, 1.7, 19, 1.2, 4), (1, 1.00)).keeps(14),
        fruit("pomegranate-seeds", "Pomegranate seeds", ["pomegranate seeds", "pomegranate arils", "pomegranate jewels"], .g, nil, n(83, 1.7, 19, 1.2, 4), (100, 1.50)).keeps(5).dense(0.7),
        fruit("passion-fruit", "Passion fruit", ["passion fruit", "passionfruit", "passion fruits"], .piece, 20, n(97, 2.2, 23, 0.7, 10), (3, 1.50)).keeps(10),
        fruit("figs", "Fresh figs", ["fig", "figs", "fresh figs", "fresh fig"], .piece, 50, n(74, 0.8, 19, 0.3, 2.9), (4, 2.00)).keeps(5),
        fruit("raspberries", "Raspberries", ["raspberries", "raspberry", "fresh raspberries"], .g, nil, n(52, 1.2, 12, 0.7, 6.5), (150, 2.00)).keeps(4).dense(0.5).group("berries"),
        fruit("blackberries", "Blackberries", ["blackberries", "blackberry", "fresh blackberries"], .g, nil, n(43, 1.4, 10, 0.5, 5.3), (150, 2.00)).keeps(4).dense(0.6).group("berries"),
        fruit("rhubarb", "Rhubarb", ["rhubarb", "forced rhubarb", "rhubarb stalks"], .g, nil, n(21, 0.9, 4.5, 0.2, 1.8), (400, 2.00)),
        fruit("lychees", "Lychees", ["lychee", "lychees", "litchi"], .g, nil, n(66, 0.8, 17, 0.4, 1.3), (200, 2.00)),
        fruit("papaya", "Papaya", ["papaya", "pawpaw"], .piece, 450, n(43, 0.5, 11, 0.3, 1.7), (1, 1.50)).keeps(5),
        fruit("coconut", "Fresh coconut", ["fresh coconut", "coconut", "coconut flesh"], .piece, 400, n(354, 3.3, 15, 33, 9), (1, 1.25)).keeps(30).kept(.cupboard),
        fruit("frozen-mango", "Frozen mango", ["frozen mango", "frozen mango chunks", "mango chunks"], .g, nil, n(60, 0.8, 15, 0.4, 1.6), (500, 2.25)).sort(.frozen).kept(.freezer).keeps(365).dense(0.6),
        fruit("tinned-fruit", "Tinned fruit", ["tinned peaches", "peach slices in juice", "canned peaches", "tinned fruit", "fruit cocktail", "tinned pears", "mandarin segments", "tinned mandarins"], .g, nil, n(50, 0.5, 12, 0, 1), (410, 0.85)).sort(.tins).kept(.cupboard).keeps(700).tin(410).dense(1.05),
    ]

    static let herbs: [Food] = [
        herb("mint", "Mint", ["mint", "fresh mint", "mint leaves", "garden mint", "spearmint", "fresh mint leaves"], .g, nil, n(44, 3.3, 8, 0.7, 6.8), (30, 0.80)),
        herb("dill", "Dill", ["dill", "fresh dill", "dill fronds"], .g, nil, n(43, 3.5, 7, 1.1, 2.1), (30, 0.80)),
        herb("chives", "Chives", ["chives", "fresh chives", "snipped chives", "chive", "garlic chives"], .g, nil, n(30, 3.3, 4.4, 0.7, 2.5), (30, 0.80)),
        herb("thyme-fresh", "Fresh thyme", ["fresh thyme", "thyme sprigs", "thyme sprig", "sprigs of thyme", "sprig of thyme", "thyme leaves", "lemon thyme", "fresh thyme leaves"], .g, nil, n(101, 5.6, 24, 1.7, 14), (30, 0.80)),
        herb("rosemary-fresh", "Fresh rosemary", ["fresh rosemary", "rosemary sprigs", "rosemary sprig", "sprigs of rosemary", "sprig of rosemary", "rosemary leaves"], .g, nil, n(131, 3.3, 21, 5.9, 14), (30, 0.80)),
        herb("sage", "Sage", ["sage", "fresh sage", "sage leaves", "fresh sage leaves"], .g, nil, n(120, 4, 20, 4, 10), (30, 0.80)),
        herb("tarragon", "Tarragon", ["tarragon", "fresh tarragon"], .g, nil, n(49, 3.4, 7, 1.1, 3), (30, 0.80)),
        herb("oregano-fresh", "Fresh oregano", ["fresh oregano", "oregano leaves", "marjoram", "fresh marjoram"], .g, nil, n(60, 2, 10, 1, 6), (30, 0.80)),
        herb("thai-basil", "Thai basil", ["thai basil", "holy basil", "thai sweet basil"], .g, nil, n(23, 3.2, 2.7, 0.6, 1.6), (30, 1.00)),
        herb("curry-leaves", "Curry leaves", ["curry leaves", "curry leaf", "fresh curry leaves", "dried curry leaves"], .g, nil, n(108, 6, 18, 1, 6), (20, 1.00)),
        herb("lime-leaves", "Lime leaves", ["lime leaves", "kaffir lime leaves", "makrut lime leaves", "lime leaf", "kaffir lime leaf", "makrut lime leaf", "dried lime leaves"], .piece, 0.5, n(100, 4, 20, 1, 10), (20, 1.50)).keeps(180).kept(.cupboard),
        herb("chervil", "Chervil", ["chervil", "fresh chervil", "sorrel", "lovage"], .g, nil, n(40, 3, 6, 0.8, 3), (30, 1.00)),
        spice("bay-leaves", "Bay leaves", ["bay leaf", "bay leaves", "dried bay leaves", "fresh bay leaves", "dried bay leaf"], .piece, 0.2, n(313, 7.6, 75, 8.4, 26), (30, 1.10)),
    ]

    static let spices: [Food] = [
        spice("ground-cumin", "Ground cumin", ["cumin", "ground cumin", "cumin powder", "jeera powder"], .g, nil, n(375, 18, 44, 22, 10.5), (42, 1.10)),
        spice("cumin-seeds", "Cumin seeds", ["cumin seeds", "whole cumin", "jeera", "cumin seed", "black cumin seeds"], .g, nil, n(375, 18, 44, 22, 10.5), (42, 1.10)),
        spice("ground-coriander", "Ground coriander", ["ground coriander", "coriander powder", "dhania powder", "dhania"], .g, nil, n(298, 12, 22, 18, 42), (32, 1.10)),
        spice("coriander-seeds", "Coriander seeds", ["coriander seeds", "whole coriander", "coriander seed"], .g, nil, n(298, 12, 22, 18, 42), (32, 1.10)),
        spice("smoked-paprika", "Smoked paprika", ["smoked paprika", "pimenton", "pimentón", "sweet smoked paprika", "hot smoked paprika", "spanish smoked paprika"], .g, nil, n(282, 14, 27, 13, 35), (48, 1.20)),
        spice("paprika", "Paprika", ["paprika", "sweet paprika", "hot paprika", "hungarian paprika", "mild paprika"], .g, nil, n(282, 14, 27, 13, 35), (48, 1.10)),
        spice("chilli-powder", "Chilli powder", ["chilli powder", "chili powder", "hot chilli powder", "mild chilli powder", "kashmiri chilli powder", "kashmiri chili powder", "red chilli powder", "extra hot chilli powder"], .g, nil, n(282, 13, 50, 14, 35), (40, 1.10)),
        spice("chilli-flakes", "Chilli flakes", ["chilli flakes", "chili flakes", "red pepper flakes", "crushed chillies", "crushed red pepper", "dried chilli flakes", "chilli flake", "aleppo pepper", "pul biber", "gochugaru", "korean chilli flakes", "urfa chilli", "urfa biber"], .g, nil, n(318, 12, 29, 17, 27), (36, 1.10)),
        spice("cayenne", "Cayenne pepper", ["cayenne", "cayenne pepper", "ground cayenne"], .g, nil, n(318, 12, 29, 17, 27), (40, 1.10)),
        spice("turmeric", "Ground turmeric", ["turmeric", "ground turmeric", "haldi", "turmeric powder"], .g, nil, n(312, 10, 67, 3, 22), (40, 1.10)),
        spice("garam-masala", "Garam masala", ["garam masala"], .g, nil, n(379, 15, 45, 15, 20), (44, 1.10)),
        spice("curry-powder", "Curry powder", ["curry powder", "mild curry powder", "medium curry powder", "hot curry powder", "madras curry powder", "madras powder"], .g, nil, n(325, 14, 56, 14, 53), (90, 1.10)),
        spice("ras-el-hanout", "Ras el hanout", ["ras el hanout", "ras-el-hanout", "ras al hanout"], .g, nil, n(330, 12, 55, 12, 30), (38, 1.50)),
        spice("zaatar", "Za'atar", ["za'atar", "zaatar", "zahtar"], .g, nil, n(350, 12, 40, 18, 25), (40, 1.50)),
        spice("sumac", "Sumac", ["sumac", "sumach", "ground sumac"], .g, nil, n(240, 4, 25, 14, 30), (40, 1.50)),
        spice("cinnamon", "Ground cinnamon", ["cinnamon", "ground cinnamon", "cinnamon powder"], .g, nil, n(247, 4, 55, 1.2, 53), (39, 1.10)),
        spice("cinnamon-sticks", "Cinnamon sticks", ["cinnamon stick", "cinnamon sticks", "cinnamon quills", "cinnamon quill", "cassia bark"], .piece, 3, n(247, 4, 55, 1.2, 53), (8, 1.50)),
        spice("nutmeg", "Nutmeg", ["nutmeg", "ground nutmeg", "grated nutmeg", "whole nutmeg", "freshly grated nutmeg", "mace"], .g, nil, n(525, 6, 49, 36, 21), (42, 1.25)),
        spice("allspice", "Allspice", ["allspice", "ground allspice", "allspice berries", "pimento"], .g, nil, n(263, 6, 40, 8.7, 22), (40, 1.25)),
        spice("whole-cloves", "Cloves (spice)", ["whole cloves", "ground cloves", "clove powder", "cloves spice"], .g, nil, n(274, 6, 33, 13, 34), (30, 1.25)),
        spice("star-anise", "Star anise", ["star anise", "star anise pods", "star anise pod", "aniseed", "anise seeds"], .piece, 2, n(337, 18, 50, 16, 15), (12, 1.50)),
        spice("cardamom-pods", "Cardamom pods", ["cardamom pods", "cardamom pod", "green cardamom", "green cardamom pods", "cardamom", "black cardamom", "black cardamom pods", "cardamon pods"], .piece, 0.3, n(311, 11, 68, 6.7, 28), (40, 1.75)),
        spice("ground-cardamom", "Ground cardamom", ["ground cardamom", "cardamom powder", "ground cardamon"], .g, nil, n(311, 11, 68, 6.7, 28), (25, 1.75)),
        spice("fennel-seeds", "Fennel seeds", ["fennel seeds", "fennel seed", "saunf", "ground fennel"], .g, nil, n(345, 16, 52, 15, 40), (36, 1.10)),
        spice("mustard-seeds", "Mustard seeds", ["mustard seeds", "black mustard seeds", "yellow mustard seeds", "brown mustard seeds", "mustard seed"], .g, nil, n(508, 26, 28, 36, 12), (52, 1.10)),
        spice("mustard-powder", "Mustard powder", ["mustard powder", "english mustard powder", "dry mustard", "ground mustard"], .g, nil, n(508, 26, 28, 36, 12), (57, 1.50)),
        spice("nigella-seeds", "Nigella seeds", ["nigella seeds", "black onion seeds", "kalonji", "nigella", "onion seeds"], .g, nil, n(375, 18, 44, 22, 10), (40, 1.25)),
        spice("fenugreek", "Fenugreek", ["fenugreek", "fenugreek seeds", "methi", "dried fenugreek leaves", "kasuri methi", "fenugreek leaves", "methi leaves"], .g, nil, n(323, 23, 58, 6.4, 25), (40, 1.25)),
        spice("asafoetida", "Asafoetida", ["asafoetida", "hing", "asafetida"], .g, nil, n(297, 4, 68, 1, 4), (50, 1.75)),
        spice("caraway", "Caraway seeds", ["caraway", "caraway seeds", "caraway seed"], .g, nil, n(333, 20, 50, 15, 38), (40, 1.25)),
        spice("black-pepper", "Black pepper", ["black pepper", "ground black pepper", "cracked black pepper", "black peppercorns", "peppercorns", "freshly ground black pepper", "whole peppercorns", "mixed peppercorns", "pink peppercorns"], .g, nil, n(251, 10, 64, 3.3, 25), (50, 1.10)),
        spice("white-pepper", "White pepper", ["white pepper", "ground white pepper", "white peppercorns"], .g, nil, n(296, 10, 69, 2, 26), (50, 1.25)),
        spice("sichuan-pepper", "Sichuan peppercorns", ["sichuan peppercorns", "szechuan peppercorns", "sichuan pepper", "szechuan pepper", "sichuan peppercorn"], .g, nil, n(300, 6, 66, 9, 25), (30, 2.00)),
        spice("dried-oregano", "Dried oregano", ["oregano", "dried oregano", "mexican oregano"], .g, nil, n(265, 9, 69, 4.3, 42.5), (12, 1.10)),
        spice("dried-thyme", "Dried thyme", ["thyme", "dried thyme", "dried thyme leaves"], .g, nil, n(276, 9, 64, 7.4, 37), (13, 1.10)),
        spice("dried-rosemary", "Dried rosemary", ["rosemary", "dried rosemary"], .g, nil, n(331, 4.9, 64, 15, 43), (20, 1.10)),
        spice("dried-basil", "Dried basil", ["dried basil", "basil flakes"], .g, nil, n(233, 23, 26, 4, 38), (13, 1.10)),
        spice("dried-parsley", "Dried parsley", ["dried parsley", "parsley flakes"], .g, nil, n(292, 27, 51, 5.5, 27), (12, 1.10)),
        spice("dried-mint", "Dried mint", ["dried mint", "dried mint leaves"], .g, nil, n(285, 20, 52, 6, 30), (15, 1.10)),
        spice("dried-dill", "Dried dill", ["dried dill", "dill weed", "dried dill weed"], .g, nil, n(253, 20, 56, 4.4, 14), (15, 1.10)),
        spice("dried-sage", "Dried sage", ["dried sage", "rubbed sage", "ground sage"], .g, nil, n(315, 10.6, 61, 12.8, 40), (13, 1.10)),
        spice("dried-tarragon", "Dried tarragon", ["dried tarragon"], .g, nil, n(295, 23, 50, 7, 7), (12, 1.25)),
        spice("dried-chives", "Dried chives", ["dried chives", "freeze dried chives"], .g, nil, n(311, 21, 64, 3.5, 26), (5, 1.25)),
        spice("mixed-herbs", "Mixed herbs", ["mixed herbs", "dried mixed herbs", "herbes de provence", "italian herbs", "italian seasoning", "mediterranean herbs", "italian mixed herbs", "herbs de provence"], .g, nil, n(280, 10, 60, 6, 35), (14, 1.10)),
    ]

    static let seasonings: [Food] = [
        spice("five-spice", "Chinese five spice", ["chinese five spice", "five spice", "5 spice", "chinese 5 spice", "five spice powder", "chinese five-spice"], .g, nil, n(340, 10, 60, 10, 30), (50, 1.10)),
        spice("cajun-seasoning", "Cajun seasoning", ["cajun seasoning", "cajun spice", "cajun spice mix", "cajun", "creole seasoning"], .g, nil, n(280, 10, 50, 8, 20), (50, 1.10)),
        spice("fajita-seasoning", "Fajita seasoning", ["fajita seasoning", "fajita spice mix", "fajita spice", "fajita mix"], .g, nil, n(280, 8, 50, 6, 15), (30, 0.90)),
        spice("taco-seasoning", "Taco seasoning", ["taco seasoning", "taco spice mix", "mexican seasoning", "chilli con carne mix", "taco mix"], .g, nil, n(280, 8, 50, 6, 15), (30, 0.90)),
        spice("jerk-seasoning", "Jerk seasoning", ["jerk seasoning", "jerk spice", "jerk rub", "jerk paste", "jerk marinade"], .g, nil, n(250, 8, 45, 6, 15), (50, 1.25)),
        spice("peri-peri-seasoning", "Peri peri seasoning", ["peri peri seasoning", "piri piri seasoning", "peri peri rub", "piri piri", "peri-peri seasoning", "peri peri spice"], .g, nil, n(280, 8, 50, 6, 15), (50, 1.25)),
        spice("garlic-powder", "Garlic powder", ["garlic powder", "garlic granules", "granulated garlic", "garlic salt", "dried garlic"], .g, nil, n(331, 17, 73, 0.7, 9), (60, 1.10)),
        spice("onion-powder", "Onion powder", ["onion powder", "onion granules", "onion salt", "dried onion", "crispy onions", "crispy fried onions"], .g, nil, n(341, 10, 79, 1, 15), (55, 1.10)),
        spice("ground-ginger", "Ground ginger", ["ground ginger", "ginger powder", "dried ginger"], .g, nil, n(335, 9, 72, 4.2, 14), (28, 1.10)),
        spice("mixed-spice", "Mixed spice", ["mixed spice", "pumpkin spice", "pumpkin pie spice", "apple pie spice", "speculaas spice"], .g, nil, n(300, 6, 70, 6, 30), (37, 1.10)),
        spice("saffron", "Saffron", ["saffron", "saffron threads", "saffron strands", "pinch of saffron", "saffron powder"], .g, nil, n(310, 11, 65, 6, 4), (1, 4.00)),
        spice("celery-salt", "Celery salt", ["celery salt", "celery seeds", "celery seed"], .g, nil, n(100, 4, 15, 4, 5), (60, 1.25)),
        spice("msg", "MSG", ["msg", "monosodium glutamate", "ajinomoto"], .g, nil, n(0, 0, 0, 0), (100, 1.50)),
        spice("black-salt", "Black salt (kala namak)", ["black salt", "kala namak", "indian black salt"], .g, nil, n(0, 0, 0, 0), (100, 1.50)),
        spice("chaat-masala", "Chaat masala", ["chaat masala", "chat masala"], .g, nil, n(250, 10, 40, 5, 15), (100, 1.50)),
        spice("tandoori-masala", "Tandoori masala", ["tandoori masala", "tandoori spice", "tandoori seasoning", "tandoori spice mix"], .g, nil, n(300, 10, 50, 8, 20), (100, 1.50)),
        spice("amchur", "Amchur (mango powder)", ["amchur", "amchoor", "mango powder", "dry mango powder"], .g, nil, n(330, 2, 75, 2, 10), (100, 1.50)),
        spice("baharat", "Baharat", ["baharat", "lebanese seven spice", "seven spice"], .g, nil, n(320, 10, 55, 10, 25), (40, 1.75)),
        spice("dukkah", "Dukkah", ["dukkah", "dukka", "duqqa"], .g, nil, n(500, 18, 20, 40, 10), (80, 2.50)),
        spice("everything-seasoning", "Everything bagel seasoning", ["everything bagel seasoning", "everything seasoning", "everything bagel spice"], .g, nil, n(450, 15, 30, 30, 12), (60, 2.00)),
        spice("togarashi", "Shichimi togarashi", ["shichimi togarashi", "togarashi", "shichimi", "japanese seven spice"], .g, nil, n(350, 12, 50, 12, 25), (15, 2.50)),
        spice("lemon-pepper", "Lemon pepper", ["lemon pepper", "lemon pepper seasoning"], .g, nil, n(200, 6, 40, 2, 10), (60, 1.25)),
        spice("chipotle-powder", "Chipotle powder", ["chipotle flakes", "chipotle powder", "ground chipotle", "chipotle chilli powder", "chipotle chilli flakes"], .g, nil, n(320, 12, 56, 6, 28), (40, 1.50)),
        spice("vanilla-pod", "Vanilla pods", ["vanilla pod", "vanilla pods", "vanilla bean", "vanilla beans", "vanilla seeds"], .piece, 3, n(230, 4, 40, 6, 0), (2, 3.50)).sort(.condiments),
        spice("smoked-salt", "Sea salt flakes", ["sea salt flakes", "flaky salt", "maldon salt", "smoked salt", "flaky sea salt", "kosher salt", "rock salt", "pink himalayan salt", "himalayan salt"], .g, nil, n(0, 0, 0, 0), (250, 1.75)),
    ]

    static let pulses: [Food] = [
        pulse("butter-beans", "Butter beans", ["butter beans", "lima beans", "tin of butter beans", "giant butter beans", "judion beans", "butterbeans"], .g, nil, n(77, 5.9, 13, 0.5, 4.6), (235, 0.75)).tin(235),
        pulse("cannellini-beans", "Cannellini beans", ["cannellini beans", "cannellini", "white beans", "tin of cannellini beans", "white kidney beans"], .g, nil, n(91, 6.5, 13, 0.6, 6), (240, 0.75)).tin(240),
        pulse("borlotti-beans", "Borlotti beans", ["borlotti beans", "borlotti", "cranberry beans", "roman beans"], .g, nil, n(103, 7, 15, 0.5, 6), (240, 0.85)).tin(240),
        pulse("haricot-beans", "Haricot beans", ["haricot beans", "navy beans", "haricot"], .g, nil, n(90, 6.5, 13, 0.5, 6), (240, 0.75)).tin(240),
        pulse("pinto-beans", "Pinto beans", ["pinto beans", "pinto"], .g, nil, n(99, 6.6, 15, 0.6, 5.5), (240, 0.85)).tin(240),
        pulse("black-eyed-beans", "Black-eyed beans", ["black-eyed beans", "black eyed beans", "black-eyed peas", "black eyed peas"], .g, nil, n(94, 6.9, 14, 0.6, 4.5), (240, 0.85)).tin(240),
        pulse("aduki-beans", "Aduki beans", ["aduki beans", "adzuki beans", "azuki beans", "red beans", "red bean paste"], .g, nil, n(110, 7.5, 20, 0.2, 5.5), (240, 1.00)).tin(240),
        pulse("mixed-beans", "Mixed beans", ["mixed beans", "three bean mix", "mixed bean salad", "bean mix", "mixed beans in water", "five bean mix"], .g, nil, n(100, 7, 14, 0.6, 6), (240, 0.85)).tin(240),
        pulse("flageolet-beans", "Flageolet beans", ["flageolet beans", "flageolet"], .g, nil, n(95, 7, 14, 0.6, 5), (265, 1.25)).tin(265),
        pulse("broad-beans", "Broad beans", ["broad beans", "fava beans", "broad bean", "frozen broad beans"], .g, nil, n(81, 7.6, 11, 0.6, 5.4), (500, 1.75)).sort(.frozen).kept(.freezer).keeps(365).group("greenveg"),
        pulse("edamame", "Edamame beans", ["edamame", "edamame beans", "soya beans", "soybeans", "soy beans", "frozen edamame"], .g, nil, n(121, 12, 9, 5, 5), (500, 2.25)).sort(.frozen).kept(.freezer).keeps(365).group("greenveg"),
        pulse("tinned-lentils", "Tinned lentils", ["tinned lentils", "lentils in water", "tin of lentils", "canned lentils", "cooked lentils", "tinned green lentils", "green lentils in water"], .g, nil, n(100, 7.5, 15, 0.5, 4.5), (265, 0.85)).tin(265),
        pulse("refried-beans", "Refried beans", ["refried beans", "refried pinto beans", "refried black beans"], .g, nil, n(90, 5, 13, 1.5, 5), (435, 1.50)).tin(435).dense(1.05),
        pulse("jackfruit", "Jackfruit", ["jackfruit", "young jackfruit", "green jackfruit", "jackfruit in brine", "pulled jackfruit", "young green jackfruit"], .g, nil, n(25, 1, 4, 0.2, 3), (225, 1.50)).tin(225),
        grain("dried-chickpeas", "Dried chickpeas", ["dried chickpeas", "dry chickpeas"], .g, nil, n(364, 19, 61, 6, 17), (500, 1.25)).keeps(700).group("beans"),
        grain("dried-beans", "Dried beans", ["dried beans", "dried kidney beans", "dried black beans", "dried butter beans", "dried cannellini beans", "dry beans"], .g, nil, n(340, 22, 60, 1.5, 20), (500, 1.50)).keeps(700).group("beans"),
        grain("green-lentils", "Green lentils", ["green lentils", "french green lentils", "dried green lentils", "brown lentils", "beluga lentils", "black lentils", "dried brown lentils"], .g, nil, n(336, 24, 49, 1.9, 11), (500, 1.50)).keeps(700).group("beans"),
        grain("puy-lentils", "Puy lentils", ["puy lentils", "puy", "pouch of puy lentils", "ready to eat puy lentils", "lentil pouch", "ready cooked lentils"], .g, nil, n(140, 9, 19, 1, 5), (250, 1.75)).group("beans"),
        grain("split-peas", "Yellow split peas", ["yellow split peas", "split peas", "green split peas", "split yellow peas", "marrowfat peas"], .g, nil, n(341, 24, 60, 1.2, 25), (500, 1.10)).keeps(700).group("beans"),
        grain("chana-dal", "Chana dal", ["chana dal", "chana daal", "channa dal", "split chickpeas", "bengal gram", "chana dhal"], .g, nil, n(360, 22, 58, 5, 15), (500, 1.75)).keeps(700).group("beans"),
        grain("urad-dal", "Urad dal", ["urad dal", "urad daal", "black gram", "whole urad", "urid dal", "black lentils urad"], .g, nil, n(340, 25, 59, 1.6, 18), (500, 1.75)).keeps(700).group("beans"),
        grain("moong-dal", "Moong dal", ["moong dal", "mung dal", "yellow moong dal", "mung beans", "moong beans", "green mung beans", "moong daal"], .g, nil, n(347, 24, 63, 1.2, 16), (500, 1.75)).keeps(700).group("beans"),
        grain("toor-dal", "Toor dal", ["toor dal", "toor daal", "arhar dal", "pigeon peas", "tuvar dal"], .g, nil, n(343, 22, 63, 1.5, 15), (500, 1.75)).keeps(700).group("beans"),
    ]

    static let grains: [Food] = [
        grain("risotto-rice", "Risotto rice", ["risotto rice", "arborio", "arborio rice", "carnaroli", "carnaroli rice", "vialone nano"], .g, nil, n(350, 7, 79, 0.6, 1), (500, 1.50)).dense(0.85).group("grain"),
        grain("jasmine-rice", "Jasmine rice", ["jasmine rice", "thai jasmine rice", "thai fragrant rice", "fragrant rice"], .g, nil, n(355, 7, 79, 0.6, 1), (1000, 2.00)).group("grain"),
        grain("sushi-rice", "Sushi rice", ["sushi rice", "short grain rice", "japanese rice", "glutinous rice", "sticky rice", "calrose rice"], .g, nil, n(355, 6.5, 80, 0.5, 0.5), (500, 2.00)).dense(0.85).group("grain"),
        grain("wild-rice", "Wild rice", ["wild rice", "wild rice mix", "red camargue rice", "red rice", "black rice", "forbidden rice"], .g, nil, n(357, 14, 75, 1.1, 6), (500, 2.50)).group("grain"),
        grain("pudding-rice", "Pudding rice", ["pudding rice", "rice pudding rice"], .g, nil, n(350, 7, 79, 0.6, 0.5), (500, 1.00)).dense(0.85),
        grain("paella-rice", "Paella rice", ["paella rice", "bomba rice", "calasparra rice"], .g, nil, n(350, 7, 79, 0.6, 1), (500, 2.25)).dense(0.85).group("grain"),
        grain("bulgur", "Bulgur wheat", ["bulgur wheat", "bulgur", "bulghur", "cracked wheat", "burghul", "bulgar wheat"], .g, nil, n(342, 12, 76, 1.3, 12), (500, 1.25)).dense(0.75).group("grain"),
        grain("giant-couscous", "Giant couscous", ["giant couscous", "pearl couscous", "israeli couscous", "moghrabieh", "maftoul"], .g, nil, n(355, 12, 73, 1.5, 3), (500, 1.50)).dense(0.7).group("grain"),
        grain("pearl-barley", "Pearl barley", ["pearl barley", "barley", "pot barley"], .g, nil, n(352, 10, 78, 1.2, 15), (500, 0.95)).group("grain"),
        grain("freekeh", "Freekeh", ["freekeh", "frikeh"], .g, nil, n(325, 13, 62, 2.5, 16), (200, 2.25)).group("grain"),
        grain("farro", "Farro", ["farro", "spelt grain", "pearled spelt", "emmer", "spelt", "pearled farro"], .g, nil, n(340, 13, 68, 2.5, 10), (500, 2.50)).group("grain"),
        grain("buckwheat", "Buckwheat", ["buckwheat", "buckwheat groats", "kasha", "roasted buckwheat"], .g, nil, n(343, 13, 72, 3.4, 10), (500, 2.50)).dense(0.75).group("grain"),
        grain("millet", "Millet", ["millet", "millet grain", "hulled millet"], .g, nil, n(378, 11, 73, 4.2, 8.5), (500, 2.00)).group("grain"),
        grain("polenta", "Polenta", ["polenta", "cornmeal", "quick cook polenta", "instant polenta", "maize meal", "fine cornmeal", "coarse cornmeal", "grits", "masa harina"], .g, nil, n(362, 8, 79, 1.8, 4), (500, 1.50)).dense(0.65),
        grain("semolina", "Semolina", ["semolina", "durum wheat semolina", "fine semolina", "sooji", "rava", "semola"], .g, nil, n(360, 12.7, 73, 1, 4), (500, 1.00)).dense(0.65),
        grain("amaranth", "Amaranth", ["amaranth", "teff", "sorghum"], .g, nil, n(371, 14, 65, 7, 7), (500, 2.50)).group("grain"),
        grain("cereal", "Breakfast cereal", ["cornflakes", "corn flakes", "rice krispies", "puffed rice", "bran flakes", "weetabix", "shredded wheat", "breakfast cereal", "cereal"], .g, 19, n(370, 8, 80, 1.5, 6), (500, 1.50)).dense(0.12),
        grain("popcorn", "Popcorn kernels", ["popcorn kernels", "popping corn", "popcorn", "popcorn maize"], .g, nil, n(375, 12, 74, 4.5, 15), (500, 1.25)).dense(0.75).sort(.snacks),
    ]

    static let pastaAndNoodles: [Food] = [
        grain("lasagne-sheets", "Lasagne sheets", ["lasagne sheets", "lasagne", "lasagna sheets", "lasagne sheet", "lasagna", "dried lasagne sheets", "lasagna noodles"], .piece, 18, n(355, 12, 72, 1.5, 3), (14, 0.95)).keeps(700).group("pasta"),
        grain("cannelloni", "Cannelloni tubes", ["cannelloni tubes", "cannelloni", "manicotti"], .piece, 12, n(355, 12, 72, 1.5, 3), (20, 1.25)).keeps(700),
        grain("gnocchi", "Gnocchi", ["gnocchi", "potato gnocchi", "fresh gnocchi"], .g, nil, n(150, 3.6, 32, 0.3, 2), (500, 1.25)).keeps(30).group("pasta"),
        grain("fresh-pasta", "Fresh pasta", ["fresh pasta", "fresh tagliatelle", "fresh linguine", "fresh lasagne sheets", "fresh egg pasta", "fresh fettuccine", "fresh pappardelle", "pappardelle", "fettuccine"], .g, nil, n(270, 11, 50, 3, 2), (500, 2.00)).keeps(14).kept(.fridge).group("pasta"),
        grain("filled-pasta", "Filled pasta", ["tortellini", "ravioli", "fresh ravioli", "fresh tortellini", "girasole", "filled pasta", "cappelletti", "spinach and ricotta tortellini", "mushroom ravioli"], .g, nil, n(250, 10, 35, 8, 2.5), (300, 2.25)).keeps(14).kept(.fridge).group("pasta"),
        grain("gluten-free-pasta", "Gluten-free pasta", ["gluten free pasta", "gluten-free pasta", "gf pasta", "corn pasta", "brown rice pasta"], .g, nil, n(355, 7, 78, 1.5, 2), (500, 1.50)).keeps(700).group("pasta"),
        grain("legume-pasta", "Lentil or chickpea pasta", ["red lentil pasta", "chickpea pasta", "lentil pasta", "edamame pasta", "bean pasta", "pea pasta", "high protein pasta"], .g, nil, n(340, 23, 52, 2, 8), (250, 2.00)).keeps(700).group("pasta"),
        grain("soba", "Soba noodles", ["soba noodles", "soba", "buckwheat noodles"], .g, nil, n(340, 13, 68, 1.5, 3.5), (250, 2.00)).group("noodle"),
        grain("udon", "Udon noodles", ["udon noodles", "udon", "straight to wok udon", "fresh udon", "udon noodle"], .g, nil, n(140, 3.5, 28, 0.6, 1.2), (300, 1.50)).keeps(180).group("noodle"),
        grain("ramen", "Ramen noodles", ["ramen noodles", "ramen", "instant noodles", "instant ramen", "dried ramen noodles"], .g, nil, n(440, 9, 60, 18, 3), (340, 1.50)).group("noodle"),
        grain("glass-noodles", "Glass noodles", ["glass noodles", "cellophane noodles", "bean thread noodles", "mung bean noodles", "sweet potato noodles", "japchae noodles"], .g, nil, n(350, 0.2, 86, 0.1, 0.5), (100, 1.25)).group("noodle"),
        grain("wholewheat-noodles", "Wholewheat noodles", ["wholewheat noodles", "whole wheat noodles", "wholemeal noodles", "wholewheat noodle nests"], .g, nil, n(345, 13, 64, 2.5, 8), (250, 1.25)).group("noodle"),
        grain("rice-paper", "Rice paper wrappers", ["rice paper", "rice paper wrappers", "rice paper sheets", "rice paper rolls", "rice paper wrapper"], .piece, 9, n(330, 6, 78, 0.5, 1), (22, 2.00)).keeps(700),
        grain("dumpling-wrappers", "Dumpling wrappers", ["dumpling wrappers", "gyoza wrappers", "wonton wrappers", "spring roll wrappers", "spring roll pastry", "gyoza skins", "wonton skins"], .piece, 8, n(290, 9, 58, 1.5, 2), (30, 2.25)).keeps(365).kept(.freezer),
    ]

    static let breadAndPastry: [Food] = [
        bakery("filo-pastry", "Filo pastry", ["filo pastry", "filo", "phyllo", "phyllo pastry", "filo sheets", "sheets of filo", "filo pastry sheets", "sheet of filo", "filo sheet"], .piece, 25, n(300, 8, 60, 3, 2), (7, 1.85)).keeps(21).kept(.fridge),
        bakery("puff-pastry", "Puff pastry", ["puff pastry", "ready rolled puff pastry", "all butter puff pastry", "sheet of puff pastry", "puff pastry sheet", "ready-rolled puff pastry", "puff pastry block", "vegan puff pastry", "light puff pastry"], .piece, 320, n(400, 6, 36, 25, 1.5), (1, 1.40)).keeps(21).kept(.fridge),
        bakery("shortcrust-pastry", "Shortcrust pastry", ["shortcrust pastry", "shortcrust", "ready rolled shortcrust pastry", "sweet shortcrust pastry", "pie crust", "shortcrust pastry sheet", "pastry"], .piece, 320, n(450, 6, 50, 25, 2), (1, 1.25)).keeps(21).kept(.fridge),
        bakery("pastry-cases", "Pastry cases", ["pastry case", "pastry cases", "tart case", "tart cases", "tartlet cases", "vol au vent cases", "sweet pastry case"], .piece, 30, n(500, 6, 55, 28, 2), (12, 1.75)).keeps(90),
        bakery("pizza-dough", "Pizza dough", ["pizza dough", "pizza base dough", "bread dough", "fresh pizza dough"], .g, nil, n(240, 8, 45, 3, 2), (400, 1.50)).kept(.fridge),
        bakery("pizza-bases", "Pizza bases", ["pizza bases", "pizza base", "pizza crust", "flatbread pizza bases", "stonebaked pizza bases"], .piece, 150, n(270, 9, 50, 4, 2.5), (2, 1.25)).keeps(14),
        bakery("taco-shells", "Taco shells", ["taco shells", "taco shell", "hard taco shells", "crunchy taco shells", "stand and stuff tacos"], .piece, 11, n(470, 6, 60, 22, 5), (12, 1.50)).keeps(180),
        bakery("corn-tortillas", "Corn tortillas", ["corn tortillas", "corn tortilla", "soft corn tortillas", "tostadas", "street taco tortillas", "mini tortillas"], .piece, 25, n(220, 6, 45, 3, 6), (12, 2.00)).keeps(14).group("flatbread"),
        bakery("chapati", "Chapatis", ["chapati", "chapatis", "chapatti", "roti", "rotis", "paratha", "parathas", "chapattis"], .piece, 45, n(280, 8, 47, 7, 4), (8, 1.50)).keeps(7).group("flatbread"),
        bakery("english-muffins", "English muffins", ["english muffins", "english muffin", "breakfast muffins"], .piece, 65, n(230, 9, 44, 2, 2.5), (4, 1.00)).group("bread"),
        bakery("crumpets", "Crumpets", ["crumpets", "crumpet", "pikelets"], .piece, 55, n(190, 6, 38, 0.7, 2), (6, 0.80)),
        bakery("ciabatta", "Ciabatta", ["ciabatta", "ciabatta loaf", "ciabatta rolls", "focaccia", "ciabatta roll"], .piece, 270, n(260, 9, 48, 3.5, 2.5), (1, 1.25)).group("bread"),
        bakery("baguette", "Baguette", ["baguette", "french stick", "baguettes", "demi baguette", "part baked baguette", "french bread"], .piece, 250, n(260, 9, 52, 1.5, 2.5), (1, 0.85)).keeps(3).group("bread"),
        bakery("brioche", "Brioche", ["brioche", "brioche loaf", "challah", "brioche slices"], .g, 35, n(350, 8, 50, 13, 2), (400, 1.75)).group("bread"),
        bakery("croissants", "Croissants", ["croissant", "croissants", "pain au chocolat", "pains au chocolat"], .piece, 60, n(415, 8, 45, 22, 2.5), (4, 1.80)).keeps(4),
        bakery("garlic-bread", "Garlic bread", ["garlic bread", "garlic baguette", "garlic flatbread", "garlic pizza bread", "cheesy garlic bread"], .g, nil, n(350, 8, 42, 16, 2.5), (210, 1.00)).keeps(14).kept(.fridge),
        bakery("crackers", "Crackers", ["crackers", "cream crackers", "water biscuits", "oatcakes", "crispbread", "ryvita", "crackerbread", "cracker"], .g, 8, n(420, 10, 70, 10, 6), (200, 1.00)).keeps(180).sort(.snacks),
        bakery("croutons", "Croutons", ["croutons", "crouton"], .g, nil, n(450, 10, 65, 16, 3), (75, 1.00)).keeps(180).dense(0.15),
        bakery("rye-bread", "Rye bread", ["rye bread", "pumpernickel", "dark rye bread", "sourdough rye"], .g, 30, n(220, 6, 41, 1.5, 7), (500, 1.75)).group("bread"),
        bakery("gluten-free-bread", "Gluten-free bread", ["gluten free bread", "gluten-free bread", "gf bread"], .g, 35, n(250, 4, 45, 6, 6), (400, 2.75)).group("bread"),
    ]

    static let flours: [Food] = [
        baking("self-raising-flour", "Self-raising flour", ["self raising flour", "self-raising flour", "self raising", "sr flour", "self rising flour"], .g, nil, n(340, 9.9, 72, 1.2, 3), (1500, 0.95)),
        baking("wholemeal-flour", "Wholemeal flour", ["wholemeal flour", "whole wheat flour", "wholewheat flour", "wholemeal bread flour", "brown flour", "strong wholemeal flour"], .g, nil, n(310, 12.6, 60, 2.2, 9), (1500, 1.10)),
        baking("bread-flour", "Strong white bread flour", ["strong white flour", "strong bread flour", "bread flour", "strong flour", "00 flour", "tipo 00 flour", "pizza flour", "pasta flour", "strong white bread flour"], .g, nil, n(345, 12, 71, 1.4, 3), (1500, 1.15)),
        baking("gram-flour", "Gram flour", ["gram flour", "chickpea flour", "besan", "garbanzo flour", "chickpea gram flour"], .g, nil, n(360, 22, 58, 6, 11), (1000, 2.00)).dense(0.5),
        baking("rice-flour", "Rice flour", ["rice flour", "glutinous rice flour", "white rice flour", "brown rice flour", "sweet rice flour"], .g, nil, n(366, 6, 80, 1.4, 2.4), (500, 1.50)).dense(0.6),
        baking("buckwheat-flour", "Buckwheat flour", ["buckwheat flour"], .g, nil, n(335, 12.6, 70, 3.1, 10), (500, 2.00)).dense(0.5),
        baking("spelt-flour", "Spelt flour", ["spelt flour", "wholegrain spelt flour", "white spelt flour", "rye flour", "dark rye flour"], .g, nil, n(340, 14, 63, 2.5, 10), (1000, 2.00)),
        baking("oat-flour", "Oat flour", ["oat flour", "ground oats", "blended oats", "oat bran"], .g, nil, n(375, 13, 60, 8, 9), (500, 2.00)).dense(0.4),
        baking("ground-almonds", "Ground almonds", ["ground almonds", "almond flour", "almond meal", "blanched ground almonds"], .g, nil, n(620, 21, 6, 55, 11), (200, 2.75)).dense(0.45),
        baking("coconut-flour", "Coconut flour", ["coconut flour"], .g, nil, n(400, 18, 20, 15, 40), (500, 3.50)).dense(0.5),
        baking("gluten-free-flour", "Gluten-free flour", ["gluten free flour", "gluten-free flour", "plain gluten free flour", "gf flour", "gluten free self raising flour"], .g, nil, n(350, 4, 80, 1.5, 3), (1000, 1.75)),
        baking("tapioca", "Tapioca starch", ["tapioca starch", "tapioca flour", "tapioca", "tapioca pearls"], .g, nil, n(358, 0.2, 88, 0.02, 0.9), (250, 1.50)),
        baking("potato-starch", "Potato starch", ["potato starch", "potato flour", "arrowroot", "arrowroot powder", "arrowroot starch"], .g, nil, n(350, 0.1, 86, 0.1, 0), (250, 1.50)).dense(0.6),
        baking("vital-wheat-gluten", "Vital wheat gluten", ["vital wheat gluten", "wheat gluten", "gluten flour"], .g, nil, n(370, 75, 14, 2, 0.6), (500, 5.00)).dense(0.5),
        baking("yeast", "Fast action dried yeast", ["fast action yeast", "dried yeast", "yeast", "easy bake yeast", "instant yeast", "active dry yeast", "fresh yeast", "sachet of yeast", "fast action dried yeast", "easy blend yeast", "sachet yeast"], .g, 7, n(325, 40, 41, 7.6, 27), (56, 1.00)).dense(0.6),
        baking("bicarbonate-of-soda", "Bicarbonate of soda", ["bicarbonate of soda", "bicarb", "baking soda", "bicarb of soda", "sodium bicarbonate"], .g, nil, n(0, 0, 0, 0), (200, 0.75)).dense(0.9).staple.keeps(700),
        baking("cream-of-tartar", "Cream of tartar", ["cream of tartar"], .g, nil, n(258, 0, 62, 0), (100, 1.50)).dense(0.9).keeps(700),
        baking("psyllium", "Psyllium husk", ["psyllium husk", "psyllium", "psyllium husk powder", "psyllium powder"], .g, nil, n(200, 2, 45, 0.6, 80), (250, 4.50)).dense(0.5),
        baking("xanthan-gum", "Xanthan gum", ["xanthan gum", "xanthan", "guar gum"], .g, nil, n(330, 0, 78, 0, 75), (100, 2.50)).dense(0.6).keeps(700),
    ]

    static let sugars: [Food] = [
        sweet("caster-sugar", "Caster sugar", ["caster sugar", "golden caster sugar", "superfine sugar", "white caster sugar"], .g, nil, n(400, 0, 100, 0), (1000, 1.40)),
        sweet("icing-sugar", "Icing sugar", ["icing sugar", "powdered sugar", "confectioners sugar", "confectioners' sugar", "golden icing sugar", "fondant icing sugar"], .g, nil, n(398, 0, 99.5, 0), (500, 1.00)).dense(0.5),
        sweet("brown-sugar", "Soft brown sugar", ["brown sugar", "light brown sugar", "soft brown sugar", "light soft brown sugar", "dark brown sugar", "dark soft brown sugar", "muscovado", "muscovado sugar", "dark muscovado sugar", "light muscovado sugar", "coconut sugar", "jaggery", "palm sugar"], .g, nil, n(380, 0.1, 98, 0), (500, 1.25)).dense(0.9),
        sweet("demerara-sugar", "Demerara sugar", ["demerara sugar", "demerara", "granulated brown sugar", "turbinado sugar", "raw cane sugar"], .g, nil, n(398, 0, 99.6, 0), (500, 1.25)).dense(0.9),
        sweet("maple-syrup", "Maple syrup", ["maple syrup", "pure maple syrup", "maple", "maple flavour syrup"], .ml, nil, n(260, 0, 67, 0.1), (250, 4.50)).dense(1.32),
        sweet("golden-syrup", "Golden syrup", ["golden syrup", "light corn syrup", "corn syrup", "glucose syrup", "liquid glucose", "rice syrup", "brown rice syrup"], .g, nil, n(325, 0.3, 80, 0), (454, 1.40)).dense(1.4),
        sweet("black-treacle", "Black treacle", ["black treacle", "treacle", "molasses", "blackstrap molasses"], .g, nil, n(290, 1.2, 74, 0), (454, 1.40)).dense(1.4),
        sweet("agave", "Agave syrup", ["agave", "agave syrup", "agave nectar"], .ml, nil, n(310, 0, 76, 0.5), (250, 2.75)).dense(1.35),
        sweet("date-syrup", "Date syrup", ["date syrup", "date nectar", "silan"], .ml, nil, n(290, 1.5, 72, 0.2), (250, 3.00)).dense(1.35),
        sweet("sweetener", "Sweetener", ["sweetener", "stevia", "erythritol", "sucralose", "splenda", "canderel", "monk fruit sweetener", "xylitol"], .g, nil, n(0, 0, 0, 0), (100, 2.50)).dense(0.3),
        sweet("marmalade", "Marmalade", ["marmalade", "orange marmalade", "lime marmalade", "apricot jam", "cherry jam", "blackcurrant jam", "fig jam"], .g, nil, n(260, 0.2, 65, 0), (454, 1.50)).dense(1.3).keeps(365),
        sweet("lemon-curd", "Lemon curd", ["lemon curd", "lime curd", "passion fruit curd", "curd"], .g, nil, n(300, 3, 55, 8), (411, 1.50)).dense(1.2).keeps(180),
        sweet("chocolate-spread", "Chocolate spread", ["chocolate spread", "hazelnut spread", "nutella", "biscoff spread", "speculoos spread", "chocolate hazelnut spread", "cookie butter"], .g, nil, n(540, 6, 57, 31, 3.5), (400, 2.50)).dense(1.2).keeps(365),
        sweet("dessert-sauce", "Chocolate or caramel sauce", ["chocolate sauce", "chocolate syrup", "caramel sauce", "toffee sauce", "salted caramel sauce", "fudge sauce"], .ml, nil, n(320, 2, 60, 9), (325, 2.00)).dense(1.3).keeps(365),
    ]

    static let bakingExtras: [Food] = [
        sweet("cocoa", "Cocoa powder", ["cocoa powder", "cocoa", "cacao powder", "cacao", "unsweetened cocoa powder", "raw cacao powder", "dutch processed cocoa"], .g, nil, n(380, 20, 12, 22, 30), (250, 2.50)).dense(0.45),
        sweet("milk-chocolate", "Milk chocolate", ["milk chocolate", "milk chocolate chips", "milk choc", "milk chocolate buttons", "chocolate buttons"], .g, nil, n(530, 7, 57, 30, 2), (100, 1.25)).sort(.snacks).dense(0.6),
        sweet("white-chocolate", "White chocolate", ["white chocolate", "white chocolate chips", "white choc chips", "white choc", "white chocolate buttons"], .g, nil, n(545, 6, 59, 31, 0), (100, 1.25)).sort(.snacks).dense(0.6),
        sweet("chocolate-chips", "Chocolate chips", ["chocolate chips", "dark chocolate chips", "choc chips", "chocolate chunks", "plain chocolate chips", "chocolate drops", "dark choc chips", "vegan chocolate chips"], .g, nil, n(500, 5, 60, 27, 6), (100, 1.25)).sort(.snacks).dense(0.6),
        sweet("condensed-milk", "Condensed milk", ["condensed milk", "sweetened condensed milk", "caramel", "dulce de leche", "condensed coconut milk", "caramel condensed milk"], .g, nil, n(330, 8, 55, 9), (397, 1.60)).sort(.tins).tin(397).dense(1.3),
        sweet("evaporated-milk", "Evaporated milk", ["evaporated milk", "light evaporated milk"], .ml, nil, n(160, 8, 11, 9), (410, 1.20)).sort(.tins).tin(410).dense(1.07),
        sweet("almond-extract", "Almond extract", ["almond extract", "almond essence", "peppermint extract", "orange extract", "lemon extract", "coconut extract", "peppermint essence"], .ml, nil, n(0, 0, 0, 0), (38, 2.00)).staple,
        sweet("vanilla-paste", "Vanilla bean paste", ["vanilla bean paste", "vanilla paste"], .ml, nil, n(290, 0, 72, 0), (65, 4.00)).dense(1.3),
        sweet("rose-water", "Rose water", ["rose water", "rosewater", "orange blossom water", "orange flower water"], .ml, nil, n(0, 0, 0, 0), (150, 1.75)),
        sweet("food-colouring", "Food colouring", ["food colouring", "food coloring", "gel food colouring", "food colour", "gel colouring"], .ml, nil, n(0, 0, 0, 0), (38, 1.50)),
        sweet("sprinkles", "Sprinkles", ["sprinkles", "hundreds and thousands", "sugar strands", "edible glitter", "sugar sprinkles"], .g, nil, n(400, 0, 98, 1), (60, 1.00)),
        sweet("glace-cherries", "Glacé cherries", ["glace cherries", "glacé cherries", "candied cherries", "maraschino cherries", "cocktail cherries"], .g, 6, n(250, 0.4, 63, 0.2, 1), (200, 1.75)),
        sweet("mixed-peel", "Mixed peel", ["mixed peel", "candied peel", "candied orange peel", "candied lemon peel", "crystallised ginger", "stem ginger"], .g, nil, n(280, 0.3, 70, 0.3, 4), (100, 1.00)),
        sweet("marzipan", "Marzipan", ["marzipan", "almond paste", "ready to roll icing", "fondant icing", "sugarpaste", "roll out icing"], .g, nil, n(430, 6, 63, 16, 2), (500, 2.50)),
        sweet("agar-agar", "Agar agar", ["agar agar", "agar", "agar flakes", "agar powder", "vege-gel", "vegetarian gelatine", "veggie gel", "vegan gelatine", "agar-agar"], .g, nil, n(26, 0.5, 7, 0), (10, 2.00)),
        sweet("desiccated-coconut", "Desiccated coconut", ["desiccated coconut", "shredded coconut", "coconut flakes", "coconut chips", "flaked coconut", "toasted coconut"], .g, nil, n(660, 6, 7, 62, 14), (200, 1.20)).dense(0.35),
        sweet("custard", "Custard", ["custard", "ready made custard", "custard powder", "instant custard", "fresh custard", "vegan custard"], .g, nil, n(100, 3, 16, 3), (500, 1.00)).sort(.dairy).kept(.fridge).keeps(10).dense(1.05),
        sweet("meringue", "Meringue nests", ["meringue nests", "meringues", "meringue", "meringue nest", "aquafaba meringues"], .piece, 12, n(390, 5, 92, 0), (8, 1.50)).keeps(180),
        sweet("biscuits", "Biscuits", ["digestive biscuits", "digestives", "biscuit", "biscuits", "graham crackers", "ginger nuts", "ginger biscuits", "hobnobs", "rich tea", "shortbread", "biscoff", "lotus biscuits", "oreos", "oreo", "amaretti", "sponge fingers", "ladyfingers", "savoiardi"], .g, 15, n(480, 7, 64, 21, 3.5), (400, 0.90)).sort(.snacks).keeps(180),
    ]

    static let dairyFoods: [Food] = [
        dairy("single-cream", "Single cream", ["single cream", "light cream", "pouring cream", "half and half", "table cream", "half fat cream"], .ml, nil, n(193, 2.6, 3.9, 19), (300, 1.00)).keeps(7),
        dairy("whipping-cream", "Whipping cream", ["whipping cream", "whipped cream", "squirty cream", "elmlea", "extra thick cream"], .ml, nil, n(373, 2, 3, 39), (300, 1.50)).keeps(10),
        dairy("creme-fraiche", "Crème fraîche", ["creme fraiche", "crème fraîche", "half fat creme fraiche", "reduced fat creme fraiche", "light creme fraiche", "half fat crème fraîche"], .ml, nil, n(290, 2.2, 2.6, 30), (300, 1.30)),
        dairy("soured-cream", "Soured cream", ["soured cream", "sour cream", "sourcream", "light soured cream"], .ml, nil, n(190, 2.7, 4, 18), (300, 1.00)),
        dairy("clotted-cream", "Clotted cream", ["clotted cream", "cornish clotted cream"], .g, nil, n(586, 1.6, 2.3, 64), (227, 2.00)),
        dairy("mascarpone", "Mascarpone", ["mascarpone", "mascarpone cheese"], .g, nil, n(435, 4.6, 4.8, 44), (250, 2.00)),
        dairy("ricotta", "Ricotta", ["ricotta", "ricotta cheese"], .g, nil, n(150, 9, 3.5, 11), (250, 1.30)).keeps(10),
        dairy("paneer", "Paneer", ["paneer", "paneer cheese", "indian cottage cheese"], .g, nil, n(320, 18, 3, 26), (225, 2.50)).keeps(21).group("protein"),
        dairy("goats-cheese", "Goat's cheese", ["goat's cheese", "goats cheese", "goat cheese", "chevre", "chèvre", "soft goats cheese", "goats cheese log", "crumbled goats cheese"], .g, nil, n(320, 20, 1, 26), (125, 1.75)).keeps(21).dense(0.6),
        dairy("blue-cheese", "Blue cheese", ["blue cheese", "stilton", "gorgonzola", "dolcelatte", "roquefort", "danish blue", "cambozola", "crumbled blue cheese"], .g, nil, n(410, 23, 0.1, 35), (200, 2.50)).keeps(30).dense(0.5),
        dairy("brie", "Brie", ["brie", "camembert", "brie cheese", "baked camembert", "camembert cheese"], .g, 250, n(345, 20, 0.5, 29), (200, 1.75)).keeps(21),
        dairy("red-leicester", "Red Leicester", ["red leicester", "double gloucester", "red leicester cheese", "monterey jack", "colby", "wensleydale", "lancashire cheese", "cheshire cheese"], .g, nil, n(400, 24, 0.1, 34), (400, 3.50)).keeps(30).dense(0.45),
        dairy("gruyere", "Gruyère", ["gruyere", "gruyère", "emmental", "comte", "comté", "swiss cheese", "jarlsberg", "raclette", "fontina", "gouda", "edam", "smoked cheese"], .g, nil, n(410, 28, 0.4, 33), (200, 3.00)).keeps(30).dense(0.45),
        dairy("manchego", "Manchego", ["manchego", "pecorino", "pecorino romano", "aged manchego"], .g, nil, n(420, 27, 0.5, 34), (150, 2.75)).keeps(60).dense(0.4),
        dairy("veggie-hard-cheese", "Italian-style hard cheese (vegetarian)", ["vegetarian italian hard cheese", "italian hard cheese", "vegetarian hard cheese", "vegetarian parmesan", "italian style hard cheese", "vegetarian pasta cheese", "veggie parmesan", "hard cheese"], .g, nil, n(390, 33, 0, 29), (150, 2.25)).keeps(60).dense(0.4),
        dairy("burrata", "Burrata", ["burrata", "burrata cheese"], .g, 150, n(300, 17, 1, 25), (150, 2.75)).keeps(7),
        dairy("quark", "Quark", ["quark", "fat free quark", "fromage frais"], .g, nil, n(65, 12, 4, 0.2), (250, 0.85)).group("yoghurt"),
        dairy("labneh", "Labneh", ["labneh", "labne", "strained yoghurt"], .g, nil, n(160, 6, 4, 13), (200, 2.00)).dense(1.05),
        dairy("buttermilk", "Buttermilk", ["buttermilk", "cultured buttermilk"], .ml, nil, n(40, 3.5, 4.5, 1), (284, 0.85)).keeps(10),
        dairy("kefir", "Kefir", ["kefir", "milk kefir", "kefir drink"], .ml, nil, n(55, 3.5, 4.5, 2.5), (500, 2.00)),
        dairy("ghee", "Ghee", ["ghee", "clarified butter", "vegan ghee", "butter ghee"], .g, nil, n(898, 0, 0, 99.8), (500, 4.75)).keeps(365).kept(.cupboard).dense(0.91),
        dairy("vegan-butter", "Plant butter or spread", ["vegan butter", "plant butter", "dairy free spread", "margarine", "flora", "stork", "baking spread", "vegan block", "sunflower spread", "olive spread", "plant based butter", "dairy free butter", "vegan spread"], .g, nil, n(530, 0.1, 0.5, 59), (250, 1.60)).keeps(60).dense(0.96),
        dairy("cheese-slices", "Cheese slices", ["cheese slices", "burger cheese", "processed cheese", "american cheese", "sliced cheese", "cheese singles", "cheese slice"], .piece, 20, n(290, 14, 7, 22), (10, 1.50)).keeps(60),
        dairy("coconut-yoghurt", "Coconut yoghurt", ["coconut yoghurt", "coconut yogurt", "coyo", "dairy free yoghurt", "vegan yoghurt", "soya yoghurt", "plant based yoghurt", "alpro yoghurt", "oat yoghurt", "vegan yogurt", "soy yogurt"], .g, nil, n(110, 1, 6, 9), (400, 2.00)).keeps(10).group("yoghurt"),
        dairy("almond-milk", "Almond milk", ["almond milk", "almond drink", "unsweetened almond milk", "almond milk unsweetened"], .ml, nil, n(13, 0.4, 0.1, 1.1), (1000, 1.75)).keeps(7).dense(1.02).group("milk"),
        dairy("soya-milk", "Soya milk", ["soya milk", "soy milk", "soya drink", "soy drink", "unsweetened soya milk"], .ml, nil, n(39, 3.3, 2.5, 1.8), (1000, 1.25)).keeps(7).dense(1.02).group("milk"),
        dairy("coconut-drink", "Coconut drink", ["coconut drink", "coconut milk drink", "coconut milk alternative", "coconut milk carton"], .ml, nil, n(20, 0.1, 2.7, 0.9), (1000, 1.75)).keeps(7).dense(1.02).group("milk"),
        dairy("rice-milk", "Rice milk", ["rice milk", "rice drink", "hazelnut milk", "cashew milk", "hemp milk", "pea milk"], .ml, nil, n(47, 0.1, 9.4, 1), (1000, 1.60)).keeps(7).dense(1.02).group("milk"),
        dairy("oat-cream", "Plant cream", ["oat cream", "soya cream", "plant cream", "vegan cream", "dairy free cream", "alpro cream", "oatly cream", "oat single cream", "soya single cream", "vegan double cream", "oat creme fraiche", "vegan creme fraiche", "vegan sour cream"], .ml, nil, n(150, 1, 6, 13), (250, 1.20)).dense(1.0),
        dairy("vegan-cheese", "Vegan cheese", ["vegan cheese", "dairy free cheese", "plant based cheese", "violife", "vegan cheddar", "vegan mozzarella", "vegan feta", "vegan parmesan", "vegan cream cheese", "vegan halloumi", "dairy free cream cheese"], .g, nil, n(280, 0.5, 20, 22), (200, 2.75)).keeps(30).dense(0.45),
        dairy("ice-cream", "Ice cream", ["ice cream", "vanilla ice cream", "dairy free ice cream", "gelato", "frozen yoghurt", "vegan ice cream", "sorbet"], .ml, nil, n(200, 3.5, 24, 10), (1000, 2.75)).sort(.frozen).kept(.freezer).keeps(365).dense(0.55),
        dairy("tzatziki", "Tzatziki", ["tzatziki", "tzatsiki", "cucumber yoghurt dip", "raita", "cucumber raita"], .g, nil, n(120, 4, 5, 9, 0.5), (200, 1.50)).keeps(7),
    ]

    static let plantFoods: [Food] = [
        plant("silken-tofu", "Silken tofu", ["silken tofu", "soft tofu", "silken", "firm silken tofu"], .g, nil, n(55, 5, 2, 2.7), (349, 2.00)).keeps(60).kept(.cupboard).dense(1.02).group("protein"),
        plant("tempeh", "Tempeh", ["tempeh", "tempe", "smoked tempeh"], .g, nil, n(195, 19, 9, 11, 5), (200, 2.75)).keeps(21).group("protein"),
        plant("seitan", "Seitan", ["seitan", "wheat protein", "seitan pieces"], .g, nil, n(140, 25, 6, 2, 1), (350, 3.50)).keeps(21).group("protein"),
        plant("tvp", "Dried soya mince (TVP)", ["tvp", "textured vegetable protein", "dried soya mince", "soya chunks", "dried soya chunks", "soy chunks", "soya mince granules", "soya protein chunks"], .g, nil, n(345, 50, 30, 1, 18), (250, 2.50)).keeps(365).kept(.cupboard).dense(0.35).group("mince"),
        plant("plant-mince", "Meat-free mince", ["plant based mince", "vegan mince", "meat free mince", "veggie mince", "vegetarian mince", "meat-free mince", "soya mince", "soy mince", "beyond mince", "plant mince", "vegetarian meat free mince"], .g, nil, n(180, 17, 6, 9, 4), (454, 3.00)).keeps(10).group("mince"),
        plant("quorn-mince", "Quorn mince", ["quorn mince", "quorn", "mycoprotein mince", "quorn vegan mince", "quorn meat free mince"], .g, nil, n(105, 14.5, 4.5, 2, 5.5), (500, 3.25)).kept(.freezer).keeps(365).group("mince"),
        plant("meat-free-chicken", "Meat-free chicken pieces", ["quorn pieces", "quorn chicken pieces", "vegan chicken pieces", "meat free chicken pieces", "plant based chicken", "vegan chicken", "chicken free pieces", "no chicken pieces", "quorn fillets", "vegan chicken strips", "meat free chicken", "vegetarian chicken pieces", "vegan chicken breast", "meat-free chicken"], .g, nil, n(110, 14, 4, 2.5, 6), (350, 3.25)).kept(.freezer).keeps(365).group("protein"),
        plant("veggie-sausages", "Vegetarian sausages", ["vegetarian sausages", "veggie sausages", "vegan sausages", "meat free sausages", "plant based sausages", "quorn sausages", "linda mccartney sausages", "cauldron sausages", "vegetarian sausage", "veggie sausage", "vegan sausage", "meat-free sausages", "vegan chipolatas"], .piece, 50, n(200, 14, 10, 11, 4), (6, 2.50)).kept(.freezer).keeps(365),
        plant("veggie-burgers", "Veggie burgers", ["veggie burgers", "vegan burgers", "veggie burger", "vegan burger", "bean burgers", "bean burger", "plant based burgers", "beyond burger", "meat free burgers", "vegetarian burgers", "quorn burgers", "plant burger"], .piece, 110, n(220, 15, 12, 12, 4), (4, 2.75)).kept(.freezer).keeps(365),
        plant("veggie-meatballs", "Meat-free meatballs", ["vegetarian meatballs", "vegan meatballs", "veggie meatballs", "meat free meatballs", "quorn meatballs", "plant based meatballs", "swedish style vegan balls"], .piece, 20, n(200, 15, 10, 10, 4), (12, 2.50)).kept(.freezer).keeps(365),
        plant("veggie-nuggets", "Meat-free nuggets", ["vegan nuggets", "veggie nuggets", "quorn nuggets", "meat free nuggets", "vegetarian nuggets", "plant based nuggets"], .piece, 20, n(230, 12, 20, 11, 4), (15, 2.50)).kept(.freezer).keeps(365),
        plant("vegan-bacon", "Meat-free bacon", ["vegan bacon", "veggie bacon", "facon", "tofu bacon", "plant based bacon", "meat free bacon", "vegetarian bacon", "vegan rashers", "quorn bacon"], .piece, 15, n(240, 20, 8, 14, 2), (8, 2.50)),
        plant("falafel", "Falafel", ["falafel", "falafels", "falafel balls", "falafel bites", "baked falafel"], .piece, 20, n(330, 13, 31, 18, 5), (12, 1.50)).keeps(7),
        plant("nutritional-yeast", "Nutritional yeast", ["nutritional yeast", "nooch", "yeast flakes", "savoury yeast flakes", "nutritional yeast flakes"], .g, nil, n(370, 50, 36, 5, 20), (125, 3.00)).keeps(365).kept(.cupboard).dense(0.25),
        plant("vegan-protein", "Vegan protein powder", ["vegan protein powder", "pea protein", "plant protein powder", "soy protein powder", "plant based protein powder", "pea protein powder", "soya protein isolate"], .g, 30, n(380, 75, 8, 6, 3), (500, 15.00)).keeps(365).kept(.cupboard).dense(0.4),
        plant("veggie-pastry-bakes", "Veggie bakes and pies", ["vegan sausage rolls", "veggie sausage rolls", "vegetable samosas", "samosas", "onion bhajis", "bhajis", "spring rolls", "vegetable spring rolls", "pakoras", "veggie bakes"], .piece, 40, n(260, 5, 30, 13, 3), (6, 2.00)).keeps(7),
    ]

    static let nuts: [Food] = [
        nut("cashews", "Cashew nuts", ["cashews", "cashew nuts", "cashew", "raw cashews", "unsalted cashews", "roasted cashews", "cashew nut"], .g, nil, n(585, 18, 20, 48, 3.3), (200, 2.50)),
        nut("walnuts", "Walnuts", ["walnuts", "walnut", "walnut halves", "walnut pieces", "chopped walnuts"], .g, nil, n(690, 15, 3, 69, 6.5), (150, 2.00)).dense(0.45),
        nut("pecans", "Pecans", ["pecans", "pecan", "pecan halves", "pecan nuts", "chopped pecans"], .g, nil, n(720, 9, 6, 72, 9), (100, 2.25)).dense(0.45),
        nut("peanuts", "Peanuts", ["peanuts", "roasted peanuts", "salted peanuts", "unsalted peanuts", "dry roasted peanuts", "peanut", "crushed peanuts", "chopped peanuts"], .g, nil, n(590, 26, 12, 50, 8), (200, 1.25)),
        nut("pistachios", "Pistachios", ["pistachios", "pistachio", "pistachio nuts", "shelled pistachios", "pistachio kernels", "chopped pistachios"], .g, nil, n(580, 20, 17, 46, 10), (150, 2.50)),
        nut("hazelnuts", "Hazelnuts", ["hazelnuts", "hazelnut", "blanched hazelnuts", "roasted hazelnuts", "ground hazelnuts", "chopped hazelnuts"], .g, nil, n(650, 15, 6, 63, 10), (150, 2.00)),
        nut("brazil-nuts", "Brazil nuts", ["brazil nuts", "brazil nut", "brazils"], .g, nil, n(680, 14, 3, 68, 8), (150, 2.00)),
        nut("macadamias", "Macadamia nuts", ["macadamia nuts", "macadamias", "macadamia", "macadamia nut"], .g, nil, n(750, 8, 5, 76, 8), (100, 2.50)),
        nut("pine-nuts", "Pine nuts", ["pine nuts", "pine kernels", "pinenuts", "pignoli", "toasted pine nuts"], .g, nil, n(690, 14, 4, 69, 1.9), (100, 3.00)),
        nut("flaked-almonds", "Flaked almonds", ["flaked almonds", "sliced almonds", "toasted flaked almonds", "almond flakes", "slivered almonds", "blanched almonds"], .g, nil, n(610, 21, 6, 55, 12), (100, 1.50)).dense(0.35),
        nut("chestnuts", "Cooked chestnuts", ["chestnuts", "cooked chestnuts", "vacuum packed chestnuts", "roasted chestnuts", "chestnut puree", "chestnut purée"], .g, 10, n(170, 2, 36, 1.5, 4), (180, 2.00)),
        nut("pumpkin-seeds", "Pumpkin seeds", ["pumpkin seeds", "pepitas", "pumpkin seed", "toasted pumpkin seeds"], .g, nil, n(570, 30, 11, 46, 6), (150, 1.50)),
        nut("sunflower-seeds", "Sunflower seeds", ["sunflower seeds", "sunflower seed"], .g, nil, n(585, 21, 20, 51, 9), (200, 1.25)),
        nut("sesame-seeds", "Sesame seeds", ["sesame seeds", "toasted sesame seeds", "white sesame seeds", "sesame seed", "black sesame seeds", "sesame", "black sesame"], .g, nil, n(575, 18, 23, 50, 8), (100, 1.10)),
        nut("linseed", "Linseed (flaxseed)", ["linseed", "flaxseed", "flax seeds", "ground flaxseed", "golden linseed", "milled flaxseed", "ground linseed", "flax", "flax seed", "milled linseed"], .g, nil, n(530, 18, 29, 42, 27), (250, 2.00)),
        nut("hemp-seeds", "Hemp seeds", ["hemp seeds", "hulled hemp seeds", "hemp hearts", "shelled hemp seeds"], .g, nil, n(570, 32, 5, 48, 4), (175, 3.50)),
        nut("poppy-seeds", "Poppy seeds", ["poppy seeds", "poppy seed", "blue poppy seeds"], .g, nil, n(525, 18, 28, 42, 20), (100, 1.25)),
        nut("tahini", "Tahini", ["tahini", "tahina", "sesame paste", "light tahini", "tahini paste", "dark tahini"], .g, nil, n(640, 19, 10, 58, 9), (300, 2.75)).sort(.condiments).keeps(365).dense(1.05),
        nut("almond-butter", "Almond butter", ["almond butter", "cashew butter", "hazelnut butter", "mixed nut butter", "pistachio butter"], .g, nil, n(615, 21, 9, 55, 10), (170, 3.50)).sort(.condiments).keeps(365).dense(1.05),
        nut("raisins", "Raisins and sultanas", ["raisins", "sultanas", "currants", "golden raisins", "mixed dried fruit", "dried fruit mix", "raisin", "sultana", "dried mixed fruit"], .g, nil, n(300, 2.7, 70, 0.5, 4), (500, 1.75)),
        nut("dried-apricots", "Dried apricots", ["dried apricots", "dried apricot", "soft dried apricots", "ready to eat apricots", "ready to eat dried apricots"], .g, 8, n(180, 3.4, 40, 0.6, 6.3), (250, 1.75)),
        nut("dried-cranberries", "Dried cranberries", ["dried cranberries", "craisins", "cranberries", "dried cherries", "dried blueberries", "goji berries", "dried sour cherries"], .g, nil, n(330, 0.2, 80, 1.4, 5.7), (200, 2.00)),
        nut("dried-figs", "Dried figs", ["dried figs", "dried fig", "soft dried figs"], .g, 20, n(250, 3.3, 64, 0.9, 10), (250, 2.50)),
        nut("prunes", "Prunes", ["prunes", "prune", "dried prunes", "pitted prunes", "soft prunes"], .g, 10, n(240, 2.2, 64, 0.4, 7), (250, 1.75)),
        nut("dried-mango", "Dried mango", ["dried mango", "banana chips", "dried banana", "dried pineapple", "dried apple rings", "freeze dried strawberries", "freeze dried raspberries"], .g, nil, n(320, 2, 78, 1, 4), (100, 1.75)),
    ]

    static let pastes: [Food] = [
        sauce("miso", "Miso paste", ["miso", "miso paste", "white miso", "red miso", "brown miso", "shiro miso", "yellow miso", "sweet white miso", "white miso paste", "red miso paste"], .g, nil, n(200, 12, 26, 6, 5), (150, 2.50)).kept(.fridge).keeps(180).dense(1.15),
        sauce("gochujang", "Gochujang", ["gochujang", "gochujang paste", "korean chilli paste", "korean red pepper paste", "korean chili paste"], .g, nil, n(230, 5, 45, 2, 2), (170, 2.50)).dense(1.2),
        sauce("harissa", "Harissa paste", ["harissa", "harissa paste", "rose harissa", "rose harissa paste"], .g, nil, n(150, 2.5, 12, 10, 3), (190, 2.00)),
        sauce("chipotle-paste", "Chipotle paste", ["chipotle paste", "chipotle in adobo", "chipotles in adobo", "adobo sauce", "chipotle chilli paste", "chipotle peppers in adobo"], .g, nil, n(100, 2, 15, 3, 4), (90, 2.00)),
        sauce("sun-dried-tomato-paste", "Sun-dried tomato paste", ["sun-dried tomato paste", "sundried tomato paste", "sun dried tomato puree", "sun-dried tomato purée"], .g, nil, n(250, 4, 15, 20, 4), (190, 1.75)),
        sauce("thai-red-curry-paste", "Thai red curry paste", ["thai red curry paste", "red curry paste", "red thai curry paste", "vegan red curry paste"], .g, nil, n(120, 2.5, 13, 6, 4), (195, 1.75)),
        sauce("thai-green-curry-paste", "Thai green curry paste", ["thai green curry paste", "green curry paste", "green thai curry paste", "vegan green curry paste"], .g, nil, n(120, 2.5, 13, 6, 4), (195, 1.75)),
        sauce("massaman-paste", "Massaman curry paste", ["massaman curry paste", "massaman paste", "panang curry paste", "yellow curry paste", "penang curry paste"], .g, nil, n(150, 2.5, 15, 9, 4), (195, 1.75)),
        sauce("tikka-paste", "Tikka paste", ["tikka paste", "tikka masala paste", "tandoori paste", "tikka curry paste", "tikka spice paste"], .g, nil, n(200, 3, 12, 15, 4), (283, 2.00)),
        sauce("korma-paste", "Korma paste", ["korma paste", "korma curry paste", "mild curry paste"], .g, nil, n(220, 3, 14, 16, 4), (283, 2.00)),
        sauce("madras-paste", "Madras curry paste", ["madras paste", "madras curry paste", "balti paste", "rogan josh paste", "jalfrezi paste", "vindaloo paste", "hot curry paste", "biryani paste", "bhuna paste", "rogan josh curry paste"], .g, nil, n(200, 3, 12, 15, 4), (283, 2.00)),
        sauce("ginger-garlic-paste", "Ginger and garlic paste", ["ginger garlic paste", "garlic ginger paste", "ginger and garlic paste", "garlic and ginger paste"], .g, nil, n(110, 3, 22, 1, 2), (200, 1.50)).kept(.fridge),
        sauce("chilli-paste", "Chilli paste", ["chilli paste", "chili paste", "sambal oelek", "sambal", "red chilli paste", "chilli puree", "lazy chillies"], .g, nil, n(60, 2, 9, 1.5, 3), (90, 1.50)).kept(.fridge),
        sauce("lemongrass-paste", "Lemongrass paste", ["lemongrass paste", "lemon grass paste", "lazy lemongrass"], .g, nil, n(100, 1.5, 20, 2, 2), (95, 1.75)).kept(.fridge),
        sauce("black-bean-sauce", "Black bean sauce", ["black bean sauce", "fermented black beans", "black bean paste", "douchi"], .g, nil, n(120, 4, 18, 3, 2), (195, 1.50)),
        sauce("doubanjiang", "Chilli bean paste", ["doubanjiang", "chilli bean paste", "chili bean paste", "toban djan", "spicy bean paste", "broad bean paste", "spicy broad bean paste"], .g, nil, n(180, 8, 15, 9, 4), (200, 2.50)),
        sauce("tapenade", "Tapenade", ["tapenade", "olive tapenade", "black olive tapenade", "green olive tapenade", "olive paste"], .g, nil, n(300, 2, 5, 30, 3), (190, 2.25)),
        sauce("marmite", "Yeast extract", ["marmite", "yeast extract", "vegemite", "promite"], .g, nil, n(260, 40, 24, 0.4, 3), (125, 2.75)).dense(1.3),
        sauce("pesto-other", "Red or vegan pesto", ["red pesto", "sun dried tomato pesto", "vegan pesto", "wild garlic pesto", "pesto rosso", "vegetarian pesto"], .g, nil, n(400, 4, 8, 40, 2), (190, 1.75)).kept(.fridge).dense(1.05),
    ]

    static let sauces: [Food] = [
        sauce("pasta-sauce", "Pasta sauce", ["pasta sauce", "tomato pasta sauce", "arrabbiata sauce", "marinara sauce", "tomato and basil sauce", "marinara", "jar of pasta sauce", "napoletana sauce", "pizza sauce"], .g, nil, n(50, 1.5, 8, 1.2, 1.5), (500, 1.50)).sort(.tins).dense(1.05),
        sauce("curry-sauce", "Curry sauce (jar)", ["curry sauce", "tikka masala sauce", "korma sauce", "jalfrezi sauce", "balti sauce", "jar of curry sauce", "katsu curry sauce", "katsu sauce", "butter chicken sauce", "rogan josh sauce"], .g, nil, n(100, 1.5, 9, 6, 1.5), (500, 1.75)).sort(.tins).dense(1.05),
        sauce("stir-fry-sauce", "Stir fry sauce", ["stir fry sauce", "sweet and sour sauce", "sweet & sour sauce", "chow mein sauce", "szechuan sauce", "yellow bean sauce", "stir-fry sauce", "satay sauce", "peanut sauce"], .ml, nil, n(130, 1.5, 28, 1.5, 0.5), (150, 1.25)).dense(1.15),
        sauce("hoisin", "Hoisin sauce", ["hoisin sauce", "hoisin", "plum sauce", "chinese plum sauce"], .ml, nil, n(220, 3, 44, 3.5, 2), (195, 1.50)).dense(1.2),
        sauce("teriyaki", "Teriyaki sauce", ["teriyaki sauce", "teriyaki", "teriyaki marinade", "teriyaki glaze"], .ml, nil, n(90, 5, 16, 0), (250, 2.00)).dense(1.15),
        sauce("veggie-oyster-sauce", "Vegetarian oyster sauce", ["vegetarian oyster sauce", "oyster sauce", "mushroom stir fry sauce", "vegan oyster sauce", "mushroom oyster sauce", "vegetarian stir fry sauce"], .ml, nil, n(110, 2, 25, 0.2), (150, 2.00)).dense(1.2),
        sauce("kecap-manis", "Kecap manis", ["kecap manis", "ketjap manis", "sweet soy sauce", "indonesian sweet soy sauce", "sweet soy"], .ml, nil, n(270, 2, 65, 0), (250, 2.50)).dense(1.25),
        sauce("tamari", "Tamari", ["tamari", "gluten free soy sauce", "tamari soy sauce", "gluten-free tamari", "coconut aminos", "liquid aminos"], .ml, nil, n(60, 10, 5, 0.1), (250, 3.00)).dense(1.15),
        sauce("ponzu", "Ponzu", ["ponzu", "ponzu sauce", "yuzu juice", "yuzu"], .ml, nil, n(50, 3, 8, 0), (250, 3.50)).dense(1.1),
        sauce("chilli-oil", "Chilli oil", ["chilli oil", "chili oil", "chilli crisp", "crispy chilli oil", "lao gan ma", "chili crisp", "crispy chilli in oil", "chilli crunch", "crispy chilli"], .ml, nil, n(700, 2, 6, 75, 1), (200, 2.75)).dense(0.95),
        sauce("chilli-jam", "Chilli jam", ["chilli jam", "chili jam", "red pepper jelly", "chilli jelly", "hot pepper jelly", "tomato chilli jam"], .g, nil, n(260, 0.5, 63, 0.3, 0.5), (190, 2.00)).dense(1.3),
        sauce("mango-chutney", "Mango chutney", ["mango chutney", "sweet mango chutney", "mango chutney jar"], .g, nil, n(230, 0.5, 56, 0.2, 1), (340, 1.50)).dense(1.3),
        sauce("chutney", "Chutney and pickle", ["chutney", "onion chutney", "caramelised onion chutney", "red onion chutney", "tomato chutney", "branston pickle", "branston", "ploughman's pickle", "sweet pickle", "piccalilli", "onion marmalade"], .g, nil, n(150, 1, 35, 0.3, 1.5), (360, 1.50)).dense(1.25),
        sauce("lime-pickle", "Lime pickle", ["lime pickle", "mixed pickle", "indian pickle", "mango pickle", "achar", "chilli pickle"], .g, nil, n(180, 2, 8, 15, 2), (190, 1.75)),
        sauce("cranberry-sauce", "Cranberry sauce", ["cranberry sauce", "cranberry jelly", "redcurrant jelly", "red currant jelly", "cranberry relish"], .g, nil, n(160, 0.1, 40, 0.1, 1), (200, 1.25)).dense(1.3),
        sauce("mint-sauce", "Mint sauce", ["mint sauce", "mint jelly"], .ml, nil, n(100, 1, 23, 0.1, 1), (165, 1.00)),
        sauce("horseradish-sauce", "Horseradish sauce", ["horseradish sauce", "creamed horseradish", "hot horseradish", "wasabi", "wasabi paste"], .g, nil, n(150, 2, 15, 9, 2), (185, 1.25)),
        sauce("apple-sauce", "Apple sauce", ["apple sauce", "applesauce", "bramley apple sauce", "unsweetened apple sauce", "apple puree", "stewed apple", "apple purée"], .g, nil, n(70, 0.2, 17, 0.1, 1.2), (280, 1.25)).dense(1.05),
        sauce("bbq-sauce", "BBQ sauce", ["bbq sauce", "barbecue sauce", "smoky bbq sauce", "bbq", "hickory bbq sauce", "sticky bbq sauce"], .ml, nil, n(150, 1, 35, 0.3), (480, 1.75)).dense(1.2),
        sauce("brown-sauce", "Brown sauce", ["brown sauce", "hp sauce", "hp", "daddies sauce"], .ml, nil, n(120, 1, 27, 0.1), (450, 1.75)).dense(1.15),
        sauce("salad-cream", "Salad cream", ["salad cream", "caesar dressing", "ranch dressing", "honey mustard dressing", "french dressing", "salad dressing", "vinaigrette", "blue cheese dressing", "thousand island dressing"], .ml, nil, n(330, 1.5, 15, 30), (425, 1.75)).dense(1.0),
        sauce("aioli", "Aioli", ["aioli", "garlic aioli", "garlic mayonnaise", "chipotle mayo", "sriracha mayo", "spicy mayo", "kewpie mayo", "japanese mayo", "kewpie"], .ml, nil, n(600, 1, 4, 65), (240, 2.00)).dense(0.95),
        sauce("vegan-mayo", "Vegan mayonnaise", ["vegan mayo", "vegan mayonnaise", "egg free mayo", "plant based mayo", "vegan mayonaise", "dairy free mayo"], .ml, nil, n(500, 0.5, 4, 54), (270, 2.00)).dense(0.95),
        sauce("tartare-sauce", "Tartare sauce", ["tartare sauce", "tartar sauce", "seafood sauce", "marie rose sauce", "burger sauce", "big mac sauce"], .ml, nil, n(300, 1, 15, 26), (300, 1.50)).dense(1.0),
        sauce("salsa", "Salsa", ["salsa", "tomato salsa", "fresh salsa", "salsa dip", "pico de gallo", "salsa verde", "chunky salsa", "tomato salsa dip"], .g, nil, n(35, 1.5, 6, 0.2, 1.5), (300, 1.50)).kept(.fridge).keeps(14).dense(1.05),
        sauce("guacamole", "Guacamole", ["guacamole", "guac", "avocado dip"], .g, nil, n(150, 1.7, 7, 13, 5), (150, 1.50)).kept(.fridge).keeps(5).dense(1.0),
        sauce("dips", "Dips", ["baba ganoush", "baba ghanoush", "moutabal", "sour cream and chive dip", "tzatziki dip", "beetroot houmous", "red pepper dip", "muhammara"], .g, nil, n(200, 4, 8, 17, 3), (200, 1.75)).kept(.fridge).keeps(7).dense(1.05),
        sauce("liquid-smoke", "Liquid smoke", ["liquid smoke", "smoke flavouring", "hickory liquid smoke"], .ml, nil, n(10, 0, 2, 0), (100, 4.00)).staple,
        sauce("gravy", "Gravy granules", ["gravy granules", "gravy", "vegetable gravy granules", "vegetarian gravy", "onion gravy granules", "gravy powder", "bisto"], .g, nil, n(430, 3, 63, 19, 1), (170, 1.50)).dense(0.6),
        sauce("veg-stock", "Vegetable stock (liquid)", ["vegetable stock", "veg stock", "stock", "vegetable broth", "veggie stock", "hot vegetable stock", "low salt vegetable stock", "fresh vegetable stock", "mushroom stock", "vegan chicken stock", "no chicken stock", "broth", "vegan stock", "hot stock"], .ml, nil, n(5, 0.2, 0.8, 0.1), (500, 1.50)).staple.dense(1.0),
        sauce("bouillon-powder", "Bouillon powder", ["bouillon powder", "vegetable bouillon powder", "marigold bouillon", "stock powder", "marigold", "vegetable stock powder", "vegan bouillon powder"], .g, nil, n(250, 10, 30, 10), (150, 2.75)).staple.dense(0.6),
        sauce("stock-pot", "Vegetable stock pots", ["vegetable stock pot", "veg stock pot", "stock pots", "knorr stock pot", "vegetable stock pots", "mushroom stock pot"], .piece, 28, n(100, 1, 7, 7), (4, 1.50)).staple,
    ]

    static let vinegarsAndOils: [Food] = [
        sauce("balsamic", "Balsamic vinegar", ["balsamic vinegar", "balsamic", "balsamic vinegar of modena", "aged balsamic", "white balsamic", "white balsamic vinegar"], .ml, nil, n(88, 0.5, 17, 0), (250, 1.50)).keeps(700).dense(1.06),
        sauce("balsamic-glaze", "Balsamic glaze", ["balsamic glaze", "balsamic reduction", "balsamic drizzle"], .ml, nil, n(250, 0.5, 58, 0), (250, 2.00)).keeps(700).dense(1.3),
        sauce("red-wine-vinegar", "Red wine vinegar", ["red wine vinegar"], .ml, nil, n(19, 0, 0.3, 0), (350, 1.00)).keeps(700).dense(1.01).staple,
        sauce("white-wine-vinegar", "White wine vinegar", ["white wine vinegar", "white vinegar", "distilled vinegar", "spirit vinegar", "distilled white vinegar", "champagne vinegar"], .ml, nil, n(19, 0, 0.3, 0), (350, 0.85)).keeps(700).dense(1.01).staple,
        sauce("cider-vinegar", "Cider vinegar", ["apple cider vinegar", "cider vinegar", "acv", "raw apple cider vinegar"], .ml, nil, n(21, 0, 0.9, 0), (500, 1.50)).keeps(700).dense(1.01),
        sauce("rice-vinegar", "Rice vinegar", ["rice vinegar", "rice wine vinegar", "seasoned rice vinegar", "sushi vinegar", "black vinegar", "chinkiang vinegar"], .ml, nil, n(20, 0, 0.5, 0), (150, 1.75)).keeps(700).dense(1.01),
        sauce("sherry-vinegar", "Sherry vinegar", ["sherry vinegar", "malt vinegar", "brown vinegar", "chip shop vinegar"], .ml, nil, n(20, 0, 0.5, 0), (250, 1.50)).keeps(700).dense(1.01),
        sauce("pomegranate-molasses", "Pomegranate molasses", ["pomegranate molasses", "pomegranate syrup", "pomegranate concentrate"], .ml, nil, n(260, 0, 65, 0), (250, 2.50)).keeps(700).dense(1.3),
        sauce("vegetable-oil", "Vegetable oil", ["vegetable oil", "sunflower oil", "rapeseed oil", "groundnut oil", "peanut oil", "canola oil", "corn oil", "neutral oil", "frying oil", "cold pressed rapeseed oil"], .ml, nil, n(884, 0, 0, 100), (1000, 1.75)).keeps(700).dense(0.92).staple,
        sauce("coconut-oil", "Coconut oil", ["coconut oil", "virgin coconut oil", "odourless coconut oil", "melted coconut oil", "extra virgin coconut oil"], .g, nil, n(862, 0, 0, 99), (500, 4.00)).keeps(700).dense(0.92),
        sauce("avocado-oil", "Avocado oil", ["avocado oil", "walnut oil", "hazelnut oil", "flaxseed oil", "linseed oil"], .ml, nil, n(884, 0, 0, 100), (250, 4.00)).keeps(365).dense(0.92),
        sauce("truffle-oil", "Truffle oil", ["truffle oil", "white truffle oil", "black truffle oil", "truffle", "truffle paste", "truffle salt"], .ml, nil, n(884, 0, 0, 100), (100, 4.00)).keeps(365).dense(0.92),
        sauce("garlic-oil", "Garlic or chilli infused oil", ["garlic oil", "garlic infused oil", "chilli infused oil", "infused olive oil", "basil oil", "lemon oil"], .ml, nil, n(884, 0, 0, 100), (250, 2.75)).keeps(365).dense(0.92),
    ]

    static let jars: [Food] = [
        jar("plum-tomatoes", "Whole plum tomatoes (tin)", ["plum tomatoes tin", "whole plum tomatoes", "tinned plum tomatoes", "whole peeled tomatoes", "peeled plum tomatoes", "san marzano tomatoes", "tin of plum tomatoes", "canned whole tomatoes", "tinned whole tomatoes"], .g, nil, n(22, 1.1, 3.8, 0.2, 0.9), (400, 0.65)).tin(400),
        jar("tinned-cherry-tomatoes", "Tinned cherry tomatoes", ["tinned cherry tomatoes", "canned cherry tomatoes", "tin of cherry tomatoes", "cherry tomatoes in juice", "cherry tomatoes tin"], .g, nil, n(22, 1.1, 3.8, 0.2, 0.9), (400, 1.00)).tin(400),
        jar("coconut-cream", "Coconut cream", ["coconut cream", "creamed coconut", "coconut cream tin", "block of creamed coconut", "tin of coconut cream"], .ml, nil, n(330, 3.3, 6.6, 34, 0), (400, 1.75)).tin(400),
        jar("artichoke-hearts", "Artichoke hearts", ["artichoke hearts", "artichokes", "artichoke", "marinated artichokes", "chargrilled artichokes", "artichoke heart", "jarred artichokes"], .g, 30, n(47, 3.3, 10.5, 0.2, 5.4), (280, 2.50)),
        jar("sun-dried-tomatoes", "Sun-dried tomatoes", ["sun-dried tomatoes", "sundried tomatoes", "sun dried tomatoes", "sunblush tomatoes", "semi-dried tomatoes", "sun-dried tomato", "sunblush tomato"], .g, 6, n(215, 4, 14, 15, 5), (280, 2.25)).dense(0.6),
        jar("roasted-peppers", "Roasted red peppers", ["roasted red peppers", "roasted peppers", "jarred peppers", "chargrilled peppers", "roasted red pepper", "piquillo peppers", "jarred roasted peppers", "flame roasted peppers"], .g, 40, n(30, 1, 5, 0.5, 1.5), (290, 1.75)),
        jar("black-olives", "Black olives", ["black olives", "olives", "pitted olives", "sliced olives", "kalamata olives", "kalamata", "pitted black olives", "olive"], .g, 4, n(150, 1, 3, 15, 3), (160, 1.50)).dense(0.6),
        jar("green-olives", "Green olives", ["green olives", "manzanilla olives", "nocellara olives", "castelvetrano olives", "gordal olives", "pitted green olives", "stuffed olives"], .g, 4, n(145, 1, 3.8, 15, 3.3), (160, 1.50)).dense(0.6),
        jar("capers", "Capers", ["capers", "caper", "baby capers", "capers in brine", "nonpareille capers", "caper berries"], .g, nil, n(23, 2.4, 4.9, 0.9, 3.2), (60, 1.25)).dense(0.6),
        jar("gherkins", "Gherkins", ["gherkins", "gherkin", "pickles", "dill pickles", "cornichons", "cornichon", "pickled cucumbers", "pickled gherkins", "dill pickle"], .piece, 30, n(14, 0.5, 2, 0.2, 1), (10, 1.25)),
        jar("pickled-jalapenos", "Pickled jalapeños", ["pickled jalapenos", "pickled jalapeños", "jalapeno slices", "sliced jalapenos", "jalapenos in brine", "jarred jalapenos", "green jalapeno slices", "jalapeño slices"], .g, nil, n(27, 0.9, 4, 0.9, 2.6), (150, 1.50)).dense(0.6),
        jar("pickled-onions", "Pickled red onions", ["pickled red onions", "pickled onions", "pickled shallots", "quick pickled onions", "silverskin onions", "pickled red onion"], .g, nil, n(40, 0.8, 9, 0.1, 1.2), (200, 1.25)),
        jar("palm-hearts", "Hearts of palm", ["hearts of palm", "palm hearts", "heart of palm"], .g, nil, n(28, 2.5, 4.6, 0.6, 2.4), (220, 2.00)).tin(220),
        jar("water-chestnuts", "Water chestnuts", ["water chestnuts", "water chestnut", "sliced water chestnuts"], .g, nil, n(30, 1, 7, 0.1, 1.6), (140, 1.00)).tin(140),
        jar("bamboo-shoots", "Bamboo shoots", ["bamboo shoots", "sliced bamboo shoots", "bamboo shoot"], .g, nil, n(20, 1.5, 3, 0.3, 2), (140, 1.00)).tin(140),
        jar("sauerkraut", "Sauerkraut", ["sauerkraut", "pickled cabbage", "red sauerkraut"], .g, nil, n(19, 0.9, 4.3, 0.1, 2.9), (500, 2.00)).dense(0.7),
        jar("kimchi", "Kimchi", ["kimchi", "vegan kimchi", "kimchee", "kimchi juice"], .g, nil, n(23, 1.6, 4, 0.5, 1.6), (300, 3.00)).kept(.fridge).keeps(60).dense(0.7),
        jar("tinned-veg", "Tinned vegetables", ["tinned potatoes", "tinned carrots", "tinned peas", "mushy peas", "processed peas", "tinned mushrooms", "tinned spinach", "tinned sweet potato"], .g, nil, n(60, 3, 10, 0.5, 3), (300, 0.60)).tin(300),
        jar("soup", "Soup", ["soup", "tomato soup", "tinned soup", "cream of mushroom soup", "condensed soup", "lentil soup", "vegetable soup"], .g, nil, n(50, 1.5, 7, 2, 1), (400, 1.00)).tin(400).dense(1.03),
    ]

    static let frozenFoods: [Food] = [
        frozen("frozen-spinach", "Frozen spinach", ["frozen spinach", "spinach portions", "frozen chopped spinach", "frozen leaf spinach", "frozen spinach balls"], .g, 25, n(25, 3, 1.5, 0.5, 2.5), (900, 1.50)).group("leafy"),
        frozen("frozen-chips", "Oven chips", ["oven chips", "frozen chips", "chips", "french fries", "fries", "potato wedges", "wedges", "sweet potato fries", "frozen fries", "skinny fries", "chunky chips"], .g, nil, n(160, 2.5, 25, 5, 2.5), (1500, 2.25)).dense(0.35),
        frozen("hash-browns", "Hash browns", ["hash browns", "hash brown", "potato rosti", "rosti", "potato waffles", "waffles potato"], .piece, 45, n(180, 2, 22, 9, 2), (15, 1.50)),
        frozen("frozen-peppers", "Frozen sliced peppers", ["frozen peppers", "frozen sliced peppers", "frozen mixed peppers", "frozen pepper strips"], .g, nil, n(25, 1, 4.5, 0.3, 2), (500, 1.25)),
        frozen("frozen-onions", "Frozen chopped onions", ["frozen chopped onions", "frozen onions", "frozen diced onions", "frozen sliced onions", "frozen onion"], .g, nil, n(30, 1, 6, 0.1, 1.5), (500, 1.00)),
        frozen("frozen-herbs", "Frozen herbs", ["frozen herbs", "frozen chopped herbs", "frozen coriander", "frozen basil", "frozen parsley", "frozen mixed herbs", "frozen chillies"], .g, nil, n(30, 3, 3, 0.5, 3), (25, 1.25)),
        frozen("frozen-sweet-potato", "Frozen sweet potato", ["frozen sweet potato", "frozen butternut squash", "frozen squash", "frozen roast vegetables", "frozen roasting vegetables", "frozen root vegetables"], .g, nil, n(70, 1.5, 15, 0.3, 3), (500, 1.50)),
        frozen("frozen-cauliflower-rice", "Frozen cauliflower rice", ["frozen cauliflower rice", "frozen broccoli rice", "frozen riced cauliflower", "frozen cauliflower", "frozen broccoli"], .g, nil, n(25, 2, 4, 0.3, 2), (500, 1.50)).group("greenveg"),
        frozen("frozen-avocado", "Frozen avocado", ["frozen avocado", "frozen avocado chunks", "frozen avocado halves"], .g, nil, n(160, 2, 9, 15, 6.7), (500, 2.75)),
        frozen("yorkshire-puddings", "Yorkshire puddings", ["yorkshire puddings", "yorkshire pudding", "yorkies", "frozen yorkshire puddings"], .piece, 20, n(250, 8, 32, 10, 1.5), (12, 1.25)),
        frozen("frozen-pastry", "Frozen pastry", ["frozen puff pastry", "frozen shortcrust pastry", "frozen filo pastry", "frozen pastry"], .g, nil, n(420, 6, 40, 26, 1.5), (500, 1.50)),
    ]

    static let drinksAndOther: [Food] = [
        drink("orange-juice", "Orange juice", ["orange juice", "fresh orange juice", "freshly squeezed orange juice", "smooth orange juice"], .ml, nil, n(45, 0.7, 10, 0.2, 0.2), (1000, 1.75)).kept(.fridge).keeps(7).dense(1.04),
        drink("apple-juice", "Apple juice", ["apple juice", "cloudy apple juice", "pressed apple juice", "cranberry juice", "pineapple juice", "pomegranate juice", "grape juice", "tomato juice"], .ml, nil, n(46, 0.1, 11, 0.1, 0), (1000, 1.25)).kept(.fridge).keeps(7).dense(1.04),
        drink("coconut-water", "Coconut water", ["coconut water"], .ml, nil, n(19, 0.7, 3.7, 0.2), (1000, 2.50)).dense(1.02),
        drink("soda-water", "Soda water", ["soda water", "sparkling water", "club soda", "fizzy water", "tonic water", "lemonade", "ginger beer", "ginger ale", "cola"], .ml, nil, n(0, 0, 0, 0), (1000, 0.60)),
        drink("red-wine", "Red wine", ["red wine", "dry red wine", "red wine for cooking", "cooking red wine", "glass of red wine"], .ml, nil, n(85, 0.1, 2.6, 0), (750, 6.00)).dense(0.99),
        drink("white-wine", "White wine", ["white wine", "dry white wine", "white wine for cooking", "cooking white wine", "vermouth", "dry vermouth", "glass of white wine", "prosecco", "rose wine"], .ml, nil, n(82, 0.1, 2.6, 0), (750, 6.00)).dense(0.99),
        drink("sherry", "Sherry", ["sherry", "dry sherry", "fino sherry", "marsala", "marsala wine", "port", "madeira", "cream sherry", "ruby port"], .ml, nil, n(120, 0.2, 5, 0), (700, 6.00)),
        drink("shaoxing", "Shaoxing wine", ["shaoxing wine", "shaoxing rice wine", "chinese cooking wine", "shao xing", "sake", "cooking sake", "shaoxing", "chinese rice wine"], .ml, nil, n(130, 1.5, 4, 0), (150, 2.50)),
        drink("mirin", "Mirin", ["mirin", "rice wine", "sweet rice wine", "aji mirin", "mirin seasoning", "mirin rice wine"], .ml, nil, n(240, 0.2, 43, 0), (150, 2.50)).dense(1.15),
        drink("beer", "Beer", ["beer", "ale", "stout", "lager", "guinness", "dark ale", "cider", "pale ale", "porter", "bottle of beer"], .ml, nil, n(43, 0.5, 3.6, 0), (500, 1.75)),
        drink("spirits", "Spirits and liqueurs", ["brandy", "rum", "dark rum", "cognac", "whisky", "whiskey", "bourbon", "vodka", "amaretto", "kahlua", "coffee liqueur", "grand marnier", "cointreau", "triple sec", "baileys", "gin", "tequila"], .ml, nil, n(250, 0, 10, 0), (700, 18.00)).dense(0.95),
        drink("instant-coffee", "Instant coffee", ["instant coffee", "coffee granules", "espresso powder", "instant espresso", "instant espresso powder", "ground coffee", "coffee beans"], .g, nil, n(350, 12, 75, 0.5, 30), (100, 3.00)).dense(0.3),
        drink("coffee", "Coffee (brewed)", ["coffee", "espresso", "strong coffee", "brewed coffee", "cold brew", "shot of espresso", "black coffee", "cold coffee", "espresso shot"], .ml, nil, n(2, 0.1, 0, 0), (1000, 2.00)).kept(.fridge).keeps(3),
        drink("matcha", "Matcha", ["matcha", "matcha powder", "matcha green tea powder", "green tea powder"], .g, nil, n(320, 30, 40, 5, 38), (30, 6.00)).dense(0.4),
        drink("tea", "Tea bags", ["tea bags", "tea bag", "black tea", "green tea", "earl grey", "chai tea bags", "builders tea", "chai", "rooibos", "peppermint tea", "tea"], .piece, 3, n(0, 0, 0, 0), (80, 2.50)),
        drink("hot-chocolate", "Hot chocolate powder", ["hot chocolate powder", "hot chocolate", "drinking chocolate", "cocoa mix", "malted milk powder", "horlicks", "ovaltine"], .g, nil, n(380, 7, 70, 7, 6), (400, 2.50)).dense(0.5),
        drink("crisps", "Crisps", ["crisps", "potato chips", "ready salted crisps", "kettle chips", "pringles", "crisp", "lentil crisps", "veggie crisps"], .g, nil, n(530, 6, 53, 32, 4), (150, 1.50)).sort(.snacks).dense(0.1),
        drink("tortilla-chips", "Tortilla chips", ["tortilla chips", "nachos", "corn chips", "doritos", "nacho chips", "tortilla crisps"], .g, nil, n(490, 7, 62, 23, 5), (200, 1.25)).sort(.snacks).dense(0.1),
        drink("pretzels", "Pretzels", ["pretzels", "pretzel", "breadsticks", "grissini", "mini breadsticks"], .g, nil, n(390, 10, 78, 3.5, 3), (150, 1.25)).sort(.snacks).dense(0.2),
        drink("cereal-bars", "Cereal bars", ["cereal bars", "granola bars", "flapjack", "flapjacks", "protein bars", "protein bar", "cereal bar", "nakd bars"], .piece, 35, n(420, 8, 60, 15, 5), (5, 2.00)).sort(.snacks),
    ]
}

extension IngredientCatalogue {
    /// Real densities for foods in the original list, so "1 cup of oats" becomes a sensible weight rather than
    /// 240 g. A food whose gramsPerMl is still exactly 1 has no known density, and cups of it are left alone.
    static let densities: [String: Double] = [
        "rice": 0.8, "brown-rice": 0.8, "oats": 0.4, "couscous": 0.75, "quinoa": 0.75, "red-lentils": 0.8, "granola": 0.45,
        "pasta": 0.45, "spaghetti": 0.45, "egg-noodles": 0.45, "rice-noodles": 0.45,
        "cheddar": 0.45, "parmesan": 0.4, "mozzarella": 0.45, "feta": 0.6, "halloumi": 0.6, "cottage-cheese": 1.03,
        "cream-cheese": 1.02, "butter": 0.96, "greek-yoghurt": 1.05, "natural-yoghurt": 1.03, "hummus": 1.05,
        "passata": 1.03, "chopped-tomatoes": 1.02, "baked-beans": 1.05, "chickpeas": 0.65, "black-beans": 0.7,
        "kidney-beans": 0.7, "sweetcorn": 0.65, "peas": 0.6, "mixed-veg": 0.55, "spinach": 0.13, "salad-leaves": 0.1,
        "blueberries": 0.6, "strawberries": 0.6, "frozen-berries": 0.6, "mushrooms": 0.3, "cherry-tomatoes": 0.6,
        "broccoli": 0.4, "cauliflower": 0.45, "carrot": 0.45, "green-beans": 0.45, "courgette": 0.5, "potatoes": 0.65,
        "sweet-potato": 0.6, "coriander": 0.07, "basil": 0.1, "parsley": 0.25, "ginger": 0.9, "tofu": 0.6,
        "microwave-rice": 0.75, "prawns": 0.6, "chicken-breast": 0.6, "beef-mince": 0.9, "turkey-mince": 0.9,
    ]

    /// Drinks with alcohol in, whose calories don't come from protein, carbs and fat.
    static let alcoholic: Set<String> = ["red-wine", "white-wine", "sherry", "shaoxing", "spirits", "beer"]

    /// Merges the catalogue into the original food list. An alias the catalogue now has its own entry for is taken off
    /// the original food (so "kale" no longer means spinach, "cumin" no longer means "dried herbs & spices").
    static func merged(with base: [Food]) -> [Food] {
        let claimed = Set(all.flatMap { [$0.name] + $0.aliases }.map(aliasKey))
        let trimmed = base.map { food -> Food in
            var f = food
            f.aliases = f.aliases.filter { !claimed.contains(aliasKey($0)) }
            if let d = densities[f.id] { f.gramsPerMl = d }
            return f
        }
        return trimmed + all
    }

    static func aliasKey(_ s: String) -> String { FoodMatcher.tokens(s).joined(separator: " ") }

    /// How each unit is described in the ingredient list in Settings.
    public static func unitLabel(_ food: Food) -> String {
        switch food.unit {
        case .g: return "grams"
        case .ml: return "ml"
        case .piece: return UnitStandard.cloveFoods.contains(food.id) ? "cloves" : "items"
        }
    }
}
