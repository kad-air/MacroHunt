// Views/Settings/SettingsView.swift
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var credentials: CredentialsManager
    @Environment(\.modelContext) private var modelContext

    @FocusState private var calorieFieldFocused: Bool
    @FocusState private var weightFieldFocused: Bool

    @State private var editingGoals = false
    @State private var editingWeight = false

    // Weight goal is stored canonically in kg; entered/displayed in the user's preferred unit.
    @State private var weightUnit: WeightUnit = Locale.current.measurementSystem == .us ? .pounds : .kilograms
    @State private var weightText: String = ""
    @State private var currentWeightKg: Double?

    // Apple Health
    @State private var healthRequesting = false
    @State private var healthSyncing = false
    @State private var healthSyncCurrent = 0
    @State private var healthSyncTotal = 0
    @State private var healthSyncedCount = 0
    @State private var healthSyncComplete = false
    @State private var healthMessage: String?

    private var healthAvailable: Bool { HealthKitService.shared.isHealthDataAvailable }

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidGlassBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        MHHeader(kicker: "Preferences & goals", title: "Settings")
                            .padding(.top, 8)
                            .padding(.bottom, 6)

                        section("Goals")
                        dailyTargetCard
                        weightTargetCard.padding(.top, 14)

                        section("Connections")
                        connectionsCard

                        section("Preferences")
                        preferencesCard

                        appInfo
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 110)
                }
            }
            .navigationBarHidden(true)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        calorieFieldFocused = false
                        weightFieldFocused = false
                    }
                }
            }
            .task {
                weightUnit = await HealthKitService.shared.preferredWeightUnit()
                if credentials.weightGoalKg > 0 {
                    weightText = String(Int(weightUnit.fromKilograms(credentials.weightGoalKg).rounded()))
                }
                currentWeightKg = await HealthKitService.shared.latestBodyMass()?.kilograms
            }
            .onChange(of: weightText) { _, newValue in
                if let value = Double(newValue), value > 0 {
                    credentials.weightGoalKg = weightUnit.toKilograms(value)
                } else {
                    credentials.weightGoalKg = 0
                }
            }
        }
    }

    private func section(_ title: String) -> some View {
        SectionHeader(title: title)
            .padding(.horizontal, 4)
            .padding(.top, 28)
            .padding(.bottom, 12)
    }

    // MARK: - Daily target

    private var dailyTargetCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 0) {
                cardHeader("Daily target", isEditing: $editingGoals)

                if editingGoals {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            TextField("2000", value: $credentials.dailyCalorieGoal, format: .number)
                                .keyboardType(.numberPad)
                                .focused($calorieFieldFocused)
                                .inputFieldStyle()
                            Text("kcal/day").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink2)
                        }

                        Picker("Macro Split", selection: $credentials.macroSplit) {
                            ForEach(MacroSplit.allCases) { split in
                                Text(split.displayName).tag(split)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text(credentials.macroSplit.description)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.ink3)
                    }
                    .padding(.top, 16)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text("\(credentials.dailyCalorieGoal.formatted())")
                            .font(.system(size: 28, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.ink)
                            .monospacedDigit()
                        Text(" kcal / day")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.ink2)
                    }
                    .padding(.top, 14)
                }

                macroGoalRow.padding(.top, 16)
            }
        }
    }

    private var macroGoalRow: some View {
        HStack(spacing: 18) {
            macroGoal("Protein", credentials.proteinGoal, Theme.protein)
            macroGoal("Carbs", credentials.carbsGoal, Theme.carbs)
            macroGoal("Fat", credentials.fatGoal, Theme.fat)
        }
    }

    private func macroGoal(_ name: String, _ grams: Int, _ color: Color) -> some View {
        HStack(spacing: 7) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink2)
            Text("\(grams)g").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink)
        }
    }

    // MARK: - Weight target

    private var weightTargetCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 0) {
                cardHeader("Weight target", isEditing: $editingWeight)

                if editingWeight {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            TextField("Optional", text: $weightText)
                                .keyboardType(.decimalPad)
                                .focused($weightFieldFocused)
                                .inputFieldStyle()
                            Text(weightUnit.abbreviation).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink2)
                        }
                        if !weightText.isEmpty {
                            Picker("Direction", selection: $credentials.weightGoalDirection) {
                                ForEach(WeightGoalDirection.allCases) { Text($0.displayName).tag($0) }
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                    .padding(.top, 16)
                } else if credentials.hasWeightGoal {
                    HStack(spacing: 12) {
                        if let kg = currentWeightKg {
                            StatTile(label: "Current", value: "\(Int(weightUnit.fromKilograms(kg).rounded()))", unit: weightUnit.abbreviation)
                        }
                        StatTile(
                            label: "Target",
                            value: "\(Int(weightUnit.fromKilograms(credentials.weightGoalKg).rounded()))",
                            unit: weightUnit.abbreviation,
                            caption: weightGoalCaption
                        )
                    }
                    .padding(.top, 14)
                } else {
                    Text("No weight target yet — tap Edit to set one.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.ink3)
                        .padding(.top, 12)
                }
            }
        }
    }

    private var weightGoalCaption: String? {
        guard credentials.hasWeightGoal, let kg = currentWeightKg else {
            return credentials.weightGoalDirection.displayName.lowercased()
        }
        let diff = abs(weightUnit.fromKilograms(kg) - weightUnit.fromKilograms(credentials.weightGoalKg))
        return "\(credentials.weightGoalDirection.displayName.lowercased()) · \(String(format: "%.1f", diff)) to go"
    }

    // MARK: - Connections

    private var connectionsCard: some View {
        GlassCard(padding: 0) {
            VStack(spacing: 0) {
                appleHealthRow
                rowDivider
                NavigationLink { APIConfigurationView() } label: {
                    ConnectionRow(
                        icon: "tray.full",
                        label: "Craft Docs sync",
                        sublabel: "Saved to your Meal Tracker",
                        trailing: craftConfigured ? .pill("Connected") : .chevron("Set up")
                    )
                }
                .buttonStyle(.plain)
                rowDivider
                NavigationLink { APIConfigurationView() } label: {
                    ConnectionRow(
                        icon: "wand.and.stars",
                        label: "AI analysis",
                        sublabel: "Claude · meal nutrition",
                        trailing: !credentials.anthropicKey.isEmpty ? .chevron("Configured") : .chevron("Set up")
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var craftConfigured: Bool {
        !credentials.craftToken.isEmpty && !credentials.spaceId.isEmpty && !credentials.collectionId.isEmpty
    }

    @ViewBuilder
    private var appleHealthRow: some View {
        VStack(spacing: 10) {
            HStack(spacing: 13) {
                rowIcon("heart")
                VStack(alignment: .leading, spacing: 1) {
                    Text("Apple Health")
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text("Meals out · weight, activity & cardio in")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.ink2)
                }
                Spacer(minLength: 8)
                if healthAvailable {
                    Toggle("", isOn: $credentials.healthKitSyncEnabled)
                        .labelsHidden()
                        .tint(Theme.accent)
                        .disabled(healthRequesting || healthSyncing)
                        .onChange(of: credentials.healthKitSyncEnabled) { _, enabled in
                            if enabled { requestHealthAuthorization() }
                        }
                } else {
                    Text("Unavailable").font(.system(size: 12)).foregroundStyle(Theme.ink3)
                }
            }

            if healthSyncing {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: Double(healthSyncCurrent), total: Double(max(healthSyncTotal, 1)))
                        .tint(Theme.accent)
                    Text("Syncing past meals… \(healthSyncCurrent) of \(healthSyncTotal)")
                        .font(.system(size: 11)).foregroundStyle(Theme.ink2)
                }
            } else if healthSyncComplete && healthSyncedCount > 0 {
                Text("\(healthSyncedCount) past meal\(healthSyncedCount == 1 ? "" : "s") synced to Apple Health")
                    .font(.system(size: 11)).foregroundStyle(Theme.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let healthMessage {
                Text(healthMessage).font(.system(size: 11)).foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(18)
    }

    // MARK: - Preferences

    private var preferencesCard: some View {
        GlassCard(padding: 0) {
            VStack(spacing: 0) {
                PreferenceRow(icon: "moon.stars", label: "Appearance", trailing: .text("Auto"))
                rowDivider
                PreferenceRow(icon: "ruler", label: "Units", trailing: .text("\(weightUnit == .kilograms ? "Metric" : "Imperial") · \(weightUnit.abbreviation)"))
                rowDivider
                HStack(spacing: 13) {
                    rowIcon("sparkles")
                    Text("Daily reflection")
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Toggle("", isOn: $credentials.dailyReflectionEnabled)
                        .labelsHidden()
                        .tint(Theme.accent)
                }
                .padding(18)
            }
        }
    }

    private var appInfo: some View {
        VStack(spacing: 3) {
            Text("MacroHunt").font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink)
            Text("Version 1.0").font(.system(size: 12)).foregroundStyle(Theme.ink3)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 28)
    }

    // MARK: - Shared row chrome

    private var rowDivider: some View {
        Rectangle().fill(Theme.hair).frame(height: 1).padding(.leading, 18)
    }

    private func cardHeader(_ title: String, isEditing: Binding<Bool>) -> some View {
        HStack {
            Text(title).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink)
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isEditing.wrappedValue.toggle() }
            } label: {
                Text(isEditing.wrappedValue ? "Done" : "Edit")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
        }
    }

    private func rowIcon(_ systemName: String) -> some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(Theme.chip)
            .frame(width: 36, height: 36)
            .overlay {
                Image(systemName: systemName)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Theme.ink2)
            }
    }

    // MARK: - Apple Health actions (preserved from the prior Settings card)

    private func requestHealthAuthorization() {
        healthRequesting = true
        healthMessage = nil
        Task { @MainActor in
            do {
                try await HealthKitService.shared.requestAuthorization()
                healthRequesting = false
                await syncHistoricalMeals()
            } catch {
                healthRequesting = false
                credentials.healthKitSyncEnabled = false
                healthMessage = "Couldn't enable Health sync: \(error.localizedDescription)"
            }
        }
    }

    @MainActor
    private func syncHistoricalMeals() async {
        let repo = MealRepository(modelContext: modelContext, credentials: credentials)
        healthSyncing = true
        healthSyncCurrent = 0
        healthSyncTotal = 0
        let result = await repo.syncHistoricalMeals { current, total in
            healthSyncCurrent = current
            healthSyncTotal = total
        }
        healthSyncing = false
        healthSyncedCount = result.synced
        healthSyncComplete = true
    }
}

// MARK: - Connection / preference rows

private struct ConnectionRow: View {
    enum Trailing {
        case pill(String)
        case chevron(String)
        case text(String)
    }

    let icon: String
    let label: String
    var sublabel: String?
    let trailing: Trailing

    var body: some View {
        HStack(spacing: 13) {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Theme.chip)
                .frame(width: 36, height: 36)
                .overlay {
                    Image(systemName: icon).font(.system(size: 17)).foregroundStyle(Theme.ink2)
                }
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.system(size: 14.5, weight: .semibold)).foregroundStyle(Theme.ink)
                if let sublabel {
                    Text(sublabel).font(.system(size: 12)).foregroundStyle(Theme.ink2)
                }
            }
            Spacer(minLength: 8)
            trailingView
        }
        .padding(18)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var trailingView: some View {
        switch trailing {
        case .pill(let text):
            StatusPill(text: text)
        case .chevron(let text):
            HStack(spacing: 8) {
                Text(text).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink2)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink3)
            }
        case .text(let text):
            Text(text).font(.system(size: 14, weight: .medium, design: .rounded)).foregroundStyle(Theme.ink2)
        }
    }
}

private struct PreferenceRow: View {
    let icon: String
    let label: String
    let trailing: ConnectionRow.Trailing

    var body: some View {
        ConnectionRow(icon: icon, label: label, sublabel: nil, trailing: trailing)
    }
}

#Preview {
    SettingsView()
        .environmentObject(CredentialsManager())
        .modelContainer(for: Meal.self, inMemory: true)
}
