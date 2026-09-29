// Views/Calendar/DayDetailSheet.swift
import SwiftUI
import SwiftData

struct DayDetailSheet: View {
    let date: Date

    /// Live query for just this day, so deletes made from the sheet update it immediately.
    @Query private var meals: [Meal]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var credentials: CredentialsManager
    @State private var deleteError: String?

    init(date: Date) {
        self.date = date
        let start = Calendar.current.startOfDay(for: date)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        _meals = Query(
            filter: #Predicate<Meal> { $0.date >= start && $0.date < end },
            sort: \Meal.date
        )
    }

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
                // Title + symbol so the Duo lays it out in its vertical bar (see MainTabView).
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") {
                        dismiss()
                    }
                }
            }
        }
        // A sheet is its own presentation root and does not inherit the TabView's tint.
        .tint(Theme.accent)
        .alert("Delete Failed", isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("OK") { deleteError = nil }
        } message: {
            Text(deleteError ?? "Unknown error")
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
                            .foregroundStyle(calorieColor(totalCalories, goal: goal))
                        Text("of \(goal) kcal goal")
                            .font(.caption)
                            .foregroundStyle(Theme.ink2)
                    }
                    Spacer()
                    Text("\(meals.count)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.ink2)
                    Text(meals.count == 1 ? "meal" : "meals")
                        .font(.caption)
                        .foregroundStyle(Theme.ink2)
                }

                Divider()

                // Macros
                HStack(spacing: 24) {
                    MacroStat(label: "Protein", value: totalProtein, unit: "g", color: Theme.protein)
                    MacroStat(label: "Carbs", value: totalCarbs, unit: "g", color: Theme.carbs)
                    MacroStat(label: "Fat", value: totalFat, unit: "g", color: Theme.fat)
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
                        .contextMenu {
                            Button(role: .destructive) {
                                delete(meal)
                            } label: {
                                Label("Delete meal", systemImage: "trash")
                            }
                        }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 40))
                .foregroundStyle(Theme.ink3)

            Text("No meals logged this day")
                .font(.subheadline)
                .foregroundStyle(Theme.ink2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Helpers

    private func delete(_ meal: Meal) {
        Task {
            do {
                let repository = MealRepository(modelContext: modelContext, credentials: credentials)
                try await repository.deleteMealWithSync(meal)
            } catch {
                deleteError = error.localizedDescription
            }
        }
    }

    private func calorieColor(_ calories: Int, goal: Int) -> Color {
        guard goal > 0 else { return Theme.ink }
        let ratio = Double(calories) / Double(goal)
        if ratio < 0.8 {
            return Theme.ink
        } else if ratio <= 1.1 {
            return Theme.good
        } else {
            return Theme.accent
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
                    .foregroundStyle(Theme.ink2)
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.ink2)
        }
    }
}

#Preview {
    DayDetailSheet(date: Date())
        .environmentObject(CredentialsManager())
        .modelContainer(for: Meal.self, inMemory: true)
}
