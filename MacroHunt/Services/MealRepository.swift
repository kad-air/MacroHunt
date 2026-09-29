// Services/MealRepository.swift
import Foundation
import SwiftData

@MainActor
class MealRepository: ObservableObject {
    private let modelContext: ModelContext
    private let credentials: CredentialsManager

    init(modelContext: ModelContext, credentials: CredentialsManager) {
        self.modelContext = modelContext
        self.credentials = credentials
    }

    // MARK: - Combined Save (local-first)

    /// Saves a meal **local-first**: local SwiftData is the source of truth and the only
    /// step that can fail the log. Craft Docs and Apple Health are equal, *best-effort*
    /// mirrors that run after the local save and never throw — a mirror failure must never
    /// undo a logged meal.
    ///
    /// Returns as soon as the local save lands; the mirrors run in a background task. The
    /// caller used to await them too, so a Craft outage (3 retries × 90–150 s timeouts) held
    /// the "Saving meal…" overlay up for minutes on a meal that was already logged.
    ///
    /// This inverts the app's earlier "Craft-first transactional" order. The product is
    /// local/on-device with Apple Health as the real store; Craft is an optional export, not
    /// a gate, so a Craft outage or a user who never configured Craft can still log normally.
    /// (See `docs/managed-key-proxy-plan.md` for the related paid-tier direction.)
    func saveMealWithSync(_ meal: Meal) async throws {
        // 1. Authoritative write: local SwiftData. If this throws, the meal did not log and
        //    the error propagates to the caller.
        modelContext.insert(meal)
        try modelContext.save()

        // 2. Best-effort mirrors, off the caller's critical path. The task inherits the main
        //    actor, which `Meal` and the model context need.
        Task { await mirror(meal) }
    }

    /// The Craft Docs and Apple Health mirrors for a freshly saved meal. Never throws.
    private func mirror(_ meal: Meal) async {
        // Craft Docs: gated on the user's opt-in; never undoes the local save. The doc id is
        // persisted as soon as the item is created so a later delete can still clean Craft up
        // even if the content upload (photos/notes) fails.
        if credentials.craftSyncActive {
            let craftAPI = CraftAPI(token: credentials.craftToken, spaceId: credentials.spaceId)
            do {
                let docId = try await craftAPI.createMealItem(
                    collectionId: credentials.collectionId,
                    meal: meal
                )
                // Deleted while the create was in flight: take the new Craft item back out.
                guard !meal.isDeleted else {
                    try? await craftAPI.deleteMealItem(collectionId: credentials.collectionId, itemId: docId)
                    return
                }
                meal.craftDocId = docId
                try? modelContext.save()

                if !meal.photoData.isEmpty || !meal.notes.isEmpty {
                    try await craftAPI.addMealContent(documentId: docId, photoData: meal.photoData, description: meal.notes)
                }
            } catch {
                // Mirror failed — leave the logged meal intact and (possibly) unsynced. The
                // local DB is still correct; we do not surface this or roll anything back.
            }
        }

        // Apple Health: same contract — gated, never throws. Skipped if the meal was deleted
        // while the Craft step was in flight.
        if credentials.healthKitSyncEnabled, !meal.isDeleted {
            if let hkUUID = try? await HealthKitService.shared.saveMeal(meal) {
                guard !meal.isDeleted else {
                    try? await HealthKitService.shared.deleteMeal(healthKitFoodUUID: hkUUID)
                    return
                }
                meal.healthKitFoodUUID = hkUUID
                try? modelContext.save()
            }
        }
    }

    // MARK: - Combined Delete (local-first)

    /// Deletes a meal **local-first**: the mirror identifiers are captured, the authoritative
    /// local delete runs (the only step that can fail), and then the Craft and Apple Health
    /// copies are removed best-effort in a background task, so the row disappears at once
    /// instead of waiting on Craft's retries. A failed mirror cleanup leaves an orphan in
    /// Craft/Health but never blocks removing the meal the user asked to delete.
    ///
    /// A mirror is removed whenever the meal has one, even if that sync has since been
    /// switched off: deleting a meal should take its copies with it (an orphaned Health
    /// entry keeps counting toward the day's dietary energy).
    func deleteMealWithSync(_ meal: Meal) async throws {
        let craftDocId = meal.craftDocId
        let hkUUID = meal.healthKitFoodUUID

        // 1. Authoritative: local delete. If this throws, the meal is still logged and the
        //    mirrors are left alone.
        modelContext.delete(meal)
        try modelContext.save()

        // 2. Best-effort mirror cleanup with the captured ids. Never throws.
        let craftConfigured = credentials.isCraftConfigured
        let token = credentials.craftToken
        let spaceId = credentials.spaceId
        let collectionId = credentials.collectionId
        Task {
            if craftConfigured, let craftDocId {
                let craftAPI = CraftAPI(token: token, spaceId: spaceId)
                try? await craftAPI.deleteMealItem(collectionId: collectionId, itemId: craftDocId)
            }
            if let hkUUID {
                try? await HealthKitService.shared.deleteMeal(healthKitFoodUUID: hkUUID)
            }
        }
    }

    // MARK: - Local-Only Operations (for internal use)

    private func saveLocalOnly(_ meal: Meal) throws {
        modelContext.insert(meal)
        try modelContext.save()
    }

    private func deleteLocalOnly(_ meal: Meal) throws {
        modelContext.delete(meal)
        try modelContext.save()
    }

    func fetchMealsForDate(_ date: Date) throws -> [Meal] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let predicate = #Predicate<Meal> { meal in
            meal.date >= startOfDay && meal.date < endOfDay
        }

        let descriptor = FetchDescriptor<Meal>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.date)]
        )

        return try modelContext.fetch(descriptor)
    }

    func fetchMealsInRange(from startDate: Date, to endDate: Date) throws -> [Meal] {
        let predicate = #Predicate<Meal> { meal in
            meal.date >= startDate && meal.date < endDate
        }

        let descriptor = FetchDescriptor<Meal>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.date)]
        )

        return try modelContext.fetch(descriptor)
    }

    func fetchAllMeals() throws -> [Meal] {
        let descriptor = FetchDescriptor<Meal>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    // MARK: - Analytics Helpers

    func dailyTotals(for date: Date) throws -> (calories: Int, protein: Double, carbs: Double, fat: Double) {
        let meals = try fetchMealsForDate(date)
        return meals.reduce((0, 0.0, 0.0, 0.0)) { result, meal in
            (
                result.0 + meal.calories,
                result.1 + meal.protein,
                result.2 + meal.carbs,
                result.3 + meal.fat
            )
        }
    }

    /// Averages intake over the days the user *actually logged*, not a fixed 7. A day with no
    /// meals means it wasn't tracked — not that zero calories were eaten — so folding those
    /// days into the divisor would understate real intake. `trackedDays` lets callers be
    /// honest about how much history the average is built on.
    func weeklyAverages() throws -> (avgCalories: Double, avgProtein: Double, avgCarbs: Double, avgFat: Double, trackedDays: Int) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: today)!

        let meals = try fetchMealsInRange(from: weekAgo, to: today)

        let trackedDays = Set(meals.map { calendar.startOfDay(for: $0.date) }).count
        guard trackedDays > 0 else { return (0, 0, 0, 0, 0) }

        let totals = meals.reduce((0, 0.0, 0.0, 0.0)) { result, meal in
            (
                result.0 + meal.calories,
                result.1 + meal.protein,
                result.2 + meal.carbs,
                result.3 + meal.fat
            )
        }

        let days = Double(trackedDays)
        return (
            Double(totals.0) / days,
            totals.1 / days,
            totals.2 / days,
            totals.3 / days,
            trackedDays
        )
    }

    /// Writes all meals that have never been synced to Apple Health.
    /// Best-effort — individual save failures are skipped. Returns (synced, total).
    func syncHistoricalMeals(onProgress: @escaping (Int, Int) -> Void) async -> (synced: Int, total: Int) {
        guard let meals = try? fetchAllMeals().filter({ $0.healthKitFoodUUID == nil }) else { return (0, 0) }
        let total = meals.count
        guard total > 0 else { return (0, 0) }
        var synced = 0
        for (index, meal) in meals.enumerated() {
            if let uuid = try? await HealthKitService.shared.saveMeal(meal) {
                meal.healthKitFoodUUID = uuid
                try? modelContext.save()
                synced += 1
            }
            onProgress(index + 1, total)
        }
        return (synced, total)
    }

    /// Daily calorie totals over the trailing `days`. A day with no logged meals is `nil`
    /// (untracked), not `0` — callers must not read a missing day as a zero-calorie day.
    func dailyCaloriesForRange(days: Int) throws -> [(date: Date, calories: Int?)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: today)!
        let end = calendar.date(byAdding: .day, value: 1, to: today)!

        // One fetch for the whole window, bucketed by day (was one fetch per day).
        var caloriesByDay: [Date: Int] = [:]
        for meal in try fetchMealsInRange(from: start, to: end) {
            caloriesByDay[calendar.startOfDay(for: meal.date), default: 0] += meal.calories
        }

        return (0..<days).reversed().map { dayOffset in
            let date = calendar.date(byAdding: .day, value: -dayOffset, to: today)!
            return (date, caloriesByDay[date])
        }
    }
}
