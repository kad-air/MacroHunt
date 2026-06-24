// Views/Settings/SettingsView.swift
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var credentials: CredentialsManager
    @FocusState private var calorieFieldFocused: Bool

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
                            }
                        }
                        .padding(.horizontal)

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
                    }
                }
            }
        }
    }
}

private struct HealthKitSettingsCard: View {
    @EnvironmentObject var credentials: CredentialsManager
    @State private var isRequesting = false
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
                    .disabled(isRequesting)
                    .onChange(of: credentials.healthKitSyncEnabled) { _, enabled in
                        if enabled { requestAuthorization() }
                    }

                    Text("When on, each meal you log is saved to Apple Health as calories, protein, carbs, and fat. You can change permissions any time in the Health app.")
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
            } catch {
                await MainActor.run {
                    isRequesting = false
                    credentials.healthKitSyncEnabled = false
                    message = "Couldn't enable Health sync: \(error.localizedDescription)"
                }
            }
        }
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
