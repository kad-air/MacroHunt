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
                    .padding(.bottom, 80)
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
            .alert("Delete Failed", isPresented: Binding(
                get: { deleteError != nil },
                set: { if !$0 { deleteError = nil } }
            )) {
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

                    MacroRingView(value: totalProtein, goal: Double(credentials.proteinGoal), color: .red, label: "Protein", unit: "g")
                    MacroRingView(value: totalCarbs, goal: Double(credentials.carbsGoal), color: .blue, label: "Carbs", unit: "g")
                    MacroRingView(value: totalFat, goal: Double(credentials.fatGoal), color: .yellow, label: "Fat", unit: "g")
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

            List {
                ForEach(todayMeals) { meal in
                    MealCard(meal: meal)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteMeal(meal)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDisabled(true)
            .frame(minHeight: CGFloat(todayMeals.count) * 130)
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
        Task {
            do {
                let repository = MealRepository(modelContext: modelContext, credentials: credentials)
                try await repository.deleteMealWithSync(meal)
            } catch {
                await MainActor.run {
                    deleteError = error.localizedDescription
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
