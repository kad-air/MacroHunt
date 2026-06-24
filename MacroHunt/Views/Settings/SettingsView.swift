// Views/Settings/SettingsView.swift
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var credentials: CredentialsManager
    @FocusState private var calorieFieldFocused: Bool
    @FocusState private var weightFieldFocused: Bool

    // Weight goal is stored canonically in kg; entered/displayed in the user's preferred
    // Health unit. `weightText` holds the in-progress entry (empty = no goal).
    @State private var weightUnit: WeightUnit = Locale.current.measurementSystem == .us ? .pounds : .kilograms
    @State private var weightText: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidGlassBackground()
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        Text("Settings")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)

                        // Goals
                        GlassCard {
                            VStack(alignment: .leading, spacing: 16) {
                                SectionHeader(title: "Daily Goals", icon: "target")

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Calorie Goal")
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    HStack {
                                        TextField("2000", value: $credentials.dailyCalorieGoal, format: .number)
                                            .inputFieldStyle()
                                            .keyboardType(.numberPad)
                                            .focused($calorieFieldFocused)

                                        Text("kcal")
                                            .foregroundColor(.secondary)
                                    }
                                }

                                Divider()

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Macro Split")
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    Picker("Macro Split", selection: $credentials.macroSplit) {
                                        ForEach(MacroSplit.allCases) { split in
                                            Text(split.displayName).tag(split)
                                        }
                                    }
                                    .pickerStyle(.segmented)

                                    Text(credentials.macroSplit.description)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }

                                // Calculated macro goals display
                                HStack(spacing: 16) {
                                    MacroGoalLabel(name: "Protein", value: credentials.proteinGoal, color: .red)
                                    MacroGoalLabel(name: "Carbs", value: credentials.carbsGoal, color: .blue)
                                    MacroGoalLabel(name: "Fat", value: credentials.fatGoal, color: .yellow)
                                }
                                .padding(.top, 4)

                                Divider()

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Weight Goal")
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    HStack {
                                        TextField("Optional", text: $weightText)
                                            .inputFieldStyle()
                                            .keyboardType(.decimalPad)
                                            .focused($weightFieldFocused)

                                        Text(weightUnit.abbreviation)
                                            .foregroundColor(.secondary)
                                    }

                                    if !weightText.isEmpty {
                                        Picker("Direction", selection: $credentials.weightGoalDirection) {
                                            ForEach(WeightGoalDirection.allCases) { direction in
                                                Text(direction.displayName).tag(direction)
                                            }
                                        }
                                        .pickerStyle(.segmented)
                                        .padding(.top, 4)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                        .task {
                            weightUnit = await HealthKitService.shared.preferredWeightUnit()
                            if credentials.weightGoalKg > 0 {
                                weightText = String(Int(weightUnit.fromKilograms(credentials.weightGoalKg).rounded()))
                            }
                        }
                        .onChange(of: weightText) { _, newValue in
                            if let value = Double(newValue), value > 0 {
                                credentials.weightGoalKg = weightUnit.toKilograms(value)
                            } else {
                                credentials.weightGoalKg = 0
                            }
                        }

                        // Apple Health
                        HealthKitSettingsCard()
                            .padding(.horizontal)

                        // API Configuration Link
                        NavigationLink {
                            APIConfigurationView()
                        } label: {
                            GlassCard {
                                HStack {
                                    Image(systemName: "key.fill")
                                        .foregroundColor(.accentColor)
                                    Text("API Configuration")
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Image(systemName: credentials.isValid ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                        .foregroundColor(credentials.isValid ? .green : .orange)
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.horizontal)

                        // App Info
                        VStack(spacing: 4) {
                            Text("MacroHunt")
                                .font(.headline)
                            Text("Version 1.0")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 20)
                    }
                    .padding(.vertical)
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        calorieFieldFocused = false
                        weightFieldFocused = false
                    }
                }
            }
        }
    }
}

private struct HealthKitSettingsCard: View {
    @EnvironmentObject var credentials: CredentialsManager
    @Environment(\.modelContext) private var modelContext
    @State private var isRequesting = false
    @State private var isSyncing = false
    @State private var syncCurrent = 0
    @State private var syncTotal = 0
    @State private var syncComplete = false
    @State private var syncedCount = 0
    @State private var message: String?

    private var isAvailable: Bool { HealthKitService.shared.isHealthDataAvailable }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Apple Health", icon: "heart.fill")

                if isAvailable {
                    Toggle(isOn: $credentials.healthKitSyncEnabled) {
                        Text("Sync meals to Apple Health")
                            .foregroundColor(.primary)
                    }
                    .disabled(isRequesting || isSyncing)
                    .onChange(of: credentials.healthKitSyncEnabled) { _, enabled in
                        if enabled { requestAuthorization() }
                    }

                    if isSyncing {
                        VStack(alignment: .leading, spacing: 6) {
                            ProgressView(value: Double(syncCurrent), total: Double(max(syncTotal, 1)))
                                .tint(.red)
                            Text("Syncing past meals… \(syncCurrent) of \(syncTotal)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    } else if syncComplete && syncedCount > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                            Text("\(syncedCount) past meal\(syncedCount == 1 ? "" : "s") synced to Apple Health")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    Text("When on, each meal you log is saved to Apple Health, and MacroHunt can read your weight, activity, and heart data to show richer Trends. You can change permissions any time in the Health app.")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    if let message {
                        Text(message)
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                } else {
                    Text("Apple Health is not available on this device.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func requestAuthorization() {
        isRequesting = true
        message = nil
        Task {
            do {
                try await HealthKitService.shared.requestAuthorization()
                await MainActor.run { isRequesting = false }
                await syncHistoricalMeals()
            } catch {
                await MainActor.run {
                    isRequesting = false
                    credentials.healthKitSyncEnabled = false
                    message = "Couldn't enable Health sync: \(error.localizedDescription)"
                }
            }
        }
    }

    private func syncHistoricalMeals() async {
        let repo = MealRepository(modelContext: modelContext, credentials: credentials)
        isSyncing = true
        syncCurrent = 0
        syncTotal = 0
        let result = await repo.syncHistoricalMeals { current, total in
            syncCurrent = current
            syncTotal = total
        }
        isSyncing = false
        syncedCount = result.synced
        syncComplete = true
    }
}

private struct MacroGoalLabel: View {
    let name: String
    let value: Int
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)g")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(color)
            Text(name)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    SettingsView()
        .environmentObject(CredentialsManager())
}
