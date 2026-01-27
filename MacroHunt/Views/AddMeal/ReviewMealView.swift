// Views/AddMeal/ReviewMealView.swift
import SwiftUI

struct ReviewMealView: View {
    @Binding var analysis: NutritionAnalysis
    @Binding var mealType: MealType
    @Binding var notes: String

    @State private var editedName: String = ""
    @State private var editedCalories: String = ""
    @State private var editedProtein: String = ""
    @State private var editedCarbs: String = ""
    @State private var editedFat: String = ""
    @State private var editedNutrients: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Meal Name
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Meal Name", icon: "fork.knife")
                TextField("Meal name", text: $editedName)
                    .font(.title3.weight(.semibold))
                    .inputFieldStyle()
            }

            // Macros Grid
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Nutritional Info", icon: "chart.pie.fill")

                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    MacroField(label: "Calories", value: $editedCalories, unit: "kcal", color: .orange)
                    MacroField(label: "Protein", value: $editedProtein, unit: "g", color: .red)
                    MacroField(label: "Carbs", value: $editedCarbs, unit: "g", color: .blue)
                    MacroField(label: "Fat", value: $editedFat, unit: "g", color: .yellow)
                }
            }

            // Key Nutrients
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Key Nutrients", icon: "leaf.fill")
                TextField("Vitamins, minerals...", text: $editedNutrients)
                    .inputFieldStyle()
            }

            // Notes
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Notes", icon: "note.text")
                TextField("Add any notes...", text: $notes, axis: .vertical)
                    .lineLimit(3...5)
                    .inputFieldStyle()
            }
        }
        .onAppear {
            editedName = analysis.mealName
            editedCalories = String(analysis.calories)
            editedProtein = String(format: "%.1f", analysis.protein)
            editedCarbs = String(format: "%.1f", analysis.carbs)
            editedFat = String(format: "%.1f", analysis.fat)
            editedNutrients = analysis.keyNutrients
        }
        .onChange(of: editedName) { _, value in
            updateAnalysis()
        }
        .onChange(of: editedCalories) { _, value in
            updateAnalysis()
        }
        .onChange(of: editedProtein) { _, value in
            updateAnalysis()
        }
        .onChange(of: editedCarbs) { _, value in
            updateAnalysis()
        }
        .onChange(of: editedFat) { _, value in
            updateAnalysis()
        }
        .onChange(of: editedNutrients) { _, value in
            updateAnalysis()
        }
    }

    private func updateAnalysis() {
        analysis = NutritionAnalysis(
            mealName: editedName,
            calories: Int(editedCalories) ?? analysis.calories,
            protein: Double(editedProtein) ?? analysis.protein,
            carbs: Double(editedCarbs) ?? analysis.carbs,
            fat: Double(editedFat) ?? analysis.fat,
            keyNutrients: editedNutrients
        )
    }
}

// MARK: - Macro Field

private struct MacroField: View {
    let label: String
    @Binding var value: String
    let unit: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)

                TextField("0", text: $value)
                    .keyboardType(.decimalPad)

                Text(unit)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(10)
            .background(Color.primary.opacity(0.05))
            .cornerRadius(10)
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var analysis = NutritionAnalysis(
            mealName: "Grilled Chicken Salad",
            calories: 450,
            protein: 35.0,
            carbs: 20.5,
            fat: 25.0,
            keyNutrients: "Vitamin A, Vitamin C, Iron"
        )
        @State private var mealType = MealType.lunch
        @State private var notes = ""

        var body: some View {
            ScrollView {
                ReviewMealView(analysis: $analysis, mealType: $mealType, notes: $notes)
                    .padding()
            }
        }
    }

    return PreviewWrapper()
}
