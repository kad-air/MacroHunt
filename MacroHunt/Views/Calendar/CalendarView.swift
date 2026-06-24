// Views/Calendar/CalendarView.swift
import SwiftUI
import SwiftData

extension Date: @retroactive Identifiable {
    public var id: TimeInterval { timeIntervalSince1970 }
}

struct CalendarView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var credentials: CredentialsManager

    @Query(sort: \Meal.date) private var allMeals: [Meal]

    @State private var selectedDate = Date()
    @State private var currentMonth = Date()
    @State private var detailDate: Date?

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)
    private let weekdays = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidGlassBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        MHHeader(kicker: monthYearString(from: currentMonth), title: "Calendar")
                            .padding(.top, 8)
                            .padding(.bottom, 18)

                        calendarCard

                        SectionHeader(title: "Selected day")
                            .padding(.horizontal, 4)
                            .padding(.top, 30)
                            .padding(.bottom, 13)

                        daySummaryCard
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 110)
                }
            }
            .navigationBarHidden(true)
            .sheet(item: $detailDate) { date in
                DayDetailSheet(date: date, meals: mealsForDate(date) ?? [])
                    .environmentObject(credentials)
            }
        }
    }

    // MARK: - Calendar card

    private var calendarCard: some View {
        GlassCard {
            VStack(spacing: 14) {
                HStack {
                    monthButton(systemName: "chevron.left", delta: -1)
                    Spacer()
                    Text(monthYearString(from: currentMonth))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    monthButton(systemName: "chevron.right", delta: 1)
                }

                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(weekdays, id: \.self) { day in
                        Text(day)
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.4)
                            .foregroundStyle(Theme.ink3)
                    }
                }

                LazyVGrid(columns: columns, spacing: 5) {
                    ForEach(Array(daysInMonth().enumerated()), id: \.offset) { _, date in
                        if let date {
                            DayCell(
                                date: date,
                                calories: caloriesForDate(date),
                                goal: credentials.dailyCalorieGoal,
                                isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                                isToday: calendar.isDateInToday(date),
                                isFuture: calendar.startOfDay(for: date) > calendar.startOfDay(for: Date())
                            ) {
                                selectedDate = date
                                if let meals = mealsForDate(date), !meals.isEmpty {
                                    detailDate = date
                                }
                            }
                        } else {
                            Color.clear.frame(height: 40)
                        }
                    }
                }
            }
        }
    }

    private func monthButton(systemName: String, delta: Int) -> some View {
        Button {
            withAnimation { currentMonth = calendar.date(byAdding: .month, value: delta, to: currentMonth)! }
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Theme.chip))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Selected day summary

    @ViewBuilder
    private var daySummaryCard: some View {
        let meals = mealsForDate(selectedDate) ?? []
        GlassCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(dayString(from: selectedDate))
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.ink)
                        Text(daySubtitle(meals))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.ink2)
                    }
                    Spacer()
                    if !meals.isEmpty {
                        Button { detailDate = selectedDate } label: {
                            HStack(spacing: 5) {
                                Text("Details").font(.system(size: 13, weight: .semibold))
                                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold))
                            }
                            .foregroundStyle(Theme.accent)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if meals.isEmpty {
                    Text("No meals logged this day.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.ink3)
                        .padding(.top, 14)
                } else {
                    let total = meals.reduce(0) { $0 + $1.calories }
                    let goal = credentials.dailyCalorieGoal
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text("\(total.formatted())")
                            .font(.system(size: 30, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.ink).monospacedDigit()
                        Text(" / \(goal.formatted()) kcal")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.ink2)
                    }
                    .padding(.top, 14)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.track)
                            Capsule().fill(Theme.accent)
                                .frame(width: geo.size.width * min(goal > 0 ? CGFloat(total) / CGFloat(goal) : 0, 1))
                        }
                    }
                    .frame(height: 6)
                    .padding(.top, 13)

                    HStack(spacing: 18) {
                        macroSplit("P", meals.reduce(0.0) { $0 + $1.protein }, Theme.protein)
                        macroSplit("C", meals.reduce(0.0) { $0 + $1.carbs }, Theme.carbs)
                        macroSplit("F", meals.reduce(0.0) { $0 + $1.fat }, Theme.fat)
                    }
                    .padding(.top, 16)
                }
            }
        }
    }

    private func macroSplit(_ letter: String, _ grams: Double, _ color: Color) -> some View {
        HStack(spacing: 7) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text("\(letter) ").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink2)
            + Text("\(Int(grams))g").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink)
        }
    }

    private func daySubtitle(_ meals: [Meal]) -> String {
        let count = meals.count
        let base = count == 0 ? "No meals logged" : "\(count) meal\(count == 1 ? "" : "s") logged"
        if calendar.isDateInToday(selectedDate) { return base + " · today" }
        return base
    }

    // MARK: - Helpers

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
        let remainder = days.count % 7
        if remainder > 0 { days.append(contentsOf: Array(repeating: nil, count: 7 - remainder)) }
        return days
    }

    private func mealsForDate(_ date: Date) -> [Meal]? {
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        let meals = allMeals.filter { $0.date >= startOfDay && $0.date < endOfDay }
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

// MARK: - Day cell

private struct DayCell: View {
    let date: Date
    let calories: Int
    let goal: Int
    let isSelected: Bool
    let isToday: Bool
    let isFuture: Bool
    let action: () -> Void

    private let calendar = Calendar.current

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 14, weight: isToday ? .bold : .semibold, design: .rounded))
                    .foregroundStyle(isFuture ? Theme.ink3 : Theme.ink)
                Circle()
                    .fill(isFuture ? Color.clear : dotColor)
                    .frame(width: 6, height: 6)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(isSelected ? Theme.accentSoft : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(isToday ? Theme.accent : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
    }

    private var dotColor: Color {
        guard calories > 0, goal > 0 else { return Theme.ink3 }
        let ratio = Double(calories) / Double(goal)
        if ratio < 0.5 { return Theme.ink3 }
        if ratio < 0.8 { return Theme.carbs }
        if ratio <= 1.1 { return Theme.good }
        return Theme.accent
    }
}

#Preview {
    CalendarView()
        .environmentObject(CredentialsManager())
        .modelContainer(for: Meal.self, inMemory: true)
}
