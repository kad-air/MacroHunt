// Views/Today/TodayView.swift
import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var credentials: CredentialsManager

    @Query(sort: \Meal.date) private var allMeals: [Meal]

    private var todayMeals: [Meal] {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        return allMeals.filter { $0.date >= startOfToday }
    }

    @State private var showingAddMeal = false
    @State private var mealToDelete: Meal?
    @State private var isDeleting = false
    @State private var deleteError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidGlassBackground()
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Today")
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                            Text(Date(), style: .date)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)

                        // Summary Card
                        summaryCard
                            .padding(.horizontal)

                        // Meals List
                        if todayMeals.isEmpty {
                            emptyState
                        } else {
                            mealsSection
                        }
                    }
                    .padding(.vertical)
                }

                // Floating Add Button
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        addButton
                    }
                }
                .padding()
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showingAddMeal) {
                AddMealView()
            }
            .alert("Delete Meal?", isPresented: .constant(mealToDelete != nil && !isDeleting)) {
                Button("Cancel", role: .cancel) {
                    mealToDelete = nil
                }
                Button("Delete", role: .destructive) {
                    if let meal = mealToDelete {
                        deleteMeal(meal)
                    }
                }
            } message: {
                Text("This will permanently delete this meal from both your device and Craft.")
            }
            .alert("Delete Failed", isPresented: .constant(deleteError != nil)) {
                Button("OK") {
                    deleteError = nil
                }
            } message: {
                Text(deleteError ?? "Unknown error")
            }
        }
    }

    // MARK: - Summary Card

    private var summaryCard: some View {
        GlassCard {
            VStack(spacing: 16) {
                // Calorie progress
                let totalCalories = todayMeals.reduce(0) { $0 + $1.calories }
                let goal = credentials.dailyCalorieGoal

                VStack(spacing: 8) {
                    HStack {
                        Text("\(totalCalories)")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                        Text("/ \(goal) kcal")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }

                    // Progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.orange.opacity(0.2))
                                .frame(height: 12)

                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.orange)
                                .frame(width: max(0, min(goal > 0 ? CGFloat(totalCalories) / CGFloat(goal) * geometry.size.width : 0, geometry.size.width)), height: 12)
                        }
                    }
                    .frame(height: 12)
                }

                Divider()

                // Macro rings
                HStack(spacing: 20) {
                    let totalProtein = todayMeals.reduce(0.0) { $0 + $1.protein }
                    let totalCarbs = todayMeals.reduce(0.0) { $0 + $1.carbs }
                    let totalFat = todayMeals.reduce(0.0) { $0 + $1.fat }

                    MacroRingView(value: totalProtein, goal: 150, color: .red, label: "Protein", unit: "g")
                    MacroRingView(value: totalCarbs, goal: 250, color: .blue, label: "Carbs", unit: "g")
                    MacroRingView(value: totalFat, goal: 70, color: .yellow, label: "Fat", unit: "g")
                }
            }
        }
    }

    // MARK: - Meals Section

    private var mealsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Meals")
                .font(.headline)
                .padding(.horizontal)

            VStack(spacing: 12) {
                ForEach(todayMeals) { meal in
                    MealCard(meal: meal)
                        .contextMenu {
                            Button(role: .destructive) {
                                mealToDelete = meal
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "fork.knife.circle")
                .font(.system(size: 60))
                .foregroundColor(.secondary.opacity(0.5))

            Text("No meals logged yet")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Tap + to add your first meal")
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Add Button

    private var addButton: some View {
        Button {
            showingAddMeal = true
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .foregroundColor(.white)
                .frame(width: 56, height: 56)
                .background(Color.accentColor)
                .clipShape(Circle())
                .shadow(color: Color.accentColor.opacity(0.4), radius: 8, y: 4)
        }
    }

    // MARK: - Actions

    private func deleteMeal(_ meal: Meal) {
        isDeleting = true
        Task {
            do {
                let repository = MealRepository(modelContext: modelContext, credentials: credentials)
                try await repository.deleteMealWithSync(meal)
                await MainActor.run {
                    mealToDelete = nil
                    isDeleting = false
                }
            } catch {
                await MainActor.run {
                    deleteError = error.localizedDescription
                    mealToDelete = nil
                    isDeleting = false
                }
            }
        }
    }
}

#Preview {
    TodayView()
        .environmentObject(CredentialsManager())
        .modelContainer(for: Meal.self, inMemory: true)
}
