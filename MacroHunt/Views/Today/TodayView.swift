// Views/Today/TodayView.swift
import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var credentials: CredentialsManager

    @Query(sort: \Meal.date) private var allMeals: [Meal]

    /// Opens the Add-meal sheet (owned by `MainTabView`, shared with the center "+").
    var onAddMeal: () -> Void = {}

    @StateObject private var reflection = ReflectionViewModel()
    @State private var showReflection = false
    @State private var deleteError: String?

    private var todayMeals: [Meal] {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        return allMeals.filter { $0.date >= startOfToday }.sorted { $0.date < $1.date }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidGlassBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                            .padding(.top, 8)
                            .padding(.bottom, 18)

                        summaryCard

                        if credentials.dailyReflectionEnabled {
                            SectionHeader(title: "Today")
                                .padding(.horizontal, 4)
                                .padding(.top, 30)
                                .padding(.bottom, 13)
                            reflectionCard
                        }

                        SectionHeader(title: "Meals · \(todayMeals.count) logged")
                            .padding(.horizontal, 4)
                            .padding(.top, 30)
                            .padding(.bottom, 13)

                        if todayMeals.isEmpty {
                            emptyState
                        } else {
                            ForEach(todayMeals) { meal in
                                MealCard(meal: meal)
                                    .padding(.bottom, 10)
                                    .contextMenu {
                                        Button(role: .destructive) { deleteMeal(meal) } label: {
                                            Label("Delete meal", systemImage: "trash")
                                        }
                                    }
                            }
                        }

                        logNextRow
                            .padding(.top, 2)
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 110)
                }
            }
            .navigationBarHidden(true)
            .task(id: reflectionTaskKey) {
                await reflection.ensureLoaded(mealCount: todayMeals.count, modelContext: modelContext, credentials: credentials)
            }
            .sheet(isPresented: $showReflection) {
                ReflectionSheet(reflection: reflection, modelContext: modelContext, credentials: credentials, mealCount: todayMeals.count)
            }
            .alert("Delete Failed", isPresented: Binding(
                get: { deleteError != nil },
                set: { if !$0 { deleteError = nil } }
            )) {
                Button("OK") { deleteError = nil }
            } message: {
                Text(deleteError ?? "Unknown error")
            }
        }
    }

    /// Re-run the reflection check when the day rolls over, when reflections get toggled,
    /// or when the key is first added. Today's meal count nudges it to refresh after logging.
    private var reflectionTaskKey: String {
        "\(Self.dayKey(Date()))-\(credentials.dailyReflectionEnabled)-\(credentials.anthropicKey.isEmpty)-\(todayMeals.count)"
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(Date().formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.ink2)
            Text(greeting)
                .font(.system(size: 29, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 0..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    // MARK: - Summary card

    private var summaryCard: some View {
        let eaten = todayMeals.reduce(0) { $0 + $1.calories }
        let protein = todayMeals.reduce(0.0) { $0 + $1.protein }
        let carbs = todayMeals.reduce(0.0) { $0 + $1.carbs }
        let fat = todayMeals.reduce(0.0) { $0 + $1.fat }
        let goal = credentials.dailyCalorieGoal

        return GlassCard {
            VStack(spacing: 0) {
                CalorieRing(eaten: eaten, goal: goal)

                Text("\(eaten.formatted()) eaten · \(goal.formatted()) goal")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.ink3)
                    .padding(.top, 13)

                HStack(alignment: .top, spacing: 15) {
                    MacroTrack(name: "Protein", value: protein, goal: credentials.proteinGoal, color: Theme.protein)
                    MacroTrack(name: "Carbs", value: carbs, goal: credentials.carbsGoal, color: Theme.carbs)
                    MacroTrack(name: "Fat", value: fat, goal: credentials.fatGoal, color: Theme.fat)
                }
                .padding(.top, 22)
            }
        }
    }

    // MARK: - Reflection coach card

    @ViewBuilder
    private var reflectionCard: some View {
        Button {
            if reflection.current != nil { showReflection = true }
        } label: {
            CoachCardContent(state: reflection.state, hasKey: !credentials.anthropicKey.isEmpty)
        }
        .buttonStyle(.plain)
        .disabled(reflection.current == nil)
    }

    // MARK: - Meals

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "fork.knife")
                .font(.system(size: 30))
                .foregroundStyle(Theme.ink3)
            Text("No meals logged yet")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.ink2)
            Text("Tap + to log your first meal of the day")
                .font(.system(size: 13))
                .foregroundStyle(Theme.ink3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    private var logNextRow: some View {
        Button(action: onAddMeal) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .bold))
                Text(nextMealLabel)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(Theme.ink2)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Theme.hair, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            )
        }
        .buttonStyle(.plain)
    }

    private var nextMealLabel: String {
        let logged = Set(todayMeals.map { $0.mealType })
        for type in [MealType.breakfast, .lunch, .dinner] where !logged.contains(type) {
            return "Log \(type.rawValue.lowercased())"
        }
        return "Log a snack"
    }

    // MARK: - Actions

    private func deleteMeal(_ meal: Meal) {
        Task {
            do {
                let repository = MealRepository(modelContext: modelContext, credentials: credentials)
                try await repository.deleteMealWithSync(meal)
            } catch {
                await MainActor.run { deleteError = error.localizedDescription }
            }
        }
    }

    static func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}

// MARK: - Coach card content

/// The hero "Daily reflection" card on Today. Renders a soft glow, a kicker, and a one-line
/// preview that adapts to the reflection's state (loading / ready / failed / no key).
private struct CoachCardContent: View {
    let state: ReflectionViewModel.State
    let hasKey: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Soft accent glow in the corner
            Circle()
                .fill(RadialGradient(colors: [Theme.accent.opacity(0.22), .clear], center: .center, startRadius: 0, endRadius: 110))
                .frame(width: 200, height: 200)
                .offset(x: 60, y: -60)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 7) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .bold))
                    Text("Daily reflection")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.3)
                }
                .foregroundStyle(Theme.accent)

                Text(title)
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 12)

                if let preview {
                    Text(preview)
                        .font(.system(size: 13.5))
                        .foregroundStyle(Theme.ink2)
                        .lineLimit(2)
                        .padding(.top, 9)
                }

                if showCTA {
                    HStack(spacing: 5) {
                        if case .loading = state {
                            ProgressView().controlSize(.small).tint(Theme.accent)
                            Text("Reflecting on your week…")
                        } else {
                            Text(ctaText)
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold))
                        }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.top, 15)
                }
            }
        }
        .padding(22)
        .glassContainer(cornerRadius: 26)
    }

    private var title: String {
        switch state {
        case .ready(let r): return r.headline
        case .loading: return "Looking over your last few days…"
        case .failed: return "Reflection unavailable right now"
        case .idle:
            return hasKey ? "Your daily reflection will appear here" : "Add AI analysis to unlock reflections"
        }
    }

    private var preview: String? {
        switch state {
        case .ready(let r): return r.observations.first
        case .failed(let message): return message
        case .idle where !hasKey: return "Configure your Anthropic key in Settings to get a gentle daily read on your trends."
        default: return nil
        }
    }

    private var showCTA: Bool {
        switch state {
        case .ready, .loading: return true
        default: return false
        }
    }

    private var ctaText: String { "Read the full reflection" }
}

// MARK: - Reflection view model

/// Owns generating + caching the daily reflection. Best-effort: a denied key or empty data
/// just leaves the card in an idle/failed state — it never blocks the rest of Today.
@MainActor
final class ReflectionViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case ready(CoachingReflection)
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    private var loadedDay: String?
    /// The number of meals logged today that the current reflection reflects. When a meal is
    /// added (or removed), this no longer matches and the reflection regenerates.
    private var loadedMealCount: Int?

    var current: CoachingReflection? {
        if case .ready(let r) = state { return r }
        return nil
    }

    private static let cacheDayKey = "reflection.cache.day"
    private static let cacheJSONKey = "reflection.cache.json"
    private static let cacheMealCountKey = "reflection.cache.mealCount"

    /// Loads today's reflection: from the in-memory/disk cache when it still matches today's
    /// meal count, otherwise generates a fresh one (only when reflections are on and a key is
    /// configured). Called from a `.task(id:)` keyed on the meal count, so logging a meal
    /// re-fires this asynchronously and triggers a regenerate without blocking the add flow.
    func ensureLoaded(mealCount: Int, modelContext: ModelContext, credentials: CredentialsManager) async {
        guard credentials.dailyReflectionEnabled else {
            state = .idle
            return
        }
        let today = TodayView.dayKey(Date())

        // Already have today's in this session, and it reflects the current meals.
        if loadedDay == today, loadedMealCount == mealCount, case .ready = state { return }

        // Disk cache for today (survives relaunch, avoids re-billing the API) — only reusable
        // while the logged-meal count is unchanged.
        if let cached = Self.readCache(forDay: today, mealCount: mealCount) {
            loadedDay = today
            loadedMealCount = mealCount
            state = .ready(cached)
            return
        }

        guard !credentials.anthropicKey.isEmpty else {
            state = .idle
            return
        }
        await generate(force: false, mealCount: mealCount, modelContext: modelContext, credentials: credentials)
    }

    /// Generates a new reflection. `force` bypasses the "already loading" guard for the
    /// Regenerate button. `mealCount` is the number of meals logged today that this reflection
    /// will reflect, so the cache can be invalidated when it next changes.
    func generate(force: Bool, mealCount: Int, modelContext: ModelContext, credentials: CredentialsManager) async {
        guard !credentials.anthropicKey.isEmpty else {
            state = .idle
            return
        }
        if case .loading = state, !force { return }

        state = .loading
        let context = await buildContext(modelContext: modelContext, credentials: credentials)
        do {
            let client = ClaudeAPI(apiKey: credentials.anthropicKey)
            let result = try await client.generateReflection(context: context)
            let today = TodayView.dayKey(Date())
            loadedDay = today
            loadedMealCount = mealCount
            Self.writeCache(result, forDay: today, mealCount: mealCount)
            state = .ready(result)
        } catch {
            state = .failed(friendly(error))
        }
    }

    private func friendly(_ error: Error) -> String {
        if let apiError = error as? APIError { return apiError.localizedDescription }
        return error.localizedDescription
    }

    // MARK: Context snapshot

    private func buildContext(modelContext: ModelContext, credentials: CredentialsManager) async -> String {
        let repo = MealRepository(modelContext: modelContext, credentials: credentials)
        var lines: [String] = []

        // Goals
        lines.append("GOALS")
        lines.append("- Daily calorie goal: \(credentials.dailyCalorieGoal) kcal")
        lines.append("- Macro goals: protein \(credentials.proteinGoal) g, carbs \(credentials.carbsGoal) g, fat \(credentials.fatGoal) g (\(credentials.macroSplit.displayName) split)")
        if credentials.hasWeightGoal {
            lines.append("- Weight goal: \(String(format: "%.1f", credentials.weightGoalKg)) kg (\(credentials.weightGoalDirection.displayName.lowercased()))")
        }

        // Today + week intake
        if let today = try? repo.dailyTotals(for: Date()) {
            lines.append("\nTODAY")
            lines.append("- Eaten so far: \(today.calories) kcal · P \(Int(today.protein)) g · C \(Int(today.carbs)) g · F \(Int(today.fat)) g")
        }
        if let week = try? repo.weeklyAverages() {
            lines.append("\nLAST 7 DAYS")
            if week.trackedDays > 0 {
                lines.append("- Logged \(week.trackedDays) of the last 7 days")
                lines.append("- Averages over the days they logged: \(Int(week.avgCalories)) kcal/day · P \(Int(week.avgProtein)) g · C \(Int(week.avgCarbs)) g · F \(Int(week.avgFat)) g")
            } else {
                lines.append("- No meals logged in the last 7 days")
            }
        }
        if let daily = try? repo.dailyCaloriesForRange(days: 7) {
            let series = daily.map { $0.calories.map(String.init) ?? "untracked" }.joined(separator: ", ")
            lines.append("- Daily calories (oldest→newest): \(series)")
            lines.append("- Note: \"untracked\" means no meal was logged that day — the user simply didn't track it, not that they fasted or ate at a deficit. Don't read untracked days as low-calorie days, and don't scold missed logging.")
        }

        // Health (best-effort)
        let hk = HealthKitService.shared
        if hk.isHealthDataAvailable {
            var health: [String] = []
            if let weight = await hk.latestBodyMass() {
                health.append("- Latest weight: \(String(format: "%.1f", weight.kilograms)) kg")
            }
            let active = await hk.dailyActiveEnergy(days: 7)
            if !active.isEmpty {
                let avg = active.map(\.value).reduce(0, +) / Double(active.count)
                health.append("- Avg active energy: \(Int(avg)) kcal/day")
            }
            let steps = await hk.dailySteps(days: 7)
            if !steps.isEmpty {
                let avg = steps.map(\.value).reduce(0, +) / Double(steps.count)
                health.append("- Avg steps: \(Int(avg))/day")
            }
            if let rhr = await hk.latestRestingHeartRate() {
                health.append("- Resting heart rate: \(Int(rhr.value)) bpm")
            }
            if let hrv = await hk.latestHRV() {
                health.append("- HRV (SDNN): \(Int(hrv.value)) ms")
            }
            if !health.isEmpty {
                lines.append("\nAPPLE HEALTH")
                lines.append(contentsOf: health)
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: Cache

    private static func readCache(forDay day: String, mealCount: Int) -> CoachingReflection? {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: cacheDayKey) == day,
              defaults.integer(forKey: cacheMealCountKey) == mealCount,
              let data = defaults.data(forKey: cacheJSONKey),
              let reflection = try? JSONDecoder().decode(CoachingReflection.self, from: data) else {
            return nil
        }
        return reflection
    }

    private static func writeCache(_ reflection: CoachingReflection, forDay day: String, mealCount: Int) {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(reflection) {
            defaults.set(day, forKey: cacheDayKey)
            defaults.set(data, forKey: cacheJSONKey)
            defaults.set(mealCount, forKey: cacheMealCountKey)
        }
    }
}

// MARK: - Reflection sheet

/// The full daily reflection: observations, one small idea, and an encouraging close, with a
/// regenerate affordance and a clear not-medical-advice disclaimer.
struct ReflectionSheet: View {
    @ObservedObject var reflection: ReflectionViewModel
    let modelContext: ModelContext
    let credentials: CredentialsManager
    let mealCount: Int

    @Environment(\.dismiss) private var dismiss

    private let observationColors: [Color] = [Theme.accent, Theme.protein, Theme.carbs, Theme.fat]

    var body: some View {
        ZStack {
            LiquidGlassBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    if let r = reflection.current {
                        Text(r.headline)
                            .font(.system(size: 26, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 20)

                        SectionHeader(title: "What I noticed")
                            .padding(.top, 24)
                            .padding(.bottom, 16)

                        ForEach(Array(r.observations.enumerated()), id: \.offset) { index, text in
                            HStack(alignment: .top, spacing: 13) {
                                Circle()
                                    .fill(observationColors[index % observationColors.count])
                                    .frame(width: 8, height: 8)
                                    .padding(.top, 7)
                                Text(text)
                                    .font(.system(size: 15))
                                    .foregroundStyle(Theme.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.bottom, 16)
                        }

                        ideaCard(r.suggestion)

                        Text(r.encouragement)
                            .font(.system(size: 15.5))
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, 14)
                            .overlay(alignment: .leading) {
                                Rectangle().fill(Theme.accent).frame(width: 2)
                            }
                            .padding(.top, 22)

                        footer
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack(spacing: 11) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.accentSoft)
                .frame(width: 36, height: 36)
                .overlay {
                    Image(systemName: "sparkles")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
            VStack(alignment: .leading, spacing: 1) {
                Text("Daily reflection")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text("From your logs & Apple Health")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.ink2)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.ink2)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Theme.chip))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 12)
    }

    private func ideaCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: "lightbulb.fill").font(.system(size: 12))
                Text("One small idea")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.1)
            }
            .foregroundStyle(Theme.accent)
            Text(text)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.accentSoft))
        .padding(.top, 8)
    }

    private var footer: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("Reflections are drawn from your own logs and Health data — not medical advice.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.ink3)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                Task { await reflection.generate(force: true, mealCount: mealCount, modelContext: modelContext, credentials: credentials) }
            } label: {
                HStack(spacing: 6) {
                    if case .loading = reflection.state {
                        ProgressView().controlSize(.small).tint(Theme.accent)
                    } else {
                        Image(systemName: "arrow.clockwise").font(.system(size: 13, weight: .semibold))
                    }
                    Text("Regenerate").font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 24)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hair).frame(height: 1) }
        .padding(.top, 24)
    }
}

#Preview {
    TodayView()
        .environmentObject(CredentialsManager())
        .modelContainer(for: Meal.self, inMemory: true)
}
