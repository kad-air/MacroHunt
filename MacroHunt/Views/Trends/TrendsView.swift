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

// MARK: - Health Metric Identity (Phase 2)

/// Identifies a read-in Health metric and carries its display metadata + value
/// formatting, so tiles and the tap-through detail sheet stay in sync. The view-model maps
/// each case to the right `HealthKitService` series call.
enum HealthMetricID: String, CaseIterable, Identifiable {
    case steps, activeEnergy, workouts, restingHR, hrv, vo2Max, cardioRecovery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .steps: return "Steps"
        case .activeEnergy: return "Active Energy"
        case .workouts: return "Workouts"
        case .restingHR: return "Resting HR"
        case .hrv: return "HRV"
        case .vo2Max: return "VO₂ Max"
        case .cardioRecovery: return "Cardio Recovery"
        }
    }

    var color: Color {
        switch self {
        case .steps: return Theme.carbs
        case .activeEnergy: return Theme.accent
        case .workouts: return Theme.protein
        case .restingHR: return Theme.protein
        case .hrv: return Theme.carbs
        case .vo2Max: return Theme.fat
        case .cardioRecovery: return Theme.accent
        }
    }

    /// Unit shown on the detail-chart values (matches the bucket aggregation below).
    var detailUnit: String {
        switch self {
        case .steps: return "steps/wk"
        case .activeEnergy: return "kcal/wk"
        case .workouts: return "/wk"
        case .restingHR, .cardioRecovery: return "bpm"
        case .hrv: return "ms"
        case .vo2Max: return "ml/kg·min"
        }
    }

    /// Describes how the detail buckets are aggregated, shown as a chart subtitle.
    var bucketSubtitle: String {
        switch self {
        case .steps, .activeEnergy: return "Weekly totals"
        case .workouts: return "Workouts per week"
        default: return "Weekly average"
        }
    }

    func format(_ value: Double) -> String {
        switch self {
        case .vo2Max:
            return String(format: "%.1f", value)
        case .steps, .activeEnergy:
            return value.formatted(.number.precision(.fractionLength(0)).grouping(.automatic))
        default:
            return "\(Int(value.rounded()))"
        }
    }
}

// MARK: - Trend Range (detail sheet)

enum TrendRange: String, CaseIterable, Identifiable {
    case threeMonths, sixMonths, year

    var id: String { rawValue }

    var label: String {
        switch self {
        case .threeMonths: return "3M"
        case .sixMonths: return "6M"
        case .year: return "1Y"
        }
    }

    var days: Int {
        switch self {
        case .threeMonths: return 90
        case .sixMonths: return 180
        case .year: return 365
        }
    }
}

// MARK: - Health Trends View Model (Phase 2)

/// Loads the read-in Apple Health data that backs the Trends Health sections. All queries
/// are best-effort: a denied or empty read just leaves the corresponding value
/// nil/empty, and the view degrades gracefully (HealthKit hides read-auth status, so we
/// infer "not connected" from "no data at all").
@MainActor
final class HealthTrendsViewModel: ObservableObject {
    @Published var weightUnit: WeightUnit = .kilograms
    @Published var weightSeries: [(date: Date, value: Double)] = []   // in display unit
    @Published var latestWeightKg: Double?

    @Published var dailyExpenditure: [Date: Int] = [:]                // startOfDay -> kcal (active + basal)
    @Published var avgActiveEnergy: Double = 0
    @Published var avgSteps: Double = 0
    @Published var workoutCount: Int = 0

    @Published var restingHR: (date: Date, value: Double)?
    @Published var hrv: (date: Date, value: Double)?
    @Published var vo2Max: (date: Date, value: Double)?
    @Published var cardioRecovery: (date: Date, value: Double)?

    /// Inline glance sparklines per metric (recent weekly buckets). The full long-term
    /// trend is loaded on demand by the detail sheet via `series(for:days:intervalDays:)`.
    @Published var sparklines: [HealthMetricID: [Double]] = [:]

    @Published var isLoading = false
    @Published var hasLoadedOnce = false

    /// Window for the inline tile sparklines (≈12 weeks of weekly buckets).
    private let sparklineDays = 84

    var hasWeightData: Bool { !weightSeries.isEmpty }
    var hasEnergyData: Bool { !dailyExpenditure.isEmpty }
    var hasActivityData: Bool { avgSteps > 0 || avgActiveEnergy > 0 || workoutCount > 0 }
    var hasCardioData: Bool { restingHR != nil || hrv != nil || vo2Max != nil || cardioRecovery != nil }
    var hasAnyData: Bool { hasWeightData || hasEnergyData || hasActivityData || hasCardioData }

    func load(days: Int) async {
        let hk = HealthKitService.shared
        guard hk.isHealthDataAvailable else { hasLoadedOnce = true; return }
        isLoading = true

        async let unitTask = hk.preferredWeightUnit()
        async let weightTask = hk.bodyMassSeries(days: days)
        async let latestWeightTask = hk.latestBodyMass()
        async let activeTask = hk.dailyActiveEnergy(days: days)
        async let basalTask = hk.dailyBasalEnergy(days: days)
        async let stepsTask = hk.dailySteps(days: days)
        async let workoutsTask = hk.workoutCount(days: days)
        async let restingTask = hk.latestRestingHeartRate()
        async let hrvTask = hk.latestHRV()
        async let vo2Task = hk.latestVO2Max()
        async let recoveryTask = hk.latestCardioRecovery()

        // Inline sparklines (fixed recent window, weekly buckets) — independent of the toggle.
        async let sparkStepsTask = hk.stepsSeries(days: sparklineDays, intervalDays: 7)
        async let sparkActiveTask = hk.activeEnergySeries(days: sparklineDays, intervalDays: 7)
        async let sparkWorkoutsTask = hk.workoutCountsSeries(days: sparklineDays, intervalDays: 7)
        async let sparkRestingTask = hk.restingHeartRateSeries(days: sparklineDays, intervalDays: 7)
        async let sparkHrvTask = hk.hrvSeries(days: sparklineDays, intervalDays: 7)
        async let sparkVo2Task = hk.vo2MaxSeries(days: sparklineDays, intervalDays: 7)
        async let sparkRecoveryTask = hk.cardioRecoverySeries(days: sparklineDays, intervalDays: 7)

        let unit = await unitTask
        let samples = await weightTask
        let active = await activeTask
        let basal = await basalTask
        let steps = await stepsTask

        let calendar = Calendar.current
        var expenditure: [Date: Int] = [:]
        for point in active { expenditure[calendar.startOfDay(for: point.date), default: 0] += Int(point.value.rounded()) }
        for point in basal { expenditure[calendar.startOfDay(for: point.date), default: 0] += Int(point.value.rounded()) }

        let latestWeight = await latestWeightTask

        weightUnit = unit
        weightSeries = samples.map { (date: $0.date, value: unit.fromKilograms($0.kilograms)) }
        latestWeightKg = latestWeight?.kilograms
        dailyExpenditure = expenditure
        avgActiveEnergy = active.isEmpty ? 0 : active.map(\.value).reduce(0, +) / Double(active.count)
        avgSteps = steps.isEmpty ? 0 : steps.map(\.value).reduce(0, +) / Double(steps.count)
        workoutCount = await workoutsTask
        restingHR = await restingTask
        hrv = await hrvTask
        vo2Max = await vo2Task
        cardioRecovery = await recoveryTask

        sparklines = [
            .steps: (await sparkStepsTask).map(\.value),
            .activeEnergy: (await sparkActiveTask).map(\.value),
            .workouts: (await sparkWorkoutsTask).map(\.value),
            .restingHR: (await sparkRestingTask).map(\.value),
            .hrv: (await sparkHrvTask).map(\.value),
            .vo2Max: (await sparkVo2Task).map(\.value),
            .cardioRecovery: (await sparkRecoveryTask).map(\.value)
        ]

        isLoading = false
        hasLoadedOnce = true
    }

    /// Long-term series for the tap-through detail sheet. Switches over the metric so the
    /// view layer never touches HealthKit types. Weekly buckets keep long ranges readable.
    func series(for metric: HealthMetricID, days: Int, intervalDays: Int) async -> [(date: Date, value: Double)] {
        let hk = HealthKitService.shared
        switch metric {
        case .steps: return await hk.stepsSeries(days: days, intervalDays: intervalDays)
        case .activeEnergy: return await hk.activeEnergySeries(days: days, intervalDays: intervalDays)
        case .workouts: return await hk.workoutCountsSeries(days: days, intervalDays: intervalDays)
        case .restingHR: return await hk.restingHeartRateSeries(days: days, intervalDays: intervalDays)
        case .hrv: return await hk.hrvSeries(days: days, intervalDays: intervalDays)
        case .vo2Max: return await hk.vo2MaxSeries(days: days, intervalDays: intervalDays)
        case .cardioRecovery: return await hk.cardioRecoverySeries(days: days, intervalDays: intervalDays)
        }
    }
}

struct TrendsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var credentials: CredentialsManager

    @Query(sort: \Meal.date, order: .reverse) private var allMeals: [Meal]

    @StateObject private var health = HealthTrendsViewModel()

    @State private var selectedPeriod: TimePeriod = .week
    @State private var isConnecting = false
    @State private var connectMessage: String?
    @State private var selectedMetric: HealthMetricID?

    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidGlassBackground()
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        MHHeader(kicker: selectedPeriod == .week ? "Last 7 days" : "Last 30 days", title: "Trends")
                            .padding(.horizontal)

                        // Period Selector
                        SegmentedToggle(
                            options: TimePeriod.allCases.map { $0.rawValue },
                            selection: Binding(
                                get: { selectedPeriod.rawValue },
                                set: { raw in if let p = TimePeriod(rawValue: raw) { selectedPeriod = p } }
                            )
                        )
                        .padding(.horizontal)

                        // Meal-based calorie trend
                        if !filteredMeals.isEmpty {
                            calorieTrendSection
                                .padding(.horizontal)
                        }

                        // Health: calories in vs. out
                        if health.hasEnergyData {
                            energyBalanceSection
                                .padding(.horizontal)
                        }

                        // Meal-based macro sections
                        if !filteredMeals.isEmpty {
                            macroBreakdownSection
                                .padding(.horizontal)

                            averagesSection
                                .padding(.horizontal)
                        }

                        // Health: weight vs. target
                        if health.hasWeightData || credentials.hasWeightGoal {
                            weightSection
                                .padding(.horizontal)
                        }

                        // Health: activity + cardio
                        if health.hasActivityData {
                            activitySection
                                .padding(.horizontal)
                        }
                        if health.hasCardioData {
                            cardioSection
                                .padding(.horizontal)
                        }

                        // Nothing to show yet
                        if filteredMeals.isEmpty && !health.hasAnyData && !showConnectCTA {
                            emptyState
                        }

                        // Invite to connect Apple Health (available but no data read yet)
                        if showConnectCTA {
                            connectHealthCard
                                .padding(.horizontal)
                        }
                    }
                    .padding(.top)
                    .padding(.bottom, 110)
                }
            }
            .navigationBarHidden(true)
            .task(id: selectedPeriod) {
                await health.load(days: selectedPeriod.days)
            }
            .sheet(item: $selectedMetric) { metric in
                HealthMetricDetailView(metric: metric, health: health)
            }
        }
    }

    /// Apple Health is on the device, we've finished a load, and nothing came back — i.e.
    /// the user hasn't granted reads yet (or genuinely has no data). Drives the Connect CTA.
    private var showConnectCTA: Bool {
        HealthKitService.shared.isHealthDataAvailable && health.hasLoadedOnce && !health.hasAnyData
    }

    // MARK: - Filtered Data

    private var filteredMeals: [Meal] {
        let today = calendar.startOfDay(for: Date())
        // Window covers today plus the prior (days - 1) days, matching the
        // calorie trend chart's (0..<days) range. Using -days here would pull
        // in an extra day, inflating the macro breakdown and daily averages.
        let startDate = calendar.date(byAdding: .day, value: -(selectedPeriod.days - 1), to: today)!

        return allMeals.filter { meal in
            meal.date >= startDate
        }
    }

    /// Per-day calories across the selected window. A day with no logged meals is `nil`
    /// (untracked) rather than `0`, so the chart and energy balance don't read an untracked
    /// day as a zero-calorie / huge-deficit day.
    private var dailyCalorieData: [(date: Date, calories: Int?)] {
        let today = calendar.startOfDay(for: Date())
        var result: [(Date, Int?)] = []

        for dayOffset in (0..<selectedPeriod.days).reversed() {
            let date = calendar.date(byAdding: .day, value: -dayOffset, to: today)!
            let dayMeals = filteredMeals.filter { calendar.isDate($0.date, inSameDayAs: date) }
            result.append((date, dayMeals.isEmpty ? nil : dayMeals.reduce(0) { $0 + $1.calories }))
        }

        return result
    }

    /// Only the days that were actually tracked — what the calorie line should plot. Plotting
    /// untracked days as zeros would draw a misleading crash to the axis on days the user
    /// simply didn't log.
    private var trackedCalorieData: [(date: Date, calories: Int)] {
        dailyCalorieData.compactMap { day in day.calories.map { (day.date, $0) } }
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

                CalorieTrendChart(data: trackedCalorieData, goal: credentials.dailyCalorieGoal)
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

    private var trackedDayCount: Int {
        Set(filteredMeals.map { calendar.startOfDay(for: $0.date) }).count
    }

    private var averagesSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Daily Averages", icon: "function")

                let avg = averages
                let days = trackedDayCount

                DailyAverageStats(
                    avgCalories: avg.calories,
                    avgProtein: avg.protein,
                    avgCarbs: avg.carbs,
                    avgFat: avg.fat
                )

                // Be honest about how little history this average is built on — over only the
                // days actually logged, not the whole period.
                Text("Averaged over \(days) logged day\(days == 1 ? "" : "s") in the last \(selectedPeriod.days)")
                    .font(.caption)
                    .foregroundStyle(Theme.ink3)
            }
        }
    }

    // MARK: - Health Sections (Phase 2)

    private var energyBalanceData: [(date: Date, intake: Int, expenditure: Int)] {
        dailyCalorieData.compactMap { day in
            // Skip untracked days: pairing a nil/zero intake against real expenditure would
            // invent a full-day deficit on a day the user just didn't log.
            guard let intake = day.calories else { return nil }
            let key = calendar.startOfDay(for: day.date)
            guard let expenditure = health.dailyExpenditure[key] else { return nil }
            return (date: day.date, intake: intake, expenditure: expenditure)
        }
    }

    private var avgEnergyBalance: Int? {
        let data = energyBalanceData
        guard !data.isEmpty else { return nil }
        let net = data.reduce(0) { $0 + ($1.intake - $1.expenditure) }
        return net / data.count
    }

    private var energyBalanceSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Energy Balance", icon: "flame.fill")

                EnergyBalanceChart(data: energyBalanceData)

                if let net = avgEnergyBalance {
                    Text(energyBalanceSummary(net: net))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func energyBalanceSummary(net: Int) -> String {
        guard net != 0 else { return "On average, what you eat and burn is about even." }
        let direction = net < 0 ? "below" : "above"
        return "On average you eat \(abs(net)) kcal/day \(direction) what you burn."
    }

    private var weightGoalDisplay: Double? {
        credentials.hasWeightGoal ? health.weightUnit.fromKilograms(credentials.weightGoalKg) : nil
    }

    private var weightSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Weight", icon: "scalemass.fill")

                HStack(spacing: 12) {
                    if let kg = health.latestWeightKg {
                        HealthMetricTile(
                            title: "Current",
                            value: "\(Int(health.weightUnit.fromKilograms(kg).rounded()))",
                            unit: health.weightUnit.abbreviation,
                            caption: nil,
                            color: .purple
                        )
                    }
                    if let goal = weightGoalDisplay {
                        HealthMetricTile(
                            title: "Target",
                            value: "\(Int(goal.rounded()))",
                            unit: health.weightUnit.abbreviation,
                            caption: credentials.weightGoalDirection.displayName,
                            color: .blue
                        )
                    }
                }

                if health.hasWeightData {
                    WeightTrendChart(
                        data: health.weightSeries,
                        goal: weightGoalDisplay,
                        unitLabel: health.weightUnit.abbreviation
                    )
                    .frame(height: 200)
                } else {
                    Text("No weigh-ins in this period. Record your weight in the Health app to see your trend here.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                }
            }
        }
    }

    private let metricColumns = [GridItem(.flexible()), GridItem(.flexible())]

    private var activitySection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Activity", icon: "figure.walk")

                LazyVGrid(columns: metricColumns, spacing: 12) {
                    if health.avgSteps > 0 {
                        metricTile(.steps, value: "\(Int(health.avgSteps.rounded()))", unit: "/day", caption: nil)
                    }
                    if health.avgActiveEnergy > 0 {
                        metricTile(.activeEnergy, value: "\(Int(health.avgActiveEnergy.rounded()))", unit: "kcal/day", caption: nil)
                    }
                    if health.workoutCount > 0 {
                        metricTile(.workouts, value: "\(health.workoutCount)", unit: selectedPeriod == .week ? "this wk" : "30 days", caption: nil)
                    }
                }
            }
        }
    }

    private var cardioSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Cardio Vitals", icon: "heart.fill")

                LazyVGrid(columns: metricColumns, spacing: 12) {
                    if let hr = health.restingHR {
                        metricTile(.restingHR, value: "\(Int(hr.value.rounded()))", unit: "bpm", caption: asOf(hr.date))
                    }
                    if let v = health.hrv {
                        metricTile(.hrv, value: "\(Int(v.value.rounded()))", unit: "ms", caption: asOf(v.date))
                    }
                    if let v = health.vo2Max {
                        metricTile(.vo2Max, value: String(format: "%.1f", v.value), unit: "ml/kg·min", caption: asOf(v.date))
                    }
                    if let r = health.cardioRecovery {
                        metricTile(.cardioRecovery, value: "\(Int(r.value.rounded()))", unit: "bpm", caption: asOf(r.date))
                    }
                }
            }
        }
    }

    /// A tappable metric tile: headline value + inline sparkline, opening the long-term
    /// detail sheet on tap. Title/color come from the metric so the tile and sheet match.
    private func metricTile(_ metric: HealthMetricID, value: String, unit: String, caption: String?) -> some View {
        Button {
            selectedMetric = metric
        } label: {
            HealthMetricTile(
                title: tileTitle(metric),
                value: value,
                unit: unit,
                caption: caption,
                color: metric.color,
                trend: health.sparklines[metric] ?? [],
                tappable: true
            )
        }
        .buttonStyle(.plain)
    }

    /// Tile headers use short "Avg …" labels for the period-averaged activity stats; the
    /// detail sheet uses the metric's full name.
    private func tileTitle(_ metric: HealthMetricID) -> String {
        switch metric {
        case .steps: return "Avg Steps"
        case .activeEnergy: return "Avg Active"
        default: return metric.title
        }
    }

    private func asOf(_ date: Date) -> String {
        "as of " + date.formatted(.dateTime.month(.abbreviated).day())
    }

    // MARK: - Connect Apple Health

    private var connectHealthCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Apple Health", icon: "heart.text.square")

                Text("Connect Apple Health to see your weight, activity, and cardio trends alongside what you eat.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Button {
                    connectHealth()
                } label: {
                    HStack {
                        if isConnecting {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "heart.fill")
                        }
                        Text("Connect Apple Health")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(isConnecting)

                if let connectMessage {
                    Text(connectMessage)
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
        }
    }

    private func connectHealth() {
        isConnecting = true
        connectMessage = nil
        Task {
            do {
                try await HealthKitService.shared.requestAuthorization()
            } catch {
                connectMessage = "Couldn't connect: \(error.localizedDescription)"
            }
            await health.load(days: selectedPeriod.days)
            isConnecting = false
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

// MARK: - Health Metric Detail (Phase 2)

/// The "tap away" long-term trend for a single Health metric: a range picker (3M/6M/1Y), a
/// full trend chart, and a summary (latest / average / low / high). Loads on demand via the
/// shared view-model so it never touches HealthKit types directly.
struct HealthMetricDetailView: View {
    let metric: HealthMetricID
    @ObservedObject var health: HealthTrendsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var range: TrendRange = .sixMonths
    @State private var series: [(date: Date, value: Double)] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidGlassBackground()
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        Picker("Range", selection: $range) {
                            ForEach(TrendRange.allCases) { range in
                                Text(range.label).tag(range)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)

                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(metric.bucketSubtitle)
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                if series.count >= 2 {
                                    MetricTrendChart(data: series, color: metric.color)
                                        .frame(height: 220)
                                } else if isLoading {
                                    ProgressView()
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 50)
                                } else {
                                    Text("Not enough data in this range yet.")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 50)
                                }
                            }
                        }
                        .padding(.horizontal)

                        if !series.isEmpty {
                            summaryCard
                                .padding(.horizontal)
                        }
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle(metric.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: range) { await load() }
        }
    }

    private var summaryCard: some View {
        let values = series.map(\.value)
        let latest = values.last ?? 0
        let average = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
        let low = values.min() ?? 0
        let high = values.max() ?? 0

        return GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Summary", icon: "function")

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    HealthMetricTile(title: "Latest", value: metric.format(latest), unit: metric.detailUnit, caption: nil, color: metric.color)
                    HealthMetricTile(title: "Average", value: metric.format(average), unit: metric.detailUnit, caption: nil, color: metric.color)
                    HealthMetricTile(title: "Low", value: metric.format(low), unit: metric.detailUnit, caption: nil, color: metric.color)
                    HealthMetricTile(title: "High", value: metric.format(high), unit: metric.detailUnit, caption: nil, color: metric.color)
                }
            }
        }
    }

    private func load() async {
        isLoading = true
        series = await health.series(for: metric, days: range.days, intervalDays: 7)
        isLoading = false
    }
}

#Preview {
    TrendsView()
        .environmentObject(CredentialsManager())
        .modelContainer(for: Meal.self, inMemory: true)
}
