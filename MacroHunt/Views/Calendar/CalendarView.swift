// Views/Calendar/CalendarView.swift
import SwiftUI
import SwiftData

struct CalendarView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var credentials: CredentialsManager

    @Query(sort: \Meal.date) private var allMeals: [Meal]

    @State private var selectedDate = Date()
    @State private var currentMonth = Date()
    @State private var showingDayDetail = false
    @State private var selectedDayMeals: [Meal] = []

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible()), count: 7)
    private let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidGlassBackground()
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        Text("Calendar")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)

                        // Month Navigation
                        monthNavigation
                            .padding(.horizontal)

                        // Calendar Grid
                        calendarGrid
                            .padding(.horizontal)

                        // Selected Day Summary
                        if let meals = mealsForDate(selectedDate), !meals.isEmpty {
                            daySummary(meals: meals)
                                .padding(.horizontal)
                        }
                    }
                    .padding(.vertical)
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showingDayDetail) {
                DayDetailSheet(date: selectedDate, meals: selectedDayMeals)
            }
        }
    }

    // MARK: - Month Navigation

    private var monthNavigation: some View {
        HStack {
            Button {
                withAnimation {
                    currentMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth)!
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.semibold))
            }

            Spacer()

            Text(monthYearString(from: currentMonth))
                .font(.title2.weight(.semibold))

            Spacer()

            Button {
                withAnimation {
                    currentMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth)!
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title3.weight(.semibold))
            }
        }
        .padding()
        .glassContainer(cornerRadius: 16)
    }

    // MARK: - Calendar Grid

    private var calendarGrid: some View {
        GlassCard {
            VStack(spacing: 12) {
                // Weekday headers
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(weekdays, id: \.self) { day in
                        Text(day)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                    }
                }

                // Days grid
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(daysInMonth(), id: \.self) { date in
                        if let date = date {
                            DayCell(
                                date: date,
                                calories: caloriesForDate(date),
                                goal: credentials.dailyCalorieGoal,
                                isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                                isToday: calendar.isDateInToday(date)
                            ) {
                                selectedDate = date
                                if let meals = mealsForDate(date), !meals.isEmpty {
                                    selectedDayMeals = meals
                                    showingDayDetail = true
                                }
                            }
                        } else {
                            Color.clear
                                .frame(height: 44)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Day Summary

    private func daySummary(meals: [Meal]) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(dayString(from: selectedDate))
                        .font(.headline)
                    Spacer()
                    Text("\(meals.count) \(meals.count == 1 ? "meal" : "meals")")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                let totalCalories = meals.reduce(0) { $0 + $1.calories }

                HStack {
                    Text("\(totalCalories) kcal")
                        .font(.system(size: 24, weight: .bold, design: .rounded))

                    Spacer()

                    Button("View Details") {
                        selectedDayMeals = meals
                        showingDayDetail = true
                    }
                    .font(.subheadline)
                }
            }
        }
    }

    // MARK: - Helper Methods

    private func daysInMonth() -> [Date?] {
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: currentMonth))!
        let range = calendar.range(of: .day, in: .month, for: startOfMonth)!

        let firstWeekday = calendar.component(.weekday, from: startOfMonth)
        let leadingEmptyDays = firstWeekday - 1

        var days: [Date?] = Array(repeating: nil, count: leadingEmptyDays)

        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: startOfMonth) {
                days.append(date)
            }
        }

        // Pad to complete the last week
        let remainder = days.count % 7
        if remainder > 0 {
            days.append(contentsOf: Array(repeating: nil, count: 7 - remainder))
        }

        return days
    }

    private func mealsForDate(_ date: Date) -> [Meal]? {
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let meals = allMeals.filter { meal in
            meal.date >= startOfDay && meal.date < endOfDay
        }

        return meals.isEmpty ? nil : meals
    }

    private func caloriesForDate(_ date: Date) -> Int {
        mealsForDate(date)?.reduce(0) { $0 + $1.calories } ?? 0
    }

    private func monthYearString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }

    private func dayString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: date)
    }
}

// MARK: - Day Cell

private struct DayCell: View {
    let date: Date
    let calories: Int
    let goal: Int
    let isSelected: Bool
    let isToday: Bool
    let action: () -> Void

    private let calendar = Calendar.current

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 14, weight: isToday ? .bold : .regular))

                if calories > 0 {
                    Circle()
                        .fill(calorieIndicatorColor)
                        .frame(width: 6, height: 6)
                } else {
                    Circle()
                        .fill(Color.clear)
                        .frame(width: 6, height: 6)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isToday ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private var calorieIndicatorColor: Color {
        let ratio = Double(calories) / Double(goal)
        if ratio < 0.5 {
            return .gray
        } else if ratio < 0.8 {
            return .blue
        } else if ratio <= 1.1 {
            return .green
        } else {
            return .orange
        }
    }
}

#Preview {
    CalendarView()
        .environmentObject(CredentialsManager())
        .modelContainer(for: Meal.self, inMemory: true)
}
