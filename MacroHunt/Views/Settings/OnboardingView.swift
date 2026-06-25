// Views/Settings/OnboardingView.swift
import SwiftUI
import HealthKit

struct OnboardingView: View {
    @EnvironmentObject var credentials: CredentialsManager
    @Environment(\.dismiss) private var dismiss

    @State private var currentStep = 0
    @Environment(\.modelContext) private var modelContext
    @State private var healthKitStatus: HKAuthorizationStatus = .notDetermined
    @State private var healthKitRequesting = false
    @State private var healthKitSyncing = false
    @State private var healthKitSyncCurrent = 0
    @State private var healthKitSyncTotal = 0
    @State private var healthKitSyncComplete = false
    @State private var healthKitSyncedCount = 0

    var body: some View {
        ZStack {
            LiquidGlassBackground()
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // Progress indicator
                HStack(spacing: 8) {
                    ForEach(0..<3) { step in
                        Capsule()
                            .fill(step <= currentStep ? Theme.accent : Theme.ink3)
                            .frame(height: 4)
                    }
                }
                .padding(.horizontal)
                .padding(.top)

                TabView(selection: $currentStep) {
                    // Step 1: Welcome
                    welcomeStep
                        .tag(0)

                    // Step 2: Claude Setup (required — gates logging)
                    claudeSetupStep
                        .tag(1)

                    // Step 3: Apple Health
                    healthKitStep
                        .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                // Navigation buttons
                HStack(spacing: 16) {
                    if currentStep > 0 {
                        Button("Back") {
                            withAnimation {
                                currentStep -= 1
                            }
                        }
                        .buttonStyle(.bordered)
                    }

                    Spacer()

                    if currentStep < 2 {
                        Button("Next") {
                            withAnimation { currentStep += 1 }
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button("Get Started") {
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!credentials.isAIConfigured)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
        .interactiveDismissDisabled(!credentials.isAIConfigured)
    }

    // MARK: - Step Views

    private var welcomeStep: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "fork.knife.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.orange, .orange.opacity(0.3))
                    .padding(.top, 40)

                Text("Welcome to MacroHunt")
                    .font(.system(size: 28, weight: .bold, design: .rounded))

                Text("Track your meals with AI-powered nutritional analysis.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                VStack(alignment: .leading, spacing: 16) {
                    FeatureRow(icon: "camera.fill", color: .blue, title: "Photo Analysis", description: "Snap photos of your meals for instant macro estimates")
                    FeatureRow(icon: "chart.line.uptrend.xyaxis", color: .green, title: "Track Trends", description: "Monitor your nutrition over time with charts")
                    FeatureRow(icon: "heart.fill", color: .red, title: "Apple Health", description: "Optionally sync meals and read your weight & activity")
                }
                .padding()
            }
            .padding()
        }
    }

    private var healthKitStep: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.red, .red.opacity(0.3))
                    .padding(.top, 40)

                Text("Apple Health")
                    .font(.system(size: 28, weight: .bold, design: .rounded))

                Text("MacroHunt can save the meals you log to Apple Health, and read your weight, activity, and heart data back in — so your Trends show what you eat alongside how you move. You choose exactly what to share on the next screen.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                if HealthKitService.shared.isHealthDataAvailable {
                    switch healthKitStatus {
                    case .sharingAuthorized:
                        VStack(spacing: 12) {
                            if healthKitSyncing {
                                VStack(spacing: 8) {
                                    ProgressView(value: Double(healthKitSyncCurrent), total: Double(max(healthKitSyncTotal, 1)))
                                        .tint(.red)
                                        .padding(.horizontal)
                                    Text("Syncing past meals… \(healthKitSyncCurrent) of \(healthKitSyncTotal)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                HStack(spacing: 10) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text(healthKitSyncComplete && healthKitSyncedCount > 0
                                        ? "\(healthKitSyncedCount) past meal\(healthKitSyncedCount == 1 ? "" : "s") synced to Apple Health"
                                        : "Apple Health connected")
                                        .font(.subheadline)
                                        .foregroundColor(.green)
                                }
                            }
                        }
                        .padding()

                    default:
                        Button {
                            requestHealthKitAuthorization()
                        } label: {
                            HStack {
                                if healthKitRequesting {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: "heart.fill")
                                }
                                Text("Enable Apple Health")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .disabled(healthKitRequesting)
                        .padding(.horizontal)
                    }
                } else {
                    Text("Apple Health isn't available on this device.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text("You can change this any time in Settings.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
    }

    private func requestHealthKitAuthorization() {
        healthKitRequesting = true
        Task {
            do {
                try await HealthKitService.shared.requestAuthorization()
                let status = HealthKitService.shared.energyAuthorizationStatus()
                await MainActor.run {
                    healthKitRequesting = false
                    healthKitStatus = status
                    credentials.healthKitSyncEnabled = (status == .sharingAuthorized)
                }
                if status == .sharingAuthorized {
                    await syncHistoricalMeals()
                }
            } catch {
                await MainActor.run {
                    healthKitRequesting = false
                }
            }
        }
    }

    private func syncHistoricalMeals() async {
        let repo = MealRepository(modelContext: modelContext, credentials: credentials)
        healthKitSyncing = true
        healthKitSyncCurrent = 0
        healthKitSyncTotal = 0
        let result = await repo.syncHistoricalMeals { current, total in
            healthKitSyncCurrent = current
            healthKitSyncTotal = total
        }
        healthKitSyncing = false
        healthKitSyncedCount = result.synced
        healthKitSyncComplete = true
    }

    private var claudeSetupStep: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "sparkles")
                    .font(.system(size: 60))
                    .foregroundColor(.purple)
                    .padding(.top, 40)

                Text("Enable AI Analysis")
                    .font(.system(size: 28, weight: .bold, design: .rounded))

                Text("Add your Claude API key for nutritional analysis.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                GlassCard {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Anthropic API Key")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            SecureField("Enter your API key", text: $credentials.anthropicKey)
                                .inputFieldStyle()
                        }

                        Text("Get your API key from the Anthropic Console")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)

                // Status
                if credentials.isAIConfigured {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("All set! You're ready to start tracking.")
                            .font(.subheadline)
                    }
                    .padding()
                }
            }
            .padding()
        }
    }
}

// MARK: - Feature Row

private struct FeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    OnboardingView()
        .environmentObject(CredentialsManager())
}
