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

    @Published var isLoading = false
    @Published var hasLoadedOnce = false

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

        isLoading = false
        hasLoadedOnce = true
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
                    .padding(.vertical)
                }
            }
            .navigationBarHidden(true)
            .task(id: selectedPeriod) {
                await health.load(days: selectedPeriod.days)
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

    // MARK: - Health Sections (Phase 2)

    private var energyBalanceData: [(date: Date, intake: Int, expenditure: Int)] {
        dailyCalorieData.compactMap { day in
            let key = calendar.startOfDay(for: day.date)
            guard let expenditure = health.dailyExpenditure[key] else { return nil }
            return (date: day.date, intake: day.calories, expenditure: expenditure)
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

    private var activitySection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Activity", icon: "figure.walk")

                HStack(spacing: 12) {
                    if health.avgSteps > 0 {
                        HealthMetricTile(title: "Avg Steps", value: "\(Int(health.avgSteps.rounded()))", unit: "/day", caption: nil, color: .green)
                    }
                    if health.avgActiveEnergy > 0 {
                        HealthMetricTile(title: "Avg Active", value: "\(Int(health.avgActiveEnergy.rounded()))", unit: "kcal/day", caption: nil, color: .orange)
                    }
                    if health.workoutCount > 0 {
                        HealthMetricTile(title: "Workouts", value: "\(health.workoutCount)", unit: selectedPeriod == .week ? "this wk" : "30 days", caption: nil, color: .pink)
                    }
                }
            }
        }
    }

    private var cardioSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Cardio Vitals", icon: "heart.fill")

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    if let hr = health.restingHR {
                        HealthMetricTile(title: "Resting HR", value: "\(Int(hr.value.rounded()))", unit: "bpm", caption: asOf(hr.date), color: .red)
                    }
                    if let v = health.hrv {
                        HealthMetricTile(title: "HRV", value: "\(Int(v.value.rounded()))", unit: "ms", caption: asOf(v.date), color: .teal)
                    }
                    if let v = health.vo2Max {
                        HealthMetricTile(title: "VO₂ Max", value: String(format: "%.1f", v.value), unit: "ml/kg·min", caption: asOf(v.date), color: .indigo)
                    }
                    if let r = health.cardioRecovery {
                        HealthMetricTile(title: "Cardio Recovery", value: "\(Int(r.value.rounded()))", unit: "bpm", caption: asOf(r.date), color: .mint)
                    }
                }
            }
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
                .tint(.red)
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

#Preview {
    TrendsView()
        .environmentObject(CredentialsManager())
        .modelContainer(for: Meal.self, inMemory: true)
}
