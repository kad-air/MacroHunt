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

    // MARK: - Combined Save (Transactional)

    /// Saves meal to both Craft and local DB. If Craft fails, local save is skipped.
    func saveMealWithSync(_ meal: Meal) async throws {
        // Try Craft first - if it fails, don't save locally
        if credentials.isValid {
            let craftAPI = CraftAPI(token: credentials.craftToken, spaceId: credentials.spaceId)

            // Create the meal item in Craft
            let docId = try await craftAPI.createMealItem(
                collectionId: credentials.collectionId,
                meal: meal
            )
            meal.craftDocId = docId

            // Add photos and description to the document
            if !meal.photoData.isEmpty || !meal.notes.isEmpty {
                try await craftAPI.addMealContent(documentId: docId, photoData: meal.photoData, description: meal.notes)
            }
        }

        // Craft succeeded (or was skipped), now save locally
        modelContext.insert(meal)
        try modelContext.save()
    }

    // MARK: - Combined Delete

    /// Deletes meal from both Craft and local DB.
    func deleteMealWithSync(_ meal: Meal) async throws {
        // Delete from Craft first if it exists there
        if credentials.isValid, let craftDocId = meal.craftDocId {
            let craftAPI = CraftAPI(token: credentials.craftToken, spaceId: credentials.spaceId)
            try await craftAPI.deleteMealItem(collectionId: credentials.collectionId, itemId: craftDocId)
        }

        // Delete locally
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

    func weeklyAverages() throws -> (avgCalories: Double, avgProtein: Double, avgCarbs: Double, avgFat: Double) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: today)!

        let meals = try fetchMealsInRange(from: weekAgo, to: today)

        guard !meals.isEmpty else { return (0, 0, 0, 0) }

        let totals = meals.reduce((0, 0.0, 0.0, 0.0)) { result, meal in
            (
                result.0 + meal.calories,
                result.1 + meal.protein,
                result.2 + meal.carbs,
                result.3 + meal.fat
            )
        }

        let days = 7.0
        return (
            Double(totals.0) / days,
            totals.1 / days,
            totals.2 / days,
            totals.3 / days
        )
    }

    func dailyCaloriesForRange(days: Int) throws -> [(date: Date, calories: Int)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        var results: [(Date, Int)] = []

        for dayOffset in (0..<days).reversed() {
            let date = calendar.date(byAdding: .day, value: -dayOffset, to: today)!
            let totals = try dailyTotals(for: date)
            results.append((date, totals.calories))
        }

        return results
    }
}
