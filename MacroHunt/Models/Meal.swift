// Models/Meal.swift
import Foundation
import SwiftData

// MARK: - Meal Type Enum

enum MealType: String, Codable, CaseIterable, Identifiable {
    case breakfast = "Breakfast"
    case lunch = "Lunch"
    case dinner = "Dinner"
    case snack = "Snack"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .breakfast: return "sunrise.fill"
        case .lunch: return "sun.max.fill"
        case .dinner: return "moon.fill"
        case .snack: return "carrot.fill"
        }
    }

    var color: String {
        switch self {
        case .breakfast: return "orange"
        case .lunch: return "yellow"
        case .dinner: return "purple"
        case .snack: return "green"
        }
    }
}

// MARK: - Meal Model

@Model
final class Meal {
    var id: UUID
    var name: String
    var date: Date
    var mealTypeRaw: String
    var calories: Int
    var protein: Double
    var carbs: Double
    var fat: Double
    var keyNutrients: String
    var notes: String
    @Attribute(.externalStorage) var photoData: [Data]
    var craftDocId: String?
    var createdAt: Date

    var mealType: MealType {
        get { MealType(rawValue: mealTypeRaw) ?? .snack }
        set { mealTypeRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        name: String,
        date: Date = Date(),
        mealType: MealType,
        calories: Int,
        protein: Double,
        carbs: Double,
        fat: Double,
        keyNutrients: String = "",
        notes: String = "",
        photoData: [Data] = [],
        craftDocId: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.date = date
        self.mealTypeRaw = mealType.rawValue
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.keyNutrients = keyNutrients
        self.notes = notes
        self.photoData = photoData
        self.craftDocId = craftDocId
        self.createdAt = createdAt
    }
}

// MARK: - Meal Extensions

extension Meal {
    /// Returns total macros in grams
    var totalMacros: Double {
        protein + carbs + fat
    }

    /// Returns macro percentages
    var macroPercentages: (protein: Double, carbs: Double, fat: Double) {
        let total = totalMacros
        guard total > 0 else { return (0, 0, 0) }
        return (
            protein: (protein / total) * 100,
            carbs: (carbs / total) * 100,
            fat: (fat / total) * 100
        )
    }
}

// MARK: - Nutrition Analysis Result

struct NutritionAnalysis: Codable {
    let mealName: String
    let calories: Int
    let protein: Double
    let carbs: Double
    let fat: Double
    let keyNutrients: String
}
