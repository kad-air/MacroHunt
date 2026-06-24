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

    private let columns = [GridItem(.flexible(), spacing: 11), GridItem(.flexible(), spacing: 11)]

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            field("Meal name") {
                TextField("Meal name", text: $editedName)
                    .font(.system(size: 16, weight: .semibold))
                    .inputFieldStyle()
            }

            field("Nutrition · AI estimate") {
                LazyVGrid(columns: columns, spacing: 11) {
                    MacroTile(label: "Calories", value: $editedCalories, unit: "kcal")
                    MacroTile(label: "Protein", value: $editedProtein, unit: "g", color: Theme.protein)
                    MacroTile(label: "Carbs", value: $editedCarbs, unit: "g", color: Theme.carbs)
                    MacroTile(label: "Fat", value: $editedFat, unit: "g", color: Theme.fat)
                }
            }

            field("Key nutrients") {
                TextField("Vitamins, minerals…", text: $editedNutrients)
                    .inputFieldStyle()
            }

            field("Notes") {
                TextField("Add any notes…", text: $notes, axis: .vertical)
                    .lineLimit(2...4)
                    .inputFieldStyle()
            }
        }
        .onAppear {
            editedName = analysis.mealName
            editedCalories = String(analysis.calories)
            editedProtein = String(format: "%.0f", analysis.protein)
            editedCarbs = String(format: "%.0f", analysis.carbs)
            editedFat = String(format: "%.0f", analysis.fat)
            editedNutrients = analysis.keyNutrients
        }
        .onChange(of: editedName) { _, _ in updateAnalysis() }
        .onChange(of: editedCalories) { _, _ in updateAnalysis() }
        .onChange(of: editedProtein) { _, _ in updateAnalysis() }
        .onChange(of: editedCarbs) { _, _ in updateAnalysis() }
        .onChange(of: editedFat) { _, _ in updateAnalysis() }
        .onChange(of: editedNutrients) { _, _ in updateAnalysis() }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(Theme.ink2)
            content()
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

// MARK: - Macro tile (editable)

private struct MacroTile: View {
    let label: String
    @Binding var value: String
    let unit: String
    var color: Color = Theme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(Theme.ink2)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                TextField("0", text: $value)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .fixedSize()
                Text(unit)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.ink2)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.chip))
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var analysis = NutritionAnalysis(
            mealName: "Grilled Chicken Salad",
            calories: 450, protein: 35.0, carbs: 20.5, fat: 25.0,
            keyNutrients: "Vitamin A, Vitamin C, Iron"
        )
        @State private var mealType = MealType.lunch
        @State private var notes = ""
        var body: some View {
            ScrollView {
                ReviewMealView(analysis: $analysis, mealType: $mealType, notes: $notes).padding()
            }
            .background(WarmBackground())
        }
    }
    return PreviewWrapper()
}
