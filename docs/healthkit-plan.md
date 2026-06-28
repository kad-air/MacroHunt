# Apple Health — Plan & Justification

Status: **direction / partly built.** `HEALTHKIT_INTEGRATION.md` records what already
ships (the Phase 1 write + Phase 2 reads). This document is the *forward-looking* plan for
HealthKit's **role** once the app is positioned as local-first and privacy-first — what
Apple Health is for, what it is explicitly *not* for, and what to build next.

## Why HealthKit is strategic here (not just a feature)

The product bet is: **no accounts, no server-side storage; the user's real data lives on
device and in Apple Health.** That makes HealthKit the load-bearing piece of the privacy
story, because it is the one place nutrition data can live that is:

- **owned by the user, not us** — it's their Health database, governed by their permissions;
- **portable and durable** — survives app deletion/reinstall and is shared with every other
  Health-aware app and their providers, so the user is never locked into MacroHunt;
- **off our infrastructure entirely** — we never see it, which is exactly the claim we want
  to make on the App Store privacy label and in marketing.

So Apple Health isn't a "sync target" like a cloud backend would be — it's the **public,
user-owned mirror of the on-device store**, and the reason we can honestly say we don't
collect health data.

## The model: on-device SwiftData = source of truth; Apple Health = canonical mirror

This is deliberately the same shape the `MealRepository` refactor just established (see the
"Local-first persistence" invariant in `CLAUDE.md`):

- **SwiftData (on device) is authoritative.** It's the only store the app fully controls —
  it keeps photos (`@Attribute(.externalStorage)`), the AI's `keyNutrients`, notes, and the
  links (`craftDocId`, `healthKitFoodUUID`). It's the only write that can fail a log.
- **Apple Health is a best-effort mirror, equal to Craft.** Each meal is written as a
  `.food` `HKCorrelation` (energy + protein/carb/fat). It never blocks or undoes a log.

We do **not** make HealthKit the primary store, and the plan should not drift toward that,
because HealthKit can't hold everything a meal is: it stores the four macro quantities but
**not** the photo, the meal name, the `keyNutrients`, or the notes. If Health were primary,
those would be lost. Hence: rich record on device, macro mirror in Health.

## What already exists (see HEALTHKIT_INTEGRATION.md for detail)

- **Write (Phase 1):** each `Meal` → `.food` `HKCorrelation`; `healthKitFoodUUID` links the
  SwiftData row to the Health sample; gated on `healthKitSyncEnabled`; best-effort.
- **Read (Phase 2):** weight (`bodyMass`), energy/activity (active/basal energy, steps,
  workouts), and cardio (`restingHeartRate`, HRV, `vo2Max`, cardio recovery) feed the Trends
  Health sections. Reads are best-effort/non-throwing — HealthKit hides read-auth status, so
  empty results degrade gracefully to "not connected."
- **Hard caveat to preserve:** never add a correlation type to the **share** set — it trips
  an uncatchable SIGABRT. See the comment in `nutritionTypesToShare`.

## What to build next (roadmap)

Ordered by how much each reinforces the local-first / portability claim:

1. **Backfill / reconciliation.** `syncHistoricalMeals` already pushes un-mirrored meals to
   Health (meals with `healthKitFoodUUID == nil`). Surface it as a one-tap "mirror all past
   meals to Apple Health" in Settings so a user who enables Health late, or reinstalls, can
   make Health complete. This is the concrete payoff of "your data is portable."
2. **Re-mirror on edit.** When a meal is edited, the Health sample should be updated
   (delete-by-UUID + re-add), mirroring how Craft is handled. Keep it best-effort.
3. **Resilience to orphans.** Because mirrors are best-effort, a meal can end up logged
   locally but not in Health (or vice-versa after a failed delete). Add a lightweight,
   on-demand reconcile that re-pushes locally-present-but-unmirrored meals and is safe to run
   repeatedly. Do **not** add background daemons or a server to do this — it stays an
   explicit, user-triggered action to honor "no surprise background data movement."
4. **Read coverage as differentiation.** The Trends Health reads (weight trend vs.
   `weightGoalKg`, energy balance) are where the Apple-ecosystem story shows value a cloud
   clone can't easily match. Expand thoughtfully, but keep every read best-effort and
   non-throwing per the existing pattern.

Explicit non-goals: do **not** make Health a *required* store, do **not** add a correlation
type to the share set, and do **not** introduce a server to coordinate Health state — all
three would break either stability or the privacy posture.

## How this interacts with the paid tier

The managed-AI relay (see `docs/managed-key-proxy-plan.md`) is a **pass-through for the AI
call only** — it never touches Apple Health or the meal store. HealthKit data never leaves the
device regardless of which AI tier (BYOK or managed) the user is on. Keeping these two
concerns separate is what lets the privacy claim hold: *the relay forwards an analysis request
and forgets it; the user's food history lives only on device and in their own Apple Health.*

## One-line summary

On-device SwiftData stays the authoritative store; Apple Health is the **user-owned, portable,
best-effort mirror** that makes "we don't collect your health data" literally true — so the
roadmap is about making that mirror complete and reconcilable (backfill, edit re-mirror,
orphan reconcile), never about promoting Health to the primary store or moving it through a
server.
