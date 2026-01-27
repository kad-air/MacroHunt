// Views/Trends/TrendsView.swift
import SwiftUI
import SwiftData
import Charts

enum TimePeriod: String, CaseIterable, Identifiable {
    case week = "Week"
    case month = "Month"

    var id: String { rawValue }

    var days: Int {
        switch self {
        case .week: return 7
        case .month: return 30
        }
    }
}

struct TrendsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var credentials: CredentialsManager

    @Query(sort: \Meal.date, order: .reverse) private var allMeals: [Meal]

    @State private var selectedPeriod: TimePeriod = .week

    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidGlassBackground()
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        Text("Trends")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)

                        // Period Selector
                        Picker("Time Period", selection: $selectedPeriod) {
                            ForEach(TimePeriod.allCases) { period in
                                Text(period.rawValue).tag(period)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)

                        if filteredMeals.isEmpty {
                            emptyState
                        } else {
                            // Calorie Trend
                            calorieTrendSection
                                .padding(.horizontal)

                            // Macro Breakdown
                            macroBreakdownSection
                                .padding(.horizontal)

                            // Averages
                            averagesSection
                                .padding(.horizontal)
                        }
                    }
                    .padding(.vertical)
                }
            }
            .navigationBarHidden(true)
        }
    }

    // MARK: - Filtered Data

    private var filteredMeals: [Meal] {
        let today = calendar.startOfDay(for: Date())
        let startDate = calendar.date(byAdding: .day, value: -selectedPeriod.days, to: today)!

        return allMeals.filter { meal in
            meal.date >= startDate
        }
    }

    private var dailyCalorieData: [(date: Date, calories: Int)] {
        let today = calendar.startOfDay(for: Date())
        var result: [(Date, Int)] = []

        for dayOffset in (0..<selectedPeriod.days).reversed() {
            let date = calendar.date(byAdding: .day, value: -dayOffset, to: today)!
            let dayMeals = filteredMeals.filter { calendar.isDate($0.date, inSameDayAs: date) }
            let totalCalories = dayMeals.reduce(0) { $0 + $1.calories }
            result.append((date, totalCalories))
        }

        return result
    }

    private var totalMacros: (protein: Double, carbs: Double, fat: Double) {
        filteredMeals.reduce((0.0, 0.0, 0.0)) { result, meal in
            (result.0 + meal.protein, result.1 + meal.carbs, result.2 + meal.fat)
        }
    }

    private var averages: (calories: Double, protein: Double, carbs: Double, fat: Double) {
        // Count unique days with tracked calories
        let daysWithData = Set(filteredMeals.map { calendar.startOfDay(for: $0.date) }).count
        guard daysWithData > 0 else { return (0, 0, 0, 0) }

        let days = Double(daysWithData)
        let totals = filteredMeals.reduce((0, 0.0, 0.0, 0.0)) { result, meal in
            (result.0 + meal.calories, result.1 + meal.protein, result.2 + meal.carbs, result.3 + meal.fat)
        }

        return (
            Double(totals.0) / days,
            totals.1 / days,
            totals.2 / days,
            totals.3 / days
        )
    }

    // MARK: - Sections

    private var calorieTrendSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Calorie Trend", icon: "chart.line.uptrend.xyaxis")

                CalorieTrendChart(data: dailyCalorieData, goal: credentials.dailyCalorieGoal)
                    .frame(height: 200)
            }
        }
    }

    private var macroBreakdownSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Macro Breakdown", icon: "chart.pie.fill")

                let macros = totalMacros

                if macros.protein + macros.carbs + macros.fat > 0 {
                    MacroBreakdownChart(
                        protein: macros.protein,
                        carbs: macros.carbs,
                        fat: macros.fat
                    )
                    .frame(height: 200)
                } else {
                    Text("No macro data available")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                }
            }
        }
    }

    private var averagesSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Daily Averages", icon: "function")

                let avg = averages

                DailyAverageStats(
                    avgCalories: avg.calories,
                    avgProtein: avg.protein,
                    avgCarbs: avg.carbs,
                    avgFat: avg.fat
                )
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 60))
                .foregroundColor(.secondary.opacity(0.5))

            Text("No data yet")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Start logging meals to see your trends")
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

#Preview {
    TrendsView()
        .environmentObject(CredentialsManager())
        .modelContainer(for: Meal.self, inMemory: true)
}
