// Services/ReflectionContext.swift
import Foundation

/// The facts the daily reflection is written from. `ReflectionViewModel` gathers them
/// (SwiftData + HealthKit); `render()` turns them into the snapshot text Claude sees. Rendering
/// is pure and UIKit-free so `scripts/core-check.sh` can check it.
///
/// Weights are stored in kilograms but rendered in the user's unit (Apple Health's preferred
/// body-mass unit — the same source as Settings' Units row), with an explicit line telling
/// Claude which unit to use. The snapshot used to say "kg" regardless, so a pounds user's
/// reflection talked about their goal in kilograms.
struct ReflectionSnapshot {
    struct Intake {
        var calories: Double
        var protein: Double
        var carbs: Double
        var fat: Double
    }

    var calorieGoal: Int
    var proteinGoal: Int
    var carbsGoal: Int
    var fatGoal: Int
    var macroSplitName: String

    var weightUnit: WeightUnit
    /// `nil` when no weight goal is set.
    var weightGoalKg: Double?
    var weightGoalDirection: WeightGoalDirection

    var today: Intake?
    /// Averages over the days actually logged in the last 7, and how many that was.
    var weekAverages: Intake?
    var weekTrackedDays: Int?
    /// Daily calories over the last 7 days, oldest first; `nil` = untracked.
    var dailyCalories: [Int?]?

    var latestWeightKg: Double?
    var avgActiveEnergy: Double?
    var avgSteps: Double?
    var restingHeartRate: Double?
    var hrv: Double?

    /// A weight in the user's unit, one decimal: "180.0 lb".
    func weight(_ kilograms: Double) -> String {
        String(format: "%.1f %@", weightUnit.fromKilograms(kilograms), weightUnit.abbreviation)
    }

    func render() -> String {
        var lines: [String] = []

        lines.append("UNITS")
        switch weightUnit {
        case .pounds:
            lines.append("- The user measures body weight in pounds. State every weight in lb, as given here — don't convert.")
        case .kilograms:
            lines.append("- The user measures body weight in kilograms. State every weight in kg, as given here — don't convert.")
        }

        lines.append("\nGOALS")
        lines.append("- Daily calorie goal: \(calorieGoal) kcal")
        lines.append("- Macro goals: protein \(proteinGoal) g, carbs \(carbsGoal) g, fat \(fatGoal) g (\(macroSplitName) split)")
        if let weightGoalKg {
            lines.append("- Weight goal: \(weight(weightGoalKg)) (\(weightGoalDirection.displayName.lowercased()))")
        }

        if let today {
            lines.append("\nTODAY")
            lines.append("- Eaten so far: \(Int(today.calories)) kcal · P \(Int(today.protein)) g · C \(Int(today.carbs)) g · F \(Int(today.fat)) g")
        }

        if let weekTrackedDays {
            lines.append("\nLAST 7 DAYS")
            if weekTrackedDays > 0, let week = weekAverages {
                lines.append("- Logged \(weekTrackedDays) of the last 7 days")
                lines.append("- Averages over the days they logged: \(Int(week.calories)) kcal/day · P \(Int(week.protein)) g · C \(Int(week.carbs)) g · F \(Int(week.fat)) g")
            } else {
                lines.append("- No meals logged in the last 7 days")
            }
        }
        if let dailyCalories {
            let series = dailyCalories.map { $0.map(String.init) ?? "untracked" }.joined(separator: ", ")
            lines.append("- Daily calories (oldest→newest): \(series)")
            lines.append("- Note: \"untracked\" means no meal was logged that day — the user simply didn't track it, not that they fasted or ate at a deficit. Don't read untracked days as low-calorie days, and don't scold missed logging.")
        }

        var health: [String] = []
        if let latestWeightKg {
            health.append("- Latest weight: \(weight(latestWeightKg))")
        }
        if let avgActiveEnergy {
            health.append("- Avg active energy: \(Int(avgActiveEnergy)) kcal/day")
        }
        if let avgSteps {
            health.append("- Avg steps: \(Int(avgSteps))/day")
        }
        if let restingHeartRate {
            health.append("- Resting heart rate: \(Int(restingHeartRate)) bpm")
        }
        if let hrv {
            health.append("- HRV (SDNN): \(Int(hrv)) ms")
        }
        if !health.isEmpty {
            lines.append("\nAPPLE HEALTH")
            lines.append(contentsOf: health)
        }

        return lines.joined(separator: "\n")
    }
}
