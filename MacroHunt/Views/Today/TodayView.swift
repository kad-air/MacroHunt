// Views/Today/TodayView.swift
import SwiftUI
import SwiftData
import UIKit

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var credentials: CredentialsManager

    @Query(sort: \Meal.date) private var allMeals: [Meal]

    /// Opens the Add-meal sheet (owned by `MainTabView`); drives both the bar's "Add meal"
    /// item and the in-content "log next" row.
    var onAddMeal: () -> Void = {}

    @StateObject private var reflection = ReflectionViewModel()
    @State private var showReflection = false
    @State private var deleteError: String?

    /// The moment "today" is computed from. Refreshed at midnight (significant-time-change,
    /// which iOS queues for a suspended app and delivers on resume) and on returning to the
    /// foreground. Reading `Date()` in `body` alone left the screen on yesterday's meals and
    /// ring the next morning, because nothing re-rendered it.
    @State private var now = Date()

    private var todayMeals: [Meal] {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday)!
        return allMeals.filter { $0.date >= startOfToday && $0.date < startOfTomorrow }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidGlassBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header
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
                    .padding(.bottom, 24)
                }
            }
            .tabRootBar("Today")
            .toolbar { AddMealToolbarItem(action: onAddMeal) }
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
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                now = Date()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { now = Date() }
            }
        }
    }

    /// Re-run the reflection check when the day rolls over, when reflections get toggled,
    /// or when the key is first added. Today's meal count nudges it to refresh after logging.
    private var reflectionTaskKey: String {
        "\(Self.dayKey(now))-\(credentials.dailyReflectionEnabled)-\(credentials.anthropicKey.isEmpty)-\(todayMeals.count)"
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.ink2)
            Text(greeting)
                .font(.system(size: 29, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: now) {
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

    /// Evaluated on every render (via `reflectionTaskKey`), so the formatter is built once.
    private static let dayKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func dayKey(_ date: Date) -> String {
        dayKeyFormatter.string(from: date)
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

    // v2: bumped when the snapshot started using the user's weight unit, so a reflection
    // cached from the old always-kg snapshot isn't shown again.
    private static let cacheDayKey = "reflection.cache.v2.day"
    private static let cacheJSONKey = "reflection.cache.v2.json"
    private static let cacheMealCountKey = "reflection.cache.v2.mealCount"

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
        await generate(mealCount: mealCount, modelContext: modelContext, credentials: credentials)
    }

    /// Bumped by every `generate` call. A call that finishes after a newer one started drops
    /// its result, so the latest request always wins.
    private var generation = 0

    /// Generates a new reflection, superseding any still in flight. `mealCount` is the number
    /// of meals logged today that this reflection will reflect, so the cache can be invalidated
    /// when it next changes.
    ///
    /// This used to bail out while another generation was `.loading`. But `.task(id:)` cancels
    /// the old task when the meal count changes, so logging a meal mid-generation made the new
    /// call bail, then the cancelled call landed and set `.failed("cancelled")` — the card sat
    /// on "Reflection unavailable" until the next meal.
    func generate(mealCount: Int, modelContext: ModelContext, credentials: CredentialsManager) async {
        guard !credentials.anthropicKey.isEmpty else {
            state = .idle
            return
        }

        generation += 1
        let thisGeneration = generation
        state = .loading
        let context = await buildContext(modelContext: modelContext, credentials: credentials)
        do {
            let client = ClaudeAPI(apiKey: credentials.anthropicKey)
            let result = try await client.generateReflection(context: context)
            guard thisGeneration == generation else { return }
            let today = TodayView.dayKey(Date())
            loadedDay = today
            loadedMealCount = mealCount
            Self.writeCache(result, forDay: today, mealCount: mealCount)
            state = .ready(result)
        } catch {
            guard thisGeneration == generation else { return }
            // Cancelled (Today went off screen, or its task was replaced) is not a failure:
            // go back to idle and let the next `.task` run regenerate.
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                state = .idle
            } else {
                state = .failed(friendly(error))
            }
        }
    }

    private func friendly(_ error: Error) -> String {
        if let apiError = error as? APIError { return apiError.localizedDescription }
        return error.localizedDescription
    }

    // MARK: Context snapshot

    private func buildContext(modelContext: ModelContext, credentials: CredentialsManager) async -> String {
        let repo = MealRepository(modelContext: modelContext, credentials: credentials)
        let hk = HealthKitService.shared

        var snapshot = ReflectionSnapshot(
            calorieGoal: credentials.dailyCalorieGoal,
            proteinGoal: credentials.proteinGoal,
            carbsGoal: credentials.carbsGoal,
            fatGoal: credentials.fatGoal,
            macroSplitName: credentials.macroSplit.displayName,
            // The same source as Settings' Units row: Apple Health's preferred body-mass unit.
            weightUnit: await hk.preferredWeightUnit(),
            weightGoalKg: credentials.hasWeightGoal ? credentials.weightGoalKg : nil,
            weightGoalDirection: credentials.weightGoalDirection
        )

        // Today + week intake
        if let today = try? repo.dailyTotals(for: Date()) {
            snapshot.today = .init(calories: Double(today.calories), protein: today.protein, carbs: today.carbs, fat: today.fat)
        }
        if let week = try? repo.weeklyAverages() {
            snapshot.weekTrackedDays = week.trackedDays
            snapshot.weekAverages = .init(calories: week.avgCalories, protein: week.avgProtein, carbs: week.avgCarbs, fat: week.avgFat)
        }
        if let daily = try? repo.dailyCaloriesForRange(days: 7) {
            snapshot.dailyCalories = daily.map(\.calories)
        }

        // Health (best-effort)
        if hk.isHealthDataAvailable {
            snapshot.latestWeightKg = await hk.latestBodyMass()?.kilograms
            let active = await hk.dailyActiveEnergy(days: 7)
            if !active.isEmpty {
                snapshot.avgActiveEnergy = active.map(\.value).reduce(0, +) / Double(active.count)
            }
            let steps = await hk.dailySteps(days: 7)
            if !steps.isEmpty {
                snapshot.avgSteps = steps.map(\.value).reduce(0, +) / Double(steps.count)
            }
            snapshot.restingHeartRate = await hk.latestRestingHeartRate()?.value
            snapshot.hrv = await hk.latestHRV()?.value
        }

        return snapshot.render()
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
        // NavigationStack + a semantic Done item (title + symbol) instead of a hand-drawn
        // xmark chip, so the iPhone Duo can place it in its vertical bar — see AddMealView.
        NavigationStack {
            ZStack {
                LiquidGlassBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header

                        switch reflection.state {
                        case .ready(let r):
                            readyContent(r)
                            footer
                        case .loading:
                            loadingState
                            footer
                        case .failed(let message):
                            failedState(message)
                            footer
                        case .idle:
                            EmptyView()
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Daily reflection")
            .toolbarTitleDisplayMode(.inline)
            .toolbar(removing: .title)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
        .tint(Theme.accent)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func readyContent(_ r: CoachingReflection) -> some View {
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
    }

    /// Shown while a reflection is (re)generating, so the pane never goes blank with no hint.
    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
                .tint(Theme.accent)
            Text("Reflecting on your day…")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.ink2)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
        .padding(.bottom, 60)
    }

    private func failedState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Theme.ink3)
            Text("Reflection unavailable right now")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.ink)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Theme.ink2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .padding(.bottom, 40)
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
        }
        .padding(.top, 4)
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
                Task { await reflection.generate(mealCount: mealCount, modelContext: modelContext, credentials: credentials) }
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
