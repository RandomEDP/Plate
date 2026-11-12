# Plate

An iPhone app for what's in your fridge and cupboards, what you can cook from it, your meal plan and macros, and the
shopping list that fills the gaps.

## What it does

- **Kitchen:** everything in the fridge, freezer and cupboards, with use-by dates. Add things by typing, by pasting a
  list, or by scanning a barcode (looked up on Open Food Facts). Cooking a recipe takes what it used out of the kitchen
  (soonest use-by first), so Plate knows what's running low before the next shop.
- **Recipes:** about 40 built in, plus your own. Each recipe shows what you have in, what's missing, macros per
  portion and portions scaled for however many people.
- **Import from Instagram and TikTok:** paste a Reel or TikTok link (or the caption itself), or tap Share → Save to Plate
  straight from the video. Plate reads the recipe from the caption: ingredients, method, servings, and any macros the
  creator gave. Recipes → Import many takes a whole list of links (or several captions split by `---`) at once,
  skipping any you've already saved.
- **Ideas:** what you can make now, what you nearly can, and variations that swap a missing ingredient for one you have.
  With AI on, brand-new dishes from what's in your kitchen.
- **Plan:** pick how many breakfasts, lunches, dinners and snacks a week, how many different recipes for each, and how
  many people. Plate picks recipes that use what you've got (expiring food first), share ingredients, and batch-cook
  well. Meal prep shows what to cook once for several days. Lock a meal to keep it when you re-plan.
- **Shop:** build a list from the plan or by picking meals. Ingredients are combined across meals, what's already in
  the kitchen is taken off, and each item is bought in the packs that cost least for what you need at Sainsbury's or
  Costco (bulk packs when they really save, with a penalty for food that would go off). Ticked items go straight into
  the kitchen with "Put the shopping away". Prices are rough guides.
- **Today:** calories and protein, carbs and fat against your targets, today's planned meals, what's about to go off,
  and a quick log of what you ate.
- **Home:** a dashboard for the flat, made for an iPad on the wall, and yours to restyle.
  - *Tiles:* HomeKit lights (with colour, warmth and brightness), plugs, locks, blinds, thermostats, whole rooms, your
    own groups, scenes, cameras, climate sensors, low batteries and "all lights off"; the weather, a week's forecast and
    sunrise/sunset (Apple Weather); pinned Apple Music albums, playlists and stations; kitchen timers that speak when
    they finish; chores with whose turn it is; bin days; a guest Wi-Fi code to scan; countdowns, world clocks, the
    calendar, photo frames, notes, headings; live train departures from any station (choose the direction and
    operators; fast trains are marked; needs a free National Rail key from raildata.org.uk); today's meals, the shopping list, food to use soon, what to cook now.
  - *Make it yours:* themes, accent and tile colours, a gradient, moving colours, a photo or the playing album behind
    the tiles, frosted or outlined tiles, corner shape, spacing, lettering and five packs of sound effects. Every tile
    can have its own name, icon and colour. Several pages to swipe between.
  - *Do things:* routines (several steps from one tap, or by themselves at a time of day or at sunset), light shows for
    colour bulbs, a spoken briefing, a tile that runs one of Apple's Shortcuts, and a box to type commands such as
    "kitchen off, lamp 30%, pasta 10 min". `plate://command?text=…` does the same from Shortcuts or Siri.
  - *Wall mode* fills the screen and keeps it on; after a few minutes with nobody touching it, it shows the cover of the
    album that's playing, or otherwise a photo album you pick, with a clock (digital, analogue, in words or flip) and
    the weather, dimmed at night. A tap, or a HomeKit motion sensor, brings the dashboard back.
  Accessories are still added and automated in Apple's Home app.

## AI

AI is optional; everything else works without it. Settings → AI:

- **Automatic (default):** Apple Intelligence on the iPhone when it's available (iPhone 15 Pro or later, iOS 26), free and
  private. Otherwise a Claude API key if one is saved, otherwise off.
- **Claude:** needs an API key from console.anthropic.com (pay as you go). A Claude.ai subscription can't be used by other
  apps. The key is kept in the iPhone's keychain and only sent to Anthropic.

## How it's built

| Path | What |
|---|---|
| `Packages/PlateCore` | All the logic, pure Swift with no iPhone frameworks, so it's tested on Linux: food database (UK, with Sainsbury's and Costco packs and prices), ingredient and caption parsing, units, the kitchen, suggestions and variations, the planner, the pack optimiser, Open Food Facts and social link reading |
| `App/` | The SwiftUI app (iOS 18+). `AppModel.swift` holds the household and saves it; `Views/` are the screens; `AI/` is Apple's on-device model and Claude |
| `Shared/` | Used by the app and the share extension: storage in the app group and fetching captions |
| `ShareExtension/` | "Save to Plate" in the share sheet |
| `project.yml` | The Xcode project, generated by XcodeGen on CI (no `.xcodeproj` is committed) |
| `.github/workflows/ios.yml` | Tests, a simulator build, and the TestFlight upload |

Data is kept on the iPhone in one file (`household.json` in the app group). Every record has an id and an `updatedAt`,
so sharing a household with other people can be added later without changing the format.

### Tests

```bash
swift test --package-path Packages/PlateCore
```

(or in Docker: `docker run --rm -v $PWD/Packages/PlateCore:/pkg -w /pkg swift:6.1-noble swift test`)

## Builds and TestFlight

Every push runs the core tests and checks the app builds for the simulator. Uploading to TestFlight is run by hand:
GitHub → Actions → iOS → Run workflow (TestFlight ticked). The build number is the run number.

### One-time Apple setup

1. **Register the app IDs.** developer.apple.com → Certificates, Identifiers & Profiles → Identifiers → + → App IDs → App:
   - `com.randomedp.plate` (the app), with **App Groups**, **HomeKit** and **WeatherKit** ticked under Capabilities, and
     **MusicKit** and **WeatherKit** ticked under App Services
   - `com.randomedp.plate.share` (the share extension), with **App Groups** ticked
2. **Register the app group.** Identifiers → + → App Groups → `group.com.randomedp.plate.share` (all lower case). Then on
   each of the two app IDs, App Groups → Configure → tick it.
3. **Create the app.** App Store Connect → Apps → + → New App: iOS, name *Plate* (or another if taken), bundle ID
   `com.randomedp.plate`, SKU `plate`.
4. **Add four repository secrets** (the same values as Gaffer's): GitHub → this repo → Settings → Secrets and variables →
   Actions → New repository secret: `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (the whole `.p8` file).
5. **Build.** Actions → iOS → Run workflow. About 10 to 15 minutes later it's in TestFlight.

Never put the `.p8` key, or any secret, in the code or in chat.
