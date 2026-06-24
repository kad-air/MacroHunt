# HealthKit Integration Plan

A phased plan to connect MacroHunt to Apple Health: push the meals we log *out* to
Health, pull weight / activity / cardiovascular data *in*, add a weight target, and
feed the combined picture to Claude for thoughtful, non-judgy coaching.

Each phase is a self-contained PR. Cloud sessions ship one PR at a time, so this file
is the running source of truth — update the checkboxes as phases land.

## Progress

- [x] **Phase 1 — Write meals to Apple Health** (this PR)
- [ ] **Phase 2 — Read weight / activity / cardio + weight target**
- [ ] **Phase 3 — Claude coaching from the combined picture**

---

## Phase 1 — Write meals to Apple Health ✅

**Goal:** every meal logged in MacroHunt appears in Apple Health's nutrition log, so it
flows to the Fitness app and any other Health-aware app. Write-only; opt-in.

**Done in this PR:**
- `Services/HealthKitService.swift` — `HKHealthStore` wrapper. Saves each meal as an
  `HKCorrelation` of type `.food` bundling four quantity samples:
  `dietaryEnergyConsumed` (kcal), `dietaryProtein`, `dietaryCarbohydrates`,
  `dietaryFatTotal` (g). Handles authorization, save, and delete-by-UUID.
- `Models/Meal.swift` — added `healthKitFoodUUID: String?` (optional, defaults nil →
  no SwiftData migration break), mirroring how `craftDocId` links a row to Craft.
- `Services/MealRepository.swift` — HealthKit write is a **best-effort third step
  after** the load-bearing Craft → SwiftData save (never throws, never blocks logging).
  Delete mirrors it, removing the Health entry before the local delete.
- `Utilities/CredentialsManager.swift` — `healthKitSyncEnabled` flag in app-group
  `UserDefaults` (defaults off). Independent of `isValid` — Health sync works without
  Craft configured.
- `Views/Settings/SettingsView.swift` — "Apple Health" card with an opt-in toggle that
  requests authorization on enable and reverts if it fails / Health is unavailable.
- `MacroHunt/MacroHunt.entitlements` — new file: `com.apple.developer.healthkit` plus
  the existing `group.kad-air.MacroHunt` app group (now declared explicitly).
- `project.pbxproj` — registered the new service file, wired `CODE_SIGN_ENTITLEMENTS`,
  and added `NSHealthUpdateUsageDescription` / `NSHealthShareUsageDescription` Info.plist
  keys to both Debug and Release.

**Out of band — verify before/after merge (cannot be done from a cloud build):**
- In the Apple Developer portal, confirm the App ID (`com.kad-air.MacroHunt`) has the
  **HealthKit** and **App Groups** capabilities enabled, so automatic signing on Xcode
  Cloud can provision the new entitlements. (The app already relies on the app group;
  this PR just makes it explicit in the entitlements file.)
- HealthKit does not run meaningfully in the Simulator — test the actual read/write on a
  physical device.

**Notes / known nuances:**
- The read usage string (`NSHealthShareUsageDescription`) is declared now to avoid a
  second pbxproj edit in Phase 2; Phase 1 requests no read access.
- Deleting the `.food` correlation removes the meal entry; child quantity samples may
  linger in some iOS versions. Acceptable for now — revisit if it proves noisy.
- HealthKit is unavailable on iPad; the Settings card hides the toggle there.

---

## Phase 2 — Read weight / activity / cardio + weight target

**Goal:** pull Health data in to give an energy-balance and trend picture, and let the
user set a weight target.

**Planned work:**
- Extend `HealthKitService` with read queries + authorization for:
  - **Weight:** `bodyMass` (latest + trend series).
  - **Energy out / activity:** `activeEnergyBurned`, `basalEnergyBurned`, `stepCount`,
    and `HKWorkout` sessions.
  - **Cardiovascular:** `restingHeartRate`, `heartRateVariabilitySDNN`, `vo2Max`,
    `appleCardioRecovery` (slow-moving weekly trends).
- `CredentialsManager`: add `weightGoal` (+ optional `goalDirection`: lose/maintain/gain)
  in app-group `UserDefaults`, with input in `SettingsView` beside the calorie goal.
- Trends surface (`Views/Trends/`): intake-vs-expenditure chart and a weight-trend chart
  vs. target, reusing components in `MacroCharts.swift`. Add read-trend helpers in a
  HealthKit data layer paralleling `weeklyAverages()` / `dailyCaloriesForRange(days:)`.
- Onboarding/Settings: request read authorization for the new types.

**Risks:** read authorization is privacy-gated (HealthKit hides whether read was
granted); design the UI to degrade gracefully when no data is returned.

---

## Phase 3 — Claude coaching from the combined picture

**Goal:** thoughtful, supportive, non-judgy guidance grounded in intake + Health trends.

**Planned work:**
- New method on `ClaudeAPI` — `generateCoaching(context:)` — separate from meal analysis.
  Sends a compact JSON snapshot: recent intake averages (from `MealRepository`), weight
  trend, active energy, resting HR / HRV trend, and the user's calorie/macro/weight goals.
- Reuse the structured-output (`output_config` + JSON schema) pattern already in
  `ClaudeAPI`. Suggested schema: `{ headline, observations[], suggestion, encouragement }`.
- **Tone is a system-prompt contract:** supportive, curious, never shaming; food framed
  neutrally (no "good/bad" foods, no guilt); acknowledge effort; one gentle, actionable
  suggestion at a time.
- **Not medical advice:** clear disclaimer; steer away from anything diagnostic,
  especially around cardio metrics and rate of weight change.
- Consider running this single call on `claude-opus-4-8` (max quality) while meal
  analysis stays on `claude-sonnet-4-6`.
- Surface as a coaching card (Today or Trends), generated on demand / cached daily.

**Dependency:** needs Phase 2's Health reads to have meaningful context.
