# HealthKit Integration Plan

A phased plan to connect MacroHunt to Apple Health: push the meals we log *out* to
Health, pull weight / activity / cardiovascular data *in*, add a weight target, and
feed the combined picture to Claude for thoughtful, non-judgy coaching.

Each phase is a self-contained PR. Cloud sessions ship one PR at a time, so this file
is the running source of truth — update the checkboxes as phases land.

## Progress

- [x] **Phase 1 — Write meals to Apple Health**
- [x] **Phase 2 — Read weight / activity / cardio + weight target**
- [x] **Phase 3 — Claude coaching from the combined picture** (this PR, with the UX revamp)

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
- `Services/MealRepository.swift` — HealthKit write is a **best-effort mirror after**
  the authoritative local SwiftData save (never throws, never blocks logging) — equal to
  the Craft mirror in the local-first save path. Delete mirrors it, removing the Health
  entry before the local delete.
- `Utilities/CredentialsManager.swift` — `healthKitSyncEnabled` flag in app-group
  `UserDefaults` (defaults off). Independent of `isValid` — Health sync works without
  Craft configured.
- `Views/Settings/SettingsView.swift` — "Apple Health" card with an opt-in toggle that
  requests authorization on enable and reverts if it fails / Health is unavailable.
- `Views/Settings/OnboardingView.swift` — added Step 4 "Apple Health" (4-pip progress
  indicator, "Enable Apple Health" button that fires authorization immediately, shows a
  green confirmation on grant, skippable via "Next"/"Get Started"). Health is optional so
  "Get Started" remains gated only on `credentials.isValid`.
- **Historical sync on first enablement** — `MealRepository.syncHistoricalMeals` finds
  all meals with no `healthKitFoodUUID` and writes them to Health in order, saving each
  UUID back to SwiftData as it goes (best-effort, individual failures skipped). Both the
  Settings card and onboarding step trigger this automatically after authorization, showing
  an inline progress bar and a "X past meals synced" confirmation when done. Subsequent
  toggle-offs/ons only pick up meals logged while sync was off.
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

## Phase 2 — Read weight / activity / cardio + weight target ✅

**Goal:** pull Health data in to give an energy-balance and trend picture, and let the
user set a weight target. Read access is opt-in via a **single unified authorization**
(write + read in one prompt), per the product decision below.

**Done in this PR:**
- `Services/HealthKitService.swift` — extended the Phase 1 write client into a read/write
  bridge:
  - `requestAuthorization()` now requests both share (nutrition) **and** read for the
    Phase 2 types in one call. HealthKit only prompts for `.notDetermined` types, so an
    existing Phase 1 install (write already granted) sees just the new read prompt — which
    is what the Trends "Connect" affordance triggers.
  - Read query layer (all **best-effort, non-throwing** — a denied/empty read returns
    `nil`/`[]`): `preferredWeightUnit()`, `latestBodyMass()` + `bodyMassSeries(days:)`,
    per-day `dailyActiveEnergy` / `dailyBasalEnergy` / `dailySteps`
    (`HKStatisticsCollectionQuery`), `workoutCount(days:)`, and latest
    `restingHeartRate` / `HRV (SDNN)` / `vo2Max` / `cardioRecovery`
    (`heartRateRecoveryOneMinute`). Reusable primitives: `latestQuantity`,
    `quantitySamples`, `dailyStatistics`, `trailingStart`.
- `Utilities/CredentialsManager.swift` — `WeightUnit` (kg/lb conversion, canonical store is
  kg) and `WeightGoalDirection` (lose/maintain/gain) enums; `weightGoalKg` (canonical) and
  `weightGoalDirection` persisted in app-group `UserDefaults`; `hasWeightGoal` flag.
- `Views/Trends/TrendsView.swift` — `HealthTrendsViewModel` (`@MainActor`) loads all reads
  concurrently (`async let`) for the selected period. New sections, each shown only when it
  has data: **Energy Balance** (logged intake bars vs. active+basal expenditure line, with
  an average-net summary), **Weight** (current/target tiles + trend chart vs. target),
  **Activity** (avg steps, avg active energy, workout count), **Cardio Vitals** (resting
  HR, HRV, VO₂ max, cardio recovery as neutral value tiles). A **Connect Apple Health**
  card appears when Health is available but no data has been read yet — its button fires the
  unified authorization and reloads, bringing existing installs up to date.
- `Views/Trends/MacroCharts.swift` — `EnergyBalanceChart`, `WeightTrendChart` (dashed target
  rule, unit-aware Y axis), `HealthMetricTile`, `LegendDot`.
- `Views/Settings/SettingsView.swift` — weight-target input in the Daily Goals card, shown
  in the Health app's **preferred unit** (resolved via `preferredWeightUnit()`, locale
  fallback) and stored as kg; a lose/maintain/gain selector appears once a target is entered.
- `Views/Settings/OnboardingView.swift` + Settings copy — updated to describe the unified
  write **and** read so the permission prompt isn't a surprise.

**No project-file changes needed:** all work lives in already-referenced files (no new
files, no `pbxproj` edits). The `com.apple.developer.healthkit` entitlement and the
`NSHealthShareUsageDescription` read string were already in place from Phase 1 (the read
string was even pre-worded for this phase).

**Out of band — verify on a physical device (cannot be done from a cloud build):**
- HealthKit reads only return data on a real device with real Health data; the Simulator
  returns nothing, so every section will read as empty there.
- Existing Phase-1 testers get the read prompt via the Trends **Connect Apple Health** card
  (or by toggling Apple Health off/on in Settings).

**Notes / known nuances:**
- Read authorization is privacy-gated — HealthKit hides whether a read was granted. The UI
  infers "not connected" from "no data at all" and shows the Connect card; every section is
  individually gated on having data, so partial grants degrade gracefully.
- VO₂ max and cardio recovery are sparse metrics; their tiles only appear when a value
  exists. Cardio tiles are deliberately neutral (value + measurement date, no ▲/▼ judgement)
  to match the Phase 3 coaching ethos.
- Days with no Health expenditure are omitted from the Energy Balance chart (they remain in
  the meal-only Calorie Trend above it).

---

## Phase 3 — Claude coaching from the combined picture ✅

**Goal:** thoughtful, supportive, non-judgy guidance grounded in intake + Health trends.
Surfaced as the **Daily reflection** in the UX revamp.

**Done in this PR:**
- `Services/ClaudeAPI.swift` — `generateReflection(context:)`, separate from meal analysis.
  Runs on **`claude-opus-4-8`** (meal analysis stays on `claude-sonnet-4-6`). Reuses the
  structured-output (`output_config` + JSON schema) pattern; schema is
  `{ headline, observations[], suggestion, encouragement }`. **Tone is enforced via the
  system prompt:** supportive, curious, never shaming; food framed neutrally; one gentle
  suggestion; explicitly not medical advice.
- `Models/Meal.swift` — `CoachingReflection` result struct mirroring the schema.
- `Views/Today/TodayView.swift` — `ReflectionViewModel` builds a compact snapshot from
  `MealRepository` (today + 7-day averages + daily-calorie series) and best-effort Apple
  Health reads (latest weight, avg active energy, avg steps, resting HR, HRV) plus the
  user's goals, then calls Claude. Surfaced as the **Daily reflection** coach card on Today
  with a full bottom-sheet (observations / one small idea / encouragement / disclaimer /
  regenerate). Generated on demand and **cached per day** (so it isn't re-billed on every
  appearance); the card is gated on the `dailyReflectionEnabled` preference + a configured
  Anthropic key.
- `Utilities/CredentialsManager.swift` — `dailyReflectionEnabled` flag (defaults on), with a
  toggle in Settings → Preferences.

**Notes / known nuances:**
- The reflection degrades gracefully when Health or meal data is sparse — the prompt is told
  to say so kindly rather than overreach.
- The daily cache lives in standard `UserDefaults` (a per-device convenience), keyed by day.
