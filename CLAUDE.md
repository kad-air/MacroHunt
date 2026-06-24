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

- **ClaudeAPI** (`Services/ClaudeAPI.swift`): Anthropic Messages API client for photo/description → nutrition. The model is a single constant — `claude-sonnet-4-6`; flip to `claude-opus-4-8` for max accuracy. Uses **structured outputs** (`output_config.format` with a JSON schema mirroring `NutritionAnalysis`), so the response is guaranteed schema-valid and needs no JSON cleanup. **If you change `NutritionAnalysis`, update the schema in this file to match.** Images are sent as inline base64 JPEG; the `refusal` stop reason is handled. Raw `URLSession`/`JSONSerialization` — there is no Anthropic SDK dependency.
- **CraftAPI** (`Services/CraftAPI.swift`): Craft Docs REST client. `createMealItem` returns the new doc id; `addMealContent` uploads photos + a text block; `deleteMealItem` removes it. Retries with exponential backoff (`executeRequest`).
- **MealRepository** (`Services/MealRepository.swift`): `@MainActor` data layer over the SwiftData `ModelContext`. Owns the transactional save/delete plus the fetch and analytics helpers (`dailyTotals`, `weeklyAverages`, `dailyCaloriesForRange`) that feed Today/Calendar/Trends.

### Data model

Single SwiftData model: `Meal` (`Models/Meal.swift`). Photo bytes are `@Attribute(.externalStorage) var photoData: [Data]`; `craftDocId` links a row to its synced Craft item; `mealType` is a computed wrapper over the stored `mealTypeRaw`. `NutritionAnalysis` (same file) is the AI result struct, decoded directly from the Claude response.

### Credentials

`CredentialsManager` (`Utilities/CredentialsManager.swift`, an `ObservableObject`) is the single source of truth for configuration:

- **Keychain** (via `KeychainHelper`, service `com.kad-air.MacroHunt`): `craftToken`, `anthropicKey`.
- **App-group `UserDefaults`** (suite `group.kad-air.MacroHunt`): `spaceId`, `collectionId`, `dailyCalorieGoal`, `macroSplit`. The app group may be unavailable if the entitlement isn't configured — surfaced via `configurationError`, not a crash.
- `isValid` requires all four of `craftToken`, `spaceId`, `anthropicKey`, `collectionId`; it gates both AI analysis and Craft sync. Macro goals (`proteinGoal`/`carbsGoal`/`fatGoal`) are derived from `dailyCalorieGoal` × the selected `macroSplit`.

Users enter these in **Settings → API Configuration** and in first-run onboarding. The Anthropic key comes from console.anthropic.com.

### Design system

iOS 26 Liquid Glass design language (translucent materials, glass cards). Shared components in `Utilities/DesignSystem.swift` (`GlassCard`, `SectionHeader`, `PrimaryButtonStyle`, `.inputFieldStyle()`, `LiquidGlassBackground`).
