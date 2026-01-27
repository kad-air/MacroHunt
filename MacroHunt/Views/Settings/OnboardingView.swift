// Views/Settings/OnboardingView.swift
import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var credentials: CredentialsManager
    @Environment(\.dismiss) private var dismiss

    @State private var currentStep = 0

    var body: some View {
        ZStack {
            LiquidGlassBackground()
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // Progress indicator
                HStack(spacing: 8) {
                    ForEach(0..<3) { step in
                        Capsule()
                            .fill(step <= currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(height: 4)
                    }
                }
                .padding(.horizontal)
                .padding(.top)

                TabView(selection: $currentStep) {
                    // Step 1: Welcome
                    welcomeStep
                        .tag(0)

                    // Step 2: Craft Setup
                    craftSetupStep
                        .tag(1)

                    // Step 3: Gemini Setup
                    geminiSetupStep
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
                            withAnimation {
                                currentStep += 1
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button("Get Started") {
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!credentials.isValid)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
        .interactiveDismissDisabled(!credentials.isValid)
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

                Text("Track your meals with AI-powered nutritional analysis and sync to Craft Docs.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                VStack(alignment: .leading, spacing: 16) {
                    FeatureRow(icon: "camera.fill", color: .blue, title: "Photo Analysis", description: "Snap photos of your meals for instant macro estimates")
                    FeatureRow(icon: "chart.line.uptrend.xyaxis", color: .green, title: "Track Trends", description: "Monitor your nutrition over time with charts")
                    FeatureRow(icon: "doc.text.fill", color: .purple, title: "Craft Sync", description: "All meals saved to your Craft collection")
                }
                .padding()
            }
            .padding()
        }
    }

    private var craftSetupStep: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "doc.badge.gearshape.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                    .padding(.top, 40)

                Text("Connect to Craft")
                    .font(.system(size: 28, weight: .bold, design: .rounded))

                Text("Enter your Craft API credentials to sync meals.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                GlassCard {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("API Token")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            SecureField("Craft API token", text: $credentials.craftToken)
                                .inputFieldStyle()
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Space ID")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("Your Space ID", text: $credentials.spaceId)
                                .inputFieldStyle()
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Collection ID")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("Meal Tracker collection ID", text: $credentials.collectionId)
                                .inputFieldStyle()
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding()
        }
    }

    private var geminiSetupStep: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "sparkles")
                    .font(.system(size: 60))
                    .foregroundColor(.purple)
                    .padding(.top, 40)

                Text("Enable AI Analysis")
                    .font(.system(size: 28, weight: .bold, design: .rounded))

                Text("Add your Gemini API key for nutritional analysis.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                GlassCard {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Gemini API Key")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            SecureField("Enter your API key", text: $credentials.geminiKey)
                                .inputFieldStyle()
                        }

                        Text("Get your API key from Google AI Studio")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)

                // Status
                if credentials.isValid {
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
