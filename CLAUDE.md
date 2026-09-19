# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Verify

**Builds run on Xcode Cloud, not locally.** Opening a PR triggers a validation build; pushing/merging to `main` triggers the TestFlight build (a shared scheme + TestFlight automation exist for this). The way to get a change verified is to put it on a branch and open a PR — not to run a local build. There is no linter configured. The one test target is **`MacroHuntUITests`** (XCUITest; `DuoBarsUITests`, the guard on the iPhone Duo bar migration below) — it rides the `MacroHunt` scheme's test action (built for testing only, never archived) and is run locally by `scripts/duo-check.sh`; Xcode Cloud only runs it if the workflow has a Test action.

Optional local compile check (confirms it builds; not the team's verification path):

```bash
xcodebuild -scheme MacroHunt -destination 'platform=iOS Simulator,name=iPhone 17' build
```

Open `MacroHunt.xcodeproj` in Xcode for development. iOS 26+ (deployment target 26.0 — Keith is the only user and runs the current release, so there is no reason to keep older targets alive); SwiftUI + SwiftData + Swift Charts; bundle id `com.kad-air.MacroHunt`.

**Adding a source file:** the project is in the explicit-reference format (`objectVersion = 56`, no file-system-synchronized groups), so every `.swift` file is individually listed in `MacroHunt.xcodeproj/project.pbxproj`. A new file must be registered there (PBXBuildFile entry, PBXFileReference, group membership, and the Sources build phase) or it won't compile. Repurposing/renaming an already-referenced file avoids hand-editing the pbxproj. The UI-test target was added the same way by hand (object ids `0010000…0011`–`…0015`, configs `…0005`/`…0006`).

### The iPhone Duo check (run it; it fails loudly)

```bash
scripts/duo-check.sh              # SKIP_TESTS=1 stops before the UI test
```

Proves, against the real toolchain and the *built* product, that the app is Duo-ready: an Xcode with an iOS Simulator SDK ≥ 27.1 (auto-detected under `/Applications/Xcode*.app`), an iOS ≥ 27.1 runtime and the iPhone Duo device type, a Release build whose built `Info.plist` links `iphonesimulator27.1+` with no `UIRequiresFullScreen` and both device families, the app alive 8 s after launch on a Duo simulator, every panel captured with at least one lit (under `/tmp/macrohunt-duo-check/`), then `MacroHuntUITests` on that simulator. It **reuses** an existing Duo simulator (a booted one first, then "MacroHunt iPhone Duo", then any Duo-typed device — e.g. Stow's) and only creates one as a last resort. The Duo boots *closed*: the default `simctl io … screenshot` is the dark inner panel; the cover is `--display=1`, the inner `--display=3`, and the pose is only switchable in Device Hub (ask). **Never `CODE_SIGNING_ALLOWED=NO` a build you will launch** — unsigned, the app has no HealthKit entitlement and alerts on launch; local automatic signing works. The recipe and gotchas: `~/Code/iphone-duo-playbook.md`.

## Architecture

Single-target iOS app, services-based, **local-first**, with **optional** best-effort sync to Craft Docs. At launch the app sets up a SwiftData `ModelContainer` for `Meal` and injects `CredentialsManager` as an `@EnvironmentObject`; `MainTabView` hosts the Today / Calendar / Trends / Add / Settings surfaces.

### Meal logging data flow

Photos and/or a text description → `ClaudeAPI` (AI analysis) → `NutritionAnalysis` → `Meal` → `MealRepository.saveMealWithSync` → local SwiftData → (best-effort) Craft Docs + Apple Health.

Only the Anthropic key is required to log a meal: AI analysis is gated on `isAIConfigured`, and meals always save to local SwiftData. Craft and Apple Health are independent opt-in mirrors. Either a photo *or* a description is sufficient to analyze (`AddMealView.canAnalyze`); `ClaudeAPI` adapts its prompt to whichever was provided.

### Local-first persistence (load-bearing invariant)

`MealRepository.saveMealWithSync` is **local-first**: it inserts into SwiftData and saves **first** — that local write is the source of truth and the only step that can fail the log. *Only then* does it best-effort mirror the meal to **Craft Docs** (gated on `craftSyncActive`) and **Apple Health** (gated on `healthKitSyncEnabled`). Both mirrors are wrapped so they **never throw and never undo a logged meal**: a Craft outage, a denied HealthKit permission, or a user who never configured either still logs normally. The Craft step persists the returned `craftDocId` as soon as the item is created (before uploading photos/notes) so a later delete can clean Craft up even if the content upload fails; the HealthKit step stores `healthKitFoodUUID`. `deleteMealWithSync` runs in the reverse-friendly order: best-effort remove the Craft mirror (if synced) and the HealthKit mirror (while their ids are still on the meal), **then** the authoritative local delete. The mirror steps are best-effort; the local insert/delete are authoritative — do not make a mirror failure block or roll back the local write.

> **History:** this used to be the opposite — "Craft-first transactional," where the local insert was skipped if Craft threw. That was inverted deliberately when the product repositioned around local/on-device + Apple Health as the real store, with Craft demoted to an optional export equal to the HealthKit mirror. Do not reintroduce a hard dependency on Craft in the save path.

> **Planned — more export integrations:** Craft is the *first* optional export mirror, not a special case. The roadmap is to add **Notion** and **Google Sheets** (and similar) as additional best-effort export targets, each implemented the same way — a service client plus a `*DocId`/external-id link on `Meal`, mirrored after the authoritative local save and never able to block or undo a log, gated on its own opt-in. In the UI these live together under **Settings → Integrations** (the "More coming" row there is the placeholder). A related polish item is making Craft setup bulletproof by auto-creating the Meal Tracker collection for the user instead of asking for a Collection ID. When adding one, follow the Craft mirror's shape exactly and keep the local-first invariant above intact.

### Key services

- **ClaudeAPI** (`Services/ClaudeAPI.swift`): Anthropic Messages API client. Two entry points, both on `claude-sonnet-4-6`: `analyzeMealPhotos` (photo/description → nutrition), and `generateReflection` (Phase 3 daily-coaching snapshot → `CoachingReflection`). The reflection regenerates after every logged meal (see Today's `ReflectionViewModel`), so it runs on Sonnet for the call volume rather than Opus. Both use **structured outputs** (`output_config.format` with a JSON schema), so responses are guaranteed schema-valid and need no JSON cleanup. **If you change `NutritionAnalysis` or `CoachingReflection`, update the matching schema in this file.** The reflection's supportive, non-judgy, not-medical-advice tone is a **system-prompt contract** — keep it intact. Images are sent as inline base64 JPEG; the `refusal` stop reason is handled. Raw `URLSession`/`JSONSerialization` — there is no Anthropic SDK dependency. **Two distinct URLSessions** (`NetworkConfig.session` vs `NetworkConfig.reflectionSession`): the user-facing analyze call and the background reflection must use separate sessions so they get separate HTTP/2 connections to api.anthropic.com — sharing one let an in-flight reflection starve the analyze request's data frames and trip its timeout. Keep the reflection on its own session.
- **CraftAPI** (`Services/CraftAPI.swift`): Craft Docs REST client. `createMealItem` returns the new doc id; `addMealContent` uploads photos + a text block; `deleteMealItem` removes it. Retries with exponential backoff (`executeRequest`).
- **MealRepository** (`Services/MealRepository.swift`): `@MainActor` data layer over the SwiftData `ModelContext`. Owns the local-first save/delete (see above) plus the fetch and analytics helpers (`dailyTotals`, `weeklyAverages`, `dailyCaloriesForRange`) that feed Today/Calendar/Trends.
- **HealthKitService** (`Services/HealthKitService.swift`): `HKHealthStore` read/write bridge. **Write** — saves each `Meal` as a `.food` `HKCorrelation` (Phase 1; gated on the opt-in toggle, best-effort, never blocks logging). **Read** — weight (`bodyMass`), activity/energy (`active`/`basal` energy, steps, workouts), and cardio (`restingHeartRate`, `HRV`, `vo2Max`, `cardioRecovery`) for the Trends Health sections (Phase 2). A single `requestAuthorization()` requests both directions. Reads are best-effort and non-throwing — HealthKit hides read-auth status, so empty results are treated as "not connected" and the UI degrades gracefully. **Do not add a correlation type to the *share* set** — it triggers an uncatchable SIGABRT (see the comment in `nutritionTypesToShare`).

### Data model

Single SwiftData model: `Meal` (`Models/Meal.swift`). Photo bytes are `@Attribute(.externalStorage) var photoData: [Data]`; `craftDocId` links a row to its synced Craft item; `healthKitFoodUUID` links it to its mirrored Apple Health `.food` sample (both optional, so existing stores migrate without a schema break); `mealType` is a computed wrapper over the stored `mealTypeRaw`. `NutritionAnalysis` and `CoachingReflection` (same file) are the AI result structs, decoded directly from the Claude responses.

### Credentials

`CredentialsManager` (`Utilities/CredentialsManager.swift`, an `ObservableObject`) is the single source of truth for configuration:

- **Keychain** (via `KeychainHelper`, service `com.kad-air.MacroHunt`): `craftToken`, `anthropicKey`.
- **App-group `UserDefaults`** (suite `group.kad-air.MacroHunt`): `spaceId`, `collectionId`, `dailyCalorieGoal`, `macroSplit`, `customProteinPct`/`customCarbsPct`/`customFatPct` (whole-number percentages, only consulted when `macroSplit == .custom`), `healthKitSyncEnabled`, `craftSyncEnabled` (opt-out, defaults on), `dailyReflectionEnabled` (defaults on), `weightGoalKg` (canonical kg; entered/displayed in the user's preferred Health unit), `weightGoalDirection`. The app group may be unavailable if the entitlement isn't configured — surfaced via `configurationError`, not a crash.
- **Gating is split, and `isValid` does *not* gate logging.** `isAIConfigured` (Anthropic key present) is what gates AI analysis and meal logging. `isCraftConfigured` (all three Craft fields) plus the `craftSyncEnabled` opt-out combine into `craftSyncActive` — the single gate the repository checks before touching Craft. `isValid` (`isAIConfigured && isCraftConfigured`) is now only a "fully set up" indicator. Macro goals (`proteinGoal`/`carbsGoal`/`fatGoal`) are derived from `dailyCalorieGoal` × the active macro ratios. `MacroSplit` has three presets plus `.custom`; `CredentialsManager.macroRatios` resolves the preset's fixed split or, for `.custom`, the user's `customProteinPct`/`customCarbsPct`/`customFatPct` (normalized to sum to 1). The presets are calibrated to the IOM Acceptable Macronutrient Distribution Ranges — **if you retune them or change the macro math, update `MacroSplit.presetRatios` and the matching `description` strings together.**

Users enter these in **Settings → API Configuration** and in first-run onboarding. The Anthropic key comes from console.anthropic.com.

### Design system

Warm "Liquid Glass" design language (translucent materials, glass cards) over a warm gradient field. A single warm palette **adapts to light/dark via the system setting** (the app does not override appearance); the accent is green. All tokens + shared components live in `Utilities/DesignSystem.swift`:

- **`Theme`** — the dynamic color palette (`ink`/`ink2`/`ink3`, `accent`/`accent2`/`accentSoft`/`onAccent`, `protein`/`carbs`/`fat`/`good`, plus `chip`/`hair`/`track`/glass tokens). Each token is built from `Color(light:dark:)` so it tracks the trait collection. **Use `Theme.*`, not raw `.orange`/`.secondary`,** so light/dark stays consistent.
- **Surfaces/layout:** `WarmBackground` (aliased as `LiquidGlassBackground`), `GlassCard`, `.glassContainer()`, `MHHeader`, `SectionHeader`.
- **Components:** `CalorieRing`, `MacroTrack`, `StatTile`, `StatusPill`, `SegmentedToggle`, `MealCard`, plus `PrimaryButtonStyle`/`GhostButtonStyle` and `.inputFieldStyle()`.

`MainTabView` **is a system `TabView`** hosting the four surfaces (Today/Calendar/Trends/Settings); the Add-meal sheet is opened by the "Add meal" bar action on the Today/Calendar/Trends roots (`AddMealToolbarItem`) and Today's in-content "log next" row. It used to be a hand-drawn floating bar with a center "+" — that was replaced deliberately for the iPhone Duo (below); don't bring the custom bar back. Settings lives **only** in the tab bar (a plain `gearshape`), not duplicated in any header.

### iPhone Duo (iOS 27.1) — bars are system bars

The Duo lays the status bar, tab bar and toolbar items out as a **vertical strip on the trailing edge** of its cover display and of its open inner display — but only for standard items that carry **both a title and an SF Symbol** inside a system `TabView` / `NavigationStack` `.toolbar`. Hidden bars, hand-drawn bars/chips, `Image`-only labels and text-only items never get it. Hence the rules this codebase follows (HIG "Designing for iPhone Duo"):

- **Tab roots keep their navigation bar visible** via `.tabRootBar("Today")` (`Utilities/DesignSystem.swift`): `.navigationTitle` + `.toolbarTitleDisplayMode(.inline)` + `.toolbar(removing: .title)`, so the in-content `MHHeader` masthead stays the visible title and the bar still exists to host items. Never reintroduce `.navigationBarHidden(true)` on a root. The Add action is `AddMealToolbarItem` (`Label("Add meal", systemImage: "plus")`, `.topBarTrailing`), attached to the root content outside any empty/loading branch.
- **Sheets are `NavigationStack`s with semantic dismiss items**: `.confirmationAction` → `Button("Done", systemImage: "checkmark")`, `.cancellationAction` → `Button("Cancel", systemImage: "xmark")`. Don't hand-style bar items; the system draws them. **Every sheet's NavigationStack carries `.tint(Theme.accent)`** — a sheet is its own presentation root and does not inherit the TabView's tint (a prominent confirmation item renders system blue otherwise). Content-level buttons (Save meal, Re-analyze, Onboarding's Back/Next) stay where they are.
- Layout is size-class-only (already true; nothing reads `userInterfaceIdiom`/`UIScreen`/orientation). Bare `ignoresSafeArea()` is only on backgrounds/scrims. Plist: all orientations, generated launch screen, `TARGETED_DEVICE_FAMILY = 1,2`, no `UIRequiresFullScreen` — `duo-check.sh` asserts the built plist.
- **The proof** is `MacroHuntUITests/DuoBarsUITests.swift`: launches with `MACROHUNT_DEBUG_ANTHROPIC_KEY` (seeds a bogus key *only while nothing is stored*, never written to the keychain, so onboarding doesn't cover the tabs), finds the four tabs and the "Add meal" item on each root by label, and asserts a vertical trailing column on the Duo's cover / open inner display (device from `SIMULATOR_MODEL_IDENTIFIER == "iPhone19,4"`, pose from `activeScreen()` — the largest *lit* `XCUIScreen.screens` entry, because `XCUIScreen.main` is the Duo's dark cover display even when it's open, and **never** `app.frame`, which stays unrotated on the open inner display) or horizontal bars elsewhere. Each surface is attached to the `.xcresult` with `.keepAlways` (`xcrun xcresulttool export attachments`), which is how the Duo screenshots under `docs/duo/` were produced.
- What decides how the app looks on the Duo is **the SDK it links**: 27.0 shows it inset from the status bar, 27.1 reaches the edge and lays bars out vertically. Xcode Cloud must build with **Xcode 27.1** (pick it in the workflow) for TestFlight to get the Duo layout.
