// Views/Trends/MacroCharts.swift
import SwiftUI
import Charts

// MARK: - Smoothing

/// Centered simple moving average over an ordered series — smooths day-to-day (or
/// bucket-to-bucket) spikes into a trend line. Centered rather than trailing so the smoothed
/// line sits *over* the raw data instead of lagging behind it; the window shrinks at the ends
/// where it can't be fully filled.
func centeredMovingAverage(_ values: [Double], window: Int) -> [Double] {
    guard window > 1, values.count >= 2 else { return values }
    let half = window / 2
    return values.indices.map { index in
        let lower = max(0, index - half)
        let upper = min(values.count - 1, index + half)
        let slice = values[lower...upper]
        return slice.reduce(0, +) / Double(slice.count)
    }
}

// MARK: - Calorie Trend Chart

struct CalorieTrendChart: View {
    let data: [(date: Date, calories: Int)]
    let goal: Int

    private var isWeekView: Bool {
        data.count <= 7
    }

    /// Show the smoothing line only once there's enough history for it to mean something —
    /// below this a "trend" over 2–3 points is just the raw line with a lag.
    private var showMovingAverage: Bool {
        data.count >= 4
    }

    /// Centered moving-average window. Tighter for the 7-day view (a 3-day window still reads
    /// as daily), wider for the month so the week-to-week trend comes through.
    private var movingAverageWindow: Int {
        isWeekView ? 3 : 7
    }

    /// Centered simple moving average of the daily calories — smooths the day-to-day spikes
    /// into a trend line. Centered (not trailing) so the smoothed line sits over the raw data
    /// instead of lagging behind it; the window shrinks at the ends where it can't be filled.
    private var movingAverageData: [(date: Date, value: Double)] {
        guard showMovingAverage else { return [] }
        let averaged = centeredMovingAverage(data.map { Double($0.calories) }, window: movingAverageWindow)
        return zip(data, averaged).map { (date: $0.date, value: $1) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart {
                // Goal line
                RuleMark(y: .value("Goal", goal))
                    .foregroundStyle(Theme.accent.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))

                // Raw daily line. Recedes to a thin, faded line with dots when the moving
                // average is shown, so the smoothed trend reads as the headline.
                ForEach(data, id: \.date) { item in
                    LineMark(
                        x: .value("Date", item.date, unit: .day),
                        y: .value("Calories", item.calories),
                        series: .value("Series", "Daily")
                    )
                    .foregroundStyle(Theme.accent.opacity(showMovingAverage ? 0.35 : 1))
                    .lineStyle(StrokeStyle(lineWidth: showMovingAverage ? 1.5 : 2))
                    .symbol {
                        Circle()
                            .fill(Theme.accent.opacity(showMovingAverage ? 0.5 : 1))
                            .frame(width: showMovingAverage ? 5 : 8, height: showMovingAverage ? 5 : 8)
                    }

                    AreaMark(
                        x: .value("Date", item.date, unit: .day),
                        y: .value("Calories", item.calories)
                    )
                    .foregroundStyle(
                        .linearGradient(
                            colors: [Theme.accent.opacity(showMovingAverage ? 0.15 : 0.3),
                                     Theme.accent.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }

                // Smoothed moving-average trend line.
                if showMovingAverage {
                    ForEach(movingAverageData, id: \.date) { item in
                        LineMark(
                            x: .value("Date", item.date, unit: .day),
                            y: .value("Trend", item.value),
                            series: .value("Series", "Trend")
                        )
                        .foregroundStyle(Theme.accent)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                        .interpolationMethod(.catmullRom)
                    }
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
            // Keep the catmullRom trend-line overshoot inside the card.
            .clipped()

            if showMovingAverage {
                HStack(spacing: 16) {
                    LegendDot(color: Theme.accent.opacity(0.4), label: "Daily")
                    LegendDot(color: Theme.accent, label: "\(movingAverageWindow)-day trend")
                }
                .font(.caption2)
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
            ("Protein", protein, Theme.protein),
            ("Carbs", carbs, Theme.carbs),
            ("Fat", fat, Theme.fat)
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

// MARK: - Energy Balance Chart (Phase 2)

/// Daily calories in (logged meals) vs. calories out (active + basal energy from Health).
/// Intake is drawn as bars; expenditure as a line over the top, so a bar shorter than the
/// line reads as a deficit and taller reads as a surplus.
struct EnergyBalanceChart: View {
    let data: [(date: Date, intake: Int, expenditure: Int)]

    private var isWeekView: Bool { data.count <= 7 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart {
                ForEach(data, id: \.date) { item in
                    BarMark(
                        x: .value("Date", item.date, unit: .day),
                        y: .value("Eaten", item.intake)
                    )
                    .foregroundStyle(Theme.accent.opacity(0.85))
                    .cornerRadius(3)
                }

                ForEach(data, id: \.date) { item in
                    LineMark(
                        x: .value("Date", item.date, unit: .day),
                        y: .value("Burned", item.expenditure)
                    )
                    .foregroundStyle(Theme.ink2)
                    .interpolationMethod(.catmullRom)
                    .symbol {
                        Circle().fill(Theme.ink2).frame(width: 6, height: 6)
                    }
                }
            }
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
            .frame(height: 200)

            HStack(spacing: 16) {
                LegendDot(color: Theme.accent, label: "Eaten")
                LegendDot(color: Theme.ink2, label: "Burned")
            }
            .font(.caption2)
        }
    }
}

// MARK: - Weight Trend Chart (Phase 2)

/// Body-weight measurements over time with an optional dashed target line. Values are
/// already in the user's preferred display unit (`unitLabel`).
struct WeightTrendChart: View {
    let data: [(date: Date, value: Double)]
    let goal: Double?
    let unitLabel: String

    private var yDomain: ClosedRange<Double> {
        var values = data.map(\.value)
        if let goal { values.append(goal) }
        guard let lo = values.min(), let hi = values.max() else { return 0...1 }
        let pad = max((hi - lo) * 0.15, 1)
        return (lo - pad)...(hi + pad)
    }

    var body: some View {
        Chart {
            if let goal {
                RuleMark(y: .value("Target", goal))
                    .foregroundStyle(Theme.carbs.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
            }

            ForEach(data, id: \.date) { item in
                LineMark(
                    x: .value("Date", item.date),
                    y: .value("Weight", item.value)
                )
                .foregroundStyle(Theme.accent)
                .interpolationMethod(.catmullRom)
                .symbol {
                    Circle().fill(Theme.accent).frame(width: 6, height: 6)
                }
            }
        }
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let n = value.as(Double.self) {
                        Text("\(Int(n.rounded())) \(unitLabel)")
                    }
                }
            }
        }
    }
}

// MARK: - Legend Dot

struct LegendDot: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .foregroundStyle(Theme.ink2)
        }
    }
}

// MARK: - Sparkline (Phase 2)

/// Minimal axis-less line+area used inside metric tiles for a glanceable recent trend.
/// The full long-term chart is one tap away in `MetricTrendChart`.
struct Sparkline: View {
    let points: [Double]
    let color: Color

    private var indexed: [(index: Int, value: Double)] {
        points.enumerated().map { (index: $0.offset, value: $0.element) }
    }

    private var yDomain: ClosedRange<Double> {
        guard let lo = points.min(), let hi = points.max() else { return 0...1 }
        if lo == hi { return (lo - 1)...(hi + 1) }
        let pad = (hi - lo) * 0.2
        return (lo - pad)...(hi + pad)
    }

    var body: some View {
        Chart {
            ForEach(indexed, id: \.index) { item in
                LineMark(x: .value("i", item.index), y: .value("v", item.value))
                    .foregroundStyle(color)
                    .interpolationMethod(.catmullRom)

                AreaMark(x: .value("i", item.index), y: .value("v", item.value))
                    .foregroundStyle(.linearGradient(
                        colors: [color.opacity(0.25), color.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                    .interpolationMethod(.catmullRom)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: yDomain)
        .chartLegend(.hidden)
        // catmullRom overshoots past the data's min/max; without clipping the
        // gradient area bleeds out of the tile (Charts don't clip to frame).
        .clipped()
    }
}

// MARK: - Metric Trend Chart (Phase 2 — detail)

/// Full long-term trend for a single Health metric, shown in the tap-through detail sheet.
struct MetricTrendChart: View {
    let data: [(date: Date, value: Double)]
    let color: Color

    /// Smooth only once there are enough buckets for a trend to mean something.
    private var showMovingAverage: Bool {
        data.count >= 6
    }

    /// ~5-bucket centered window: with weekly buckets that's roughly a monthly trend, enough
    /// to cut the week-to-week noise without flattening real movement.
    private var movingAverageWindow: Int { 5 }

    private var movingAverageData: [(date: Date, value: Double)] {
        guard showMovingAverage else { return [] }
        let averaged = centeredMovingAverage(data.map(\.value), window: movingAverageWindow)
        return zip(data, averaged).map { (date: $0.date, value: $1) }
    }

    private var yDomain: ClosedRange<Double> {
        // Include the smoothed values so the trend line can't fall outside the scale.
        let values = data.map(\.value) + movingAverageData.map(\.value)
        guard let lo = values.min(), let hi = values.max() else { return 0...1 }
        if lo == hi { return (lo - 1)...(hi + 1) }
        let pad = (hi - lo) * 0.15
        return (max(0, lo - pad))...(hi + pad)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart {
                ForEach(data, id: \.date) { item in
                    LineMark(
                        x: .value("Date", item.date),
                        y: .value("Value", item.value),
                        series: .value("Series", "Raw")
                    )
                    .foregroundStyle(color.opacity(showMovingAverage ? 0.35 : 1))
                    .lineStyle(StrokeStyle(lineWidth: showMovingAverage ? 1.5 : 2))
                    .interpolationMethod(.catmullRom)

                    AreaMark(x: .value("Date", item.date), y: .value("Value", item.value))
                        .foregroundStyle(.linearGradient(
                            colors: [color.opacity(showMovingAverage ? 0.12 : 0.25), color.opacity(0.04)],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                        .interpolationMethod(.catmullRom)
                }

                // Smoothed moving-average trend line.
                if showMovingAverage {
                    ForEach(movingAverageData, id: \.date) { item in
                        LineMark(
                            x: .value("Date", item.date),
                            y: .value("Trend", item.value),
                            series: .value("Series", "Trend")
                        )
                        .foregroundStyle(color)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                        .interpolationMethod(.catmullRom)
                    }
                }
            }
            .chartYScale(domain: yDomain)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            // Keep the catmullRom area/line overshoot inside the card.
            .clipped()

            if showMovingAverage {
                HStack(spacing: 16) {
                    LegendDot(color: color.opacity(0.4), label: "Weekly")
                    LegendDot(color: color, label: "Trend")
                }
                .font(.caption2)
            }
        }
    }
}

// MARK: - Health Metric Tile (Phase 2)

/// Compact stat tile for read-in Health values (activity + cardio). Shows a value with
/// unit, an optional inline sparkline, and an optional caption (e.g. the measurement
/// date). When `tappable`, a chevron hints that the full long-term trend is one tap away.
/// Neutral by design — no "good/bad" framing, matching the app's coaching ethos.
struct HealthMetricTile: View {
    let title: String
    let value: String
    let unit: String
    let caption: String?
    let color: Color
    var trend: [Double] = []
    var tappable: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(Theme.ink2)
                .lineLimit(1)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 21, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(unit)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.ink2)
            }
            .padding(.top, 6)

            if trend.count >= 2 {
                Sparkline(points: trend, color: color)
                    .frame(height: 22)
                    .padding(.top, 8)
            }

            if let caption {
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.ink3)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.chip))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(Rectangle())
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
                StatBox(title: "Avg Calories", value: "\(Int(avgCalories))", unit: "kcal", color: Theme.accent)
                StatBox(title: "Avg Protein", value: String(format: "%.0f", avgProtein), unit: "g", color: Theme.protein)
            }
            HStack {
                StatBox(title: "Avg Carbs", value: String(format: "%.0f", avgCarbs), unit: "g", color: Theme.carbs)
                StatBox(title: "Avg Fat", value: String(format: "%.0f", avgFat), unit: "g", color: Theme.fat)
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
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(Theme.ink2)

            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                    .monospacedDigit()
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(Theme.ink2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.chip))
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
