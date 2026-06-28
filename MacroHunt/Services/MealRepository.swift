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
    /// This inverts the app's earlier "Craft-first transactional" order. The product is
    /// local/on-device with Apple Health as the real store; Craft is an optional export, not
    /// a gate, so a Craft outage or a user who never configured Craft can still log normally.
    /// (See `docs/managed-key-proxy-plan.md` for the related paid-tier direction.)
    func saveMealWithSync(_ meal: Meal) async throws {
        // 1. Authoritative write: local SwiftData. If this throws, the meal did not log and
        //    the error propagates to the caller.
        modelContext.insert(meal)
        try modelContext.save()

        // 2. Best-effort mirror: Craft Docs. Gated on the user's opt-in; never throws and
        //    never undoes the local save. The doc id is persisted as soon as the item is
        //    created so a later delete can still clean Craft up even if the content upload
        //    (photos/notes) fails.
        if credentials.craftSyncActive {
            let craftAPI = CraftAPI(token: credentials.craftToken, spaceId: credentials.spaceId)
            do {
                let docId = try await craftAPI.createMealItem(
                    collectionId: credentials.collectionId,
                    meal: meal
                )
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

        // 3. Best-effort mirror: Apple Health. Same contract — gated, never throws.
        if credentials.healthKitSyncEnabled {
            if let hkUUID = try? await HealthKitService.shared.saveMeal(meal) {
                meal.healthKitFoodUUID = hkUUID
                try? modelContext.save()
            }
        }
    }

    // MARK: - Combined Delete (local-first)

    /// Deletes a meal **local-first**: the best-effort mirrors (Craft, Apple Health) are
    /// removed first — while their identifiers are still on the meal — then the authoritative
    /// local delete runs. Mirror removals never throw; only the local delete can fail the
    /// operation. A failed mirror cleanup leaves an orphan in Craft/Health but never blocks
    /// removing the meal the user asked to delete.
    func deleteMealWithSync(_ meal: Meal) async throws {
        // 1. Best-effort: remove the Craft mirror if it was synced. Never throws.
        if credentials.craftSyncActive, let craftDocId = meal.craftDocId {
            let craftAPI = CraftAPI(token: credentials.craftToken, spaceId: credentials.spaceId)
            try? await craftAPI.deleteMealItem(collectionId: credentials.collectionId, itemId: craftDocId)
        }

        // 2. Best-effort: remove the Apple Health mirror while the UUID is available. Never throws.
        if credentials.healthKitSyncEnabled, let hkUUID = meal.healthKitFoodUUID {
            try? await HealthKitService.shared.deleteMeal(healthKitFoodUUID: hkUUID)
        }

        // 3. Authoritative: local delete. If this throws, the meal is still logged.
        modelContext.delete(meal)
        try modelContext.save()
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

        var results: [(Date, Int?)] = []

        for dayOffset in (0..<days).reversed() {
            let date = calendar.date(byAdding: .day, value: -dayOffset, to: today)!
            let meals = try fetchMealsForDate(date)
            let calories = meals.isEmpty ? nil : meals.reduce(0) { $0 + $1.calories }
            results.append((date, calories))
        }

        return results
    }
}
