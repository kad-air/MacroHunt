// Views/Calendar/DayDetailSheet.swift
import SwiftUI
import SwiftData

struct DayDetailSheet: View {
    let date: Date
    let meals: [Meal]

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var credentials: CredentialsManager

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        return formatter
    }()

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidGlassBackground()
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Summary
                        summarySection

                        // Meals
                        if meals.isEmpty {
                            emptyState
                        } else {
                            mealsSection
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle(dateFormatter.string(from: date))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Summary Section

    private var summarySection: some View {
        GlassCard {
            VStack(spacing: 12) {
                let totalCalories = meals.reduce(0) { $0 + $1.calories }
                let totalProtein = meals.reduce(0.0) { $0 + $1.protein }
                let totalCarbs = meals.reduce(0.0) { $0 + $1.carbs }
                let totalFat = meals.reduce(0.0) { $0 + $1.fat }
                let goal = credentials.dailyCalorieGoal

                // Calories
                HStack {
                    VStack(alignment: .leading) {
                        Text("\(totalCalories)")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundColor(calorieColor(totalCalories, goal: goal))
                        Text("of \(goal) kcal goal")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text("\(meals.count)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                    Text(meals.count == 1 ? "meal" : "meals")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()

                // Macros
                HStack(spacing: 24) {
                    MacroStat(label: "Protein", value: totalProtein, unit: "g", color: .red)
                    MacroStat(label: "Carbs", value: totalCarbs, unit: "g", color: .blue)
                    MacroStat(label: "Fat", value: totalFat, unit: "g", color: .yellow)
                }
            }
        }
    }

    // MARK: - Meals Section

    private var mealsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Meals")
                .font(.headline)

            VStack(spacing: 12) {
                ForEach(meals) { meal in
                    MealCard(meal: meal)
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.5))

            Text("No meals logged this day")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Helpers

    private func calorieColor(_ calories: Int, goal: Int) -> Color {
        let ratio = Double(calories) / Double(goal)
        if ratio < 0.8 {
            return .primary
        } else if ratio <= 1.1 {
            return .green
        } else {
            return .orange
        }
    }
}

// MARK: - Macro Stat

private struct MacroStat: View {
    let label: String
    let value: Double
    let unit: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(String(format: "%.0f", value))
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                Text(unit)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    DayDetailSheet(date: Date(), meals: [])
        .environmentObject(CredentialsManager())
}
