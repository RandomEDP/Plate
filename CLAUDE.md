# CLAUDE.md: working on Plate

The handover for any Claude session in this repo. The README covers the features, the layout and the one-time Apple
setup. This file holds the rules and how things fit together.

**This repo is public.** Nothing private goes in it, this file included.

## 1. Who and what

- **Owner:** Ethan (GitHub `RandomEDP`). Also owns Gaffer (`RandomEDP/AI-Powered-Tactics`); Plate's build and
  TestFlight flow is copied from there.
- **Plate** is an iPhone app: kitchen inventory, recipes (including ones imported from Instagram Reels and TikTok
  captions), suggestions and variations from what's in stock, a weekly meal plan for several people, macros, and
  shopping lists that combine meals and pick the cheapest packs at Sainsbury's and Costco (UK). It also has a
  **home dashboard** (Home tab), built for an iPad on the wall of Ethan's flat: HomeKit controls, pinned Apple Music
  albums and Plate tiles, and a wall mode that shows photos (or the playing album's cover) when idle.
- **Ethan has no Mac.** Everything iOS is built, signed and uploaded on GitHub Actions. Don't suggest Xcode steps.

## 2. Hard rules

1. **No secrets in the repo or in chat.** Apple signing secrets live only in GitHub repository secrets
   (`APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`). If Ethan is about to paste one, stop him.
2. **Never use or store `AuthKey_CPB27TYJU9.p8`.** The build uses the `ASC_*` secrets only.
3. The Claude API key a user enters stays in the iPhone's keychain (`Keychain.claudeKey`), never in the household file.
4. Requests to outside services carry no personal details. Open Food Facts gets the user agent "Plate iOS app".

## 3. How Ethan wants the work done

- Plain, friendly British English in the app, in comments and in messages. Say exactly what went wrong and what to do.
- Lots of tests: every fix comes with one that would have caught it. Logic belongs in `PlateCore`, where it can be tested
  on Linux; the app target should stay thin.
- Short replies: what changed and what to check on his phone.

## 4. The routine

```bash
docker run --rm -v $PWD/Packages/PlateCore:/pkg -w /pkg swift:6.1-noble swift test   # or swift test --package-path Packages/PlateCore
git push                                                                            # CI: tests + simulator build
gh workflow run ios.yml -R RandomEDP/Plate --ref main -f testflight=true            # TestFlight (once the secrets are in)
```

- **Merge, then build.** When a piece of work is finished and CI is green, merge its PR yourself (no need to ask Ethan),
  then run TestFlight from `main`. Never upload from a branch: builds from different branches overtake each other in
  TestFlight and drop each other's features.
- Mount the package at `/pkg` exactly: a `.build` folder made under another path fails with "PCH was compiled with
  module cache path". Delete `Packages/PlateCore/.build` if in doubt.
- The app target (UIKit, SwiftUI, VisionKit, FoundationModels) only compiles on CI's Mac ("iOS" job). Read its log after
  pushing app changes.
- CI runs on the `xcode-27` runner image with Xcode 27.2; XcodeGen makes the project from `project.yml`.

## 5. How it fits together

- **One document per household** (`Household` in `Models.swift`), saved as JSON in the app group
  (`group.com.randomedp.plate.share`) 400 ms after a change. Every record has an `id` and `updatedAt`, and decoding uses
  `decodeIfPresent` with defaults, so old files still open and sharing/sync can be added later (Ethan wants household
  sharing eventually; keep the format sync-friendly). Small settings go in `household.extras`.
- **Food database** (`FoodDatabase.swift`): UK foods with macros per 100 g/ml, shelf life, and Sainsbury's/Costco packs
  with rough prices. Recipe ingredients are matched to it by `FoodMatcher` (aliases); unmatched ones still work but have
  no macros or packs.
- **Parsing:** `IngredientParser` (one line), `RecipeTextParser` (a whole caption: title, ingredients, method,
  servings, stated macros, hashtags). Test new caption styles in `ParsingTests.swift`. `IngredientSplit` turns a line naming
  two foods ("50g garlic and scallions") into two ingredients when a recipe is built, from Plate's parser or the AI. `UnitStandard` then puts each in the unit
  you'd count it in (garlic in cloves, onions and eggs by the piece, liquids in ml, no oz or cups), noting what the recipe
  said; weighed foods like chicken stay as written. Saved recipes were converted once (`standardiseSavedRecipeUnitsOnce`).
- **Social import:** `SocialImport` (pure) plus `Shared/CaptionFetcher.swift`: TikTok's oEmbed `title` is the caption;
  Instagram is read from the post's `/embed/captioned/` page, falling back to the `og:description` meta tag. Neither
  needs a login; a private post can't be read, and the app says to paste the caption instead.
- **Osta import:** Osta (ostarecipes.com) has no export, and its share pages are drawn by JavaScript. `App/OstaReader.swift`
  loads the page in an almost invisible `WKWebView` and passes the page's text to `OstaImport.extract` (PlateCore),
  which turns it into caption text for `RecipeTextParser`. Folder links are scrolled and their recipe links collected.
  The page layout in `OstaImportTests` is copied from what Safari showed (12 November 2026); if Osta changes it, fix
  the extractor against a new sample. `extract` gives nil unless the page is a real recipe page ("Save this recipe" or
  prep/cook times, not Osta's home page) with at least two real ingredients. The AI's tidy-up is only used when
  `AIGuard.faithful` finds its ingredients in the caption (on a blank page Apple's model invented recipes).
  `BulkImport` (Recipes → Import many) splits a big paste into links and captions. Recipes → Select → Re-import
  (`ReimportView`, `AppModel.fetchRecipe`, `Household.replaceRecipe`) reads chosen recipes again from their saved links
  and swaps them in place, keeping id and favourite.
- **Video import:** for recipes only in the video. Import → From a video (Photos or Files), or share a video to Plate
  (the extension copies it to `VideoInbox` in the app group; `AppModel.collectVideos` reads it when the app opens).
  `App/VideoReader.swift` reads on-screen text with Vision (about a frame a second) and the speech with
  `SFSpeechRecognizer` (on-device where it can); `VideoText` (PlateCore, tested) dedupes the screen lines and lays
  caption + screen + speech out for `readRecipe`. A link pasted first has its caption read too and stays with the recipe.
  Links alone can't fetch the video (Instagram and TikTok need a login), so Plate doesn't try.
  Sharing a post whose caption has no recipe offers "Save link, add the video later": the link and caption go to
  `WaitingForVideo` (app group JSON), shown as Recipes → "N waiting for a video" (`WaitingVideosView`), where a
  screen recording is picked for each and read with the caption (`AppModel.recipeFromVideo`).
- **Share extension** (`ShareExtension/`): reads the shared link or text, parses it and appends to `inbox.json` in the
  app group; the app takes the inbox when it opens (`AppModel.collectInbox`).
- **AI** (`App/AI/`): `AIChoice` automatic/apple/claude/off. Apple's Foundation Models (iOS 26, `@Generable`) is free
  and on-device; Claude is raw HTTP to the Messages API with a JSON schema output (`claude-opus-5-5` by default,
  `claude-haiku-5-5` as the cheaper option). A Claude.ai subscription can't be linked; only an API key. If AI fails,
  Plate's own parsing stands.
- **Planner** (`Planner.swift`): seeded, scores recipes by what's in stock, overlap with the rest of the week, expiring
  food, favourites, batch cooking and calorie targets. Locked entries stay put.
- **Home dashboard**: `Dashboard.swift` in PlateCore holds the tiles, grid packing (`DashboardGrid.place`), free placement (`row`/`column` per tile, `moveTile`, `tidyPage`; a spot that doesn't fit a narrower
  grid falls back to the first gap), idle
  timing, night dimming, the slideshow order and `IdleArtwork.choose` (album cover while music plays, else the photo
  album, else a clock); all tested in `DashboardTests.swift`. Saved as `household.dashboard`. The app side is
  `App/Home/`: `HomeStore` (HomeKit), `MusicStore` and `PhotoStore` (MusicKit, PhotoKit), `DashboardView` (grid, edit
  mode, pages), `RoomsPage.swift` (a page with `layout == .rooms`: one column per HomeKit room; choice and order in `RoomsPage`), `TileViews`/`MoreTiles` (one view per `TileKind`, all drawn on `TileCard` from `Style.swift` so any
  theme stays readable), `StyleEditors` (look, one tile, one accessory), `SetupEditors` (settings, pages, chores, bin
  days, routines, layout export), `Engine.swift` (`DashboardEngine`: timers, routines and schedules, typed commands,
  briefing; made once in `PlateApp`), `AddTileView`, `WallModeView` (full screen, screen kept on, idle artwork).
  The pure parts are `DashboardStyle.swift` (colours, themes, sound packs made from notes), `DashboardExtras.swift`
  (pages, timers, chores, bin days, routines, light shows) and `Commands.swift` (typed commands, no AI), each with
  its own test file. Adding a `TileKind` means a case in `TileView`, a row in `AddTileView` and, if it has settings,
  a case in `TileEditorView.particular`; per-tile settings go in `tile.options`. The guest Wi-Fi password lives in the
  keychain (`SecretStore`), never in the household file. The trains tile (`Trains.swift`, `TrainTile.swift`) reads National
  Rail's Live Departure Board from `api1.raildata.org.uk` with the user's own key (keychain, header `x-apikey`); the
  request carries only station codes. Music uses `SystemMusicPlayer`, so the dashboard follows whatever the Music app
  is playing (Ethan found `ApplicationMusicPlayer` didn't, 12 November 2026). Devices are still set up and
  automated in Apple's Home app. "Pinned albums" means Apple Music albums (Ethan, 12 November 2026). The weather tile
  (`WeatherTile.swift`, WeatherKit plus a once-asked location rounded to ~1 km) must show Apple's Weather mark and
  legal link. The app needs the HomeKit and WeatherKit capabilities and the MusicKit and WeatherKit app services ticked on `com.randomedp.plate`; "Open in wall mode" is a per-device
  `UserDefaults` setting. The app is iPhone (portrait) and iPad (every orientation, as Apple requires).
- **Shopping** (`Shopping.swift`): needs from the chosen meals, minus the kitchen, then `bestPacks` (a small knapsack
  over pack sizes per store, with a waste penalty for perishables).

## 6. In flight / next up

- The app group is `group.com.randomedp.plate.share` for both the app and the extension: that's the name Ethan
  registered (November 2026), so don't "tidy" it to `group.com.randomedp.plate` (that id was taken by an App ID by
  mistake). The group has to be ticked on both bundle ids; group names are case-sensitive. `apple-profiles.yml` checks.
- Household sharing between people (later).
- Real supermarket prices (the ones in `FoodDatabase.swift` are rough, November 2026).
