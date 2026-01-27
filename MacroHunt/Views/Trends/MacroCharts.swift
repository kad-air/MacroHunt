// Views/Trends/MacroCharts.swift
import SwiftUI
import Charts

// MARK: - Calorie Trend Chart

struct CalorieTrendChart: View {
    let data: [(date: Date, calories: Int)]
    let goal: Int

    private var isWeekView: Bool {
        data.count <= 7
    }

    var body: some View {
        Chart {
            // Goal line
            RuleMark(y: .value("Goal", goal))
                .foregroundStyle(.orange.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))

            // Data points
            ForEach(data, id: \.date) { item in
                LineMark(
                    x: .value("Date", item.date, unit: .day),
                    y: .value("Calories", item.calories)
                )
                .foregroundStyle(.orange)
                .symbol {
                    Circle()
                        .fill(.orange)
                        .frame(width: 8, height: 8)
                }

                AreaMark(
                    x: .value("Date", item.date, unit: .day),
                    y: .value("Calories", item.calories)
                )
                .foregroundStyle(
                    .linearGradient(
                        colors: [.orange.opacity(0.3), .orange.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
        .chartYScale(domain: 0...(max(goal, (data.map(\.calories).max() ?? 0)) + 500))
        .chartXAxis {
            if isWeekView {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                }
            } else {
                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine()
                AxisValueLabel()
            }
        }
    }
}

// MARK: - Macro Breakdown Chart

struct MacroBreakdownChart: View {
    let protein: Double
    let carbs: Double
    let fat: Double

    private var total: Double {
        protein + carbs + fat
    }

    private var data: [(name: String, value: Double, color: Color)] {
        [
            ("Protein", protein, .red),
            ("Carbs", carbs, .blue),
            ("Fat", fat, .yellow)
        ]
    }

    var body: some View {
        Chart(data, id: \.name) { item in
            SectorMark(
                angle: .value("Value", item.value),
                innerRadius: .ratio(0.5),
                angularInset: 2
            )
            .cornerRadius(4)
            .foregroundStyle(item.color)
        }
        .chartLegend(position: .bottom, spacing: 16) {
            HStack(spacing: 16) {
                ForEach(data, id: \.name) { item in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(item.color)
                            .frame(width: 8, height: 8)
                        Text(item.name)
                            .font(.caption)
                        Text("\(Int(item.value))g")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Macro Comparison Bar Chart

struct MacroComparisonChart: View {
    let currentProtein: Double
    let currentCarbs: Double
    let currentFat: Double
    let goalProtein: Double
    let goalCarbs: Double
    let goalFat: Double

    private var data: [(macro: String, current: Double, goal: Double, color: Color)] {
        [
            ("Protein", currentProtein, goalProtein, .red),
            ("Carbs", currentCarbs, goalCarbs, .blue),
            ("Fat", currentFat, goalFat, .yellow)
        ]
    }

    var body: some View {
        Chart {
            ForEach(data, id: \.macro) { item in
                BarMark(
                    x: .value("Macro", item.macro),
                    y: .value("Current", item.current)
                )
                .foregroundStyle(item.color)
                .cornerRadius(4)

                // Goal line
                RuleMark(
                    xStart: .value("Start", item.macro),
                    xEnd: .value("End", item.macro),
                    y: .value("Goal", item.goal)
                )
                .foregroundStyle(.primary.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 4]))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
    }
}

// MARK: - Daily Average Stats

struct DailyAverageStats: View {
    let avgCalories: Double
    let avgProtein: Double
    let avgCarbs: Double
    let avgFat: Double

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                StatBox(title: "Avg Calories", value: "\(Int(avgCalories))", unit: "kcal", color: .orange)
                StatBox(title: "Avg Protein", value: String(format: "%.0f", avgProtein), unit: "g", color: .red)
            }
            HStack {
                StatBox(title: "Avg Carbs", value: String(format: "%.0f", avgCarbs), unit: "g", color: .blue)
                StatBox(title: "Avg Fat", value: String(format: "%.0f", avgFat), unit: "g", color: .yellow)
            }
        }
    }
}

private struct StatBox: View {
    let title: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(color)
                Text(unit)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.primary.opacity(0.05))
        .cornerRadius(12)
    }
}

#Preview {
    VStack(spacing: 20) {
        CalorieTrendChart(
            data: [
                (Date().addingTimeInterval(-6*86400), 1800),
                (Date().addingTimeInterval(-5*86400), 2100),
                (Date().addingTimeInterval(-4*86400), 1950),
                (Date().addingTimeInterval(-3*86400), 2200),
                (Date().addingTimeInterval(-2*86400), 1750),
                (Date().addingTimeInterval(-1*86400), 2050),
                (Date(), 1900)
            ],
            goal: 2000
        )
        .frame(height: 200)

        MacroBreakdownChart(protein: 120, carbs: 200, fat: 65)
            .frame(height: 200)
    }
    .padding()
}
