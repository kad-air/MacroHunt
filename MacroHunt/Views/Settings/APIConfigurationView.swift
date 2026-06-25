// Views/Settings/APIConfigurationView.swift
import SwiftUI

struct APIConfigurationView: View {
    @EnvironmentObject var credentials: CredentialsManager
    @State private var showingClearConfirmation = false

    var body: some View {
        ZStack {
            LiquidGlassBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // API Credentials
                    GlassCard {
                        VStack(alignment: .leading, spacing: 16) {
                            SectionHeader(title: "Craft API", icon: "doc.text.fill")

                            Toggle(isOn: $credentials.craftSyncEnabled) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Sync meals to Craft")
                                        .font(.subheadline.weight(.semibold))
                                    Text("Optional. When off, meals are still logged locally and analyzed by Claude — nothing is sent to Craft.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .tint(Theme.accent)

                            VStack(alignment: .leading, spacing: 8) {
                                Text("API Token")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                SecureField("Enter your Craft API token", text: $credentials.craftToken)
                                    .inputFieldStyle()
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Space ID")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextField("Enter your Space ID", text: $credentials.spaceId)
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

                    GlassCard {
                        VStack(alignment: .leading, spacing: 16) {
                            SectionHeader(title: "Claude API", icon: "sparkles")

                            VStack(alignment: .leading, spacing: 8) {
                                Text("API Key")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                SecureField("Enter your Anthropic API key", text: $credentials.anthropicKey)
                                    .inputFieldStyle()
                            }
                        }
                    }
                    .padding(.horizontal)

                    // Status
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "Status", icon: "info.circle")

                            statusRow(
                                ok: credentials.isAIConfigured,
                                onText: "AI analysis ready",
                                offText: "Claude API key needed to log meals"
                            )

                            statusRow(
                                ok: credentials.craftSyncActive,
                                onText: "Craft sync on",
                                offText: craftStatusOffText,
                                neutral: !credentials.craftSyncEnabled || !credentials.isCraftConfigured
                            )

                            if let error = credentials.configurationError {
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                    .padding(.horizontal)

                    // Clear Button
                    GlassCard {
                        Button(role: .destructive) {
                            showingClearConfirmation = true
                        } label: {
                            Label("Clear All Credentials", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
        }
        .navigationTitle("API Configuration")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Clear Credentials?", isPresented: $showingClearConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                credentials.clearKeychainCredentials()
            }
        } message: {
            Text("This will remove all stored API keys and tokens.")
        }
    }

    private var craftStatusOffText: String {
        if !credentials.isCraftConfigured { return "Craft not set up (optional)" }
        return "Craft sync paused"
    }

    /// A single status line. `ok` shows a green check; otherwise a neutral or red indicator
    /// depending on `neutral` — an unconfigured *optional* Craft isn't an error.
    @ViewBuilder
    private func statusRow(ok: Bool, onText: String, offText: String, neutral: Bool = false) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : (neutral ? "minus.circle.fill" : "xmark.circle.fill"))
                .foregroundColor(ok ? .green : (neutral ? .secondary : .red))
            Text(ok ? onText : offText)
                .font(.subheadline)
        }
    }
}

#Preview {
    NavigationStack {
        APIConfigurationView()
            .environmentObject(CredentialsManager())
    }
}
