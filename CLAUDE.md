# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Verify

**Builds run on Xcode Cloud, not locally.** Opening a PR triggers a validation build; pushing/merging to `main` triggers the TestFlight build (a shared scheme + TestFlight automation exist for this). The way to get a change verified is to put it on a branch and open a PR — not to run a local build. There is **no test target** and no linter configured, so `xcodebuild` only ever exercises the compiler.

Optional local compile check (confirms it builds; not the team's verification path):

```bash
xcodebuild -scheme MacroHunt -destination 'platform=iOS Simulator,name=iPhone 17' build
```

Open `MacroHunt.xcodeproj` in Xcode for development. iOS 17+ (deployment target 17.0); SwiftUI + SwiftData + Swift Charts; bundle id `com.kad-air.MacroHunt`.

**Adding a source file:** the project is in the explicit-reference format (`objectVersion = 56`, no file-system-synchronized groups), so every `.swift` file is individually listed in `MacroHunt.xcodeproj/project.pbxproj`. A new file must be registered there (PBXBuildFile entry, PBXFileReference, group membership, and the Sources build phase) or it won't compile. Repurposing/renaming an already-referenced file avoids hand-editing the pbxproj.

## Architecture

Single-target iOS app, services-based, with transactional sync to Craft Docs. At launch the app sets up a SwiftData `ModelContainer` for `Meal` and injects `CredentialsManager` as an `@EnvironmentObject`; `MainTabView` hosts the Today / Calendar / Trends / Add / Settings surfaces.

### Meal logging data flow

Photos and/or a text description → `ClaudeAPI` (AI analysis) → `NutritionAnalysis` → `Meal` → `MealRepository.saveMealWithSync` → Craft Docs, then local SwiftData.

Either a photo *or* a description is sufficient to analyze (`AddMealView.canAnalyze`); `ClaudeAPI` adapts its prompt to whichever was provided.

### Transactional persistence (load-bearing invariant)

`MealRepository.saveMealWithSync` writes to **Craft first**, stores the returned `craftDocId` on the meal, uploads photos/notes, and **only then** inserts into SwiftData and saves. If the Craft write throws, the error propagates and the local insert is skipped — the local DB never holds a meal that isn't in Craft. `deleteMealWithSync` mirrors it: delete from Craft first, then locally. Do not reorder these. (Both Craft steps are gated on `credentials.isValid`.)

### Key services

- **ClaudeAPI** (`Services/ClaudeAPI.swift`): Anthropic Messages API client. Two entry points, two models: `analyzeMealPhotos` (photo/description → nutrition) on `claude-sonnet-4-6`, and `generateReflection` (Phase 3 daily-coaching snapshot → `CoachingReflection`) on `claude-opus-4-8` (the single quality-sensitive call). Both use **structured outputs** (`output_config.format` with a JSON schema), so responses are guaranteed schema-valid and need no JSON cleanup. **If you change `NutritionAnalysis` or `CoachingReflection`, update the matching schema in this file.** The reflection's supportive, non-judgy, not-medical-advice tone is a **system-prompt contract** — keep it intact. Images are sent as inline base64 JPEG; the `refusal` stop reason is handled. Raw `URLSession`/`JSONSerialization` — there is no Anthropic SDK dependency.
- **CraftAPI** (`Services/CraftAPI.swift`): Craft Docs REST client. `createMealItem` returns the new doc id; `addMealContent` uploads photos + a text block; `deleteMealItem` removes it. Retries with exponential backoff (`executeRequest`).
- **MealRepository** (`Services/MealRepository.swift`): `@MainActor` data layer over the SwiftData `ModelContext`. Owns the transactional save/delete plus the fetch and analytics helpers (`dailyTotals`, `weeklyAverages`, `dailyCaloriesForRange`) that feed Today/Calendar/Trends.
- **HealthKitService** (`Services/HealthKitService.swift`): `HKHealthStore` read/write bridge. **Write** — saves each `Meal` as a `.food` `HKCorrelation` (Phase 1; gated on the opt-in toggle, best-effort, never blocks logging). **Read** — weight (`bodyMass`), activity/energy (`active`/`basal` energy, steps, workouts), and cardio (`restingHeartRate`, `HRV`, `vo2Max`, `cardioRecovery`) for the Trends Health sections (Phase 2). A single `requestAuthorization()` requests both directions. Reads are best-effort and non-throwing — HealthKit hides read-auth status, so empty results are treated as "not connected" and the UI degrades gracefully. **Do not add a correlation type to the *share* set** — it triggers an uncatchable SIGABRT (see the comment in `nutritionTypesToShare`).

### Data model

Single SwiftData model: `Meal` (`Models/Meal.swift`). Photo bytes are `@Attribute(.externalStorage) var photoData: [Data]`; `craftDocId` links a row to its synced Craft item; `mealType` is a computed wrapper over the stored `mealTypeRaw`. `NutritionAnalysis` (same file) is the AI result struct, decoded directly from the Claude response.

### Credentials

`CredentialsManager` (`Utilities/CredentialsManager.swift`, an `ObservableObject`) is the single source of truth for configuration:

- **Keychain** (via `KeychainHelper`, service `com.kad-air.MacroHunt`): `craftToken`, `anthropicKey`.
- **App-group `UserDefaults`** (suite `group.kad-air.MacroHunt`): `spaceId`, `collectionId`, `dailyCalorieGoal`, `macroSplit`, `healthKitSyncEnabled`, `weightGoalKg` (canonical kg; entered/displayed in the user's preferred Health unit), `weightGoalDirection`. The app group may be unavailable if the entitlement isn't configured — surfaced via `configurationError`, not a crash.
- `isValid` requires all four of `craftToken`, `spaceId`, `anthropicKey`, `collectionId`; it gates both AI analysis and Craft sync. Macro goals (`proteinGoal`/`carbsGoal`/`fatGoal`) are derived from `dailyCalorieGoal` × the selected `macroSplit`.

Users enter these in **Settings → API Configuration** and in first-run onboarding. The Anthropic key comes from console.anthropic.com.

### Design system

Warm "Liquid Glass" design language (translucent materials, glass cards) over a warm gradient field. A single warm palette **adapts to light/dark via the system setting** (the app does not override appearance); the accent is green. All tokens + shared components live in `Utilities/DesignSystem.swift`:

- **`Theme`** — the dynamic color palette (`ink`/`ink2`/`ink3`, `accent`/`accent2`/`accentSoft`/`onAccent`, `protein`/`carbs`/`fat`/`good`, plus `chip`/`hair`/`track`/glass tokens). Each token is built from `Color(light:dark:)` so it tracks the trait collection. **Use `Theme.*`, not raw `.orange`/`.secondary`,** so light/dark stays consistent.
- **Surfaces/layout:** `WarmBackground` (aliased as `LiquidGlassBackground`), `GlassCard`, `.glassContainer()`, `MHHeader`, `SectionHeader`.
- **Components:** `CalorieRing`, `MacroTrack`, `StatTile`, `StatusPill`, `SegmentedToggle`, `MealCard`, plus `PrimaryButtonStyle`/`GhostButtonStyle` and `.inputFieldStyle()`.

`MainTabView` is **not** a system `TabView` — it's a custom shell hosting the four surfaces (Today/Calendar/Trends/Settings) with a floating glass tab bar (`MHTabBar`) whose center "+" opens the Add-meal sheet. Settings lives **only** in the tab bar (a plain `gearshape`), not duplicated in any header.
