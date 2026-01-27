// Views/Settings/SettingsView.swift
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var credentials: CredentialsManager

    @State private var showingClearConfirmation = false

    var body: some View {
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

                    // API Credentials
                    GlassCard {
                        VStack(alignment: .leading, spacing: 16) {
                            SectionHeader(title: "API Credentials", icon: "key.fill")

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Craft API Token")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                SecureField("Enter your Craft API token", text: $credentials.craftToken)
                                    .inputFieldStyle()
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Craft Space ID")
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

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Gemini API Key")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                SecureField("Enter your Gemini API key", text: $credentials.geminiKey)
                                    .inputFieldStyle()
                            }
                        }
                    }
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

                                    Text("kcal")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)

                    // Status
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "Status", icon: "info.circle")

                            HStack {
                                Image(systemName: credentials.isValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(credentials.isValid ? .green : .red)
                                Text(credentials.isValid ? "All credentials configured" : "Missing credentials")
                                    .font(.subheadline)
                            }

                            if let error = credentials.configurationError {
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                    .padding(.horizontal)

                    // Actions
                    GlassCard {
                        VStack(spacing: 12) {
                            Button(role: .destructive) {
                                showingClearConfirmation = true
                            } label: {
                                Label("Clear All Credentials", systemImage: "trash")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
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
        .alert("Clear Credentials?", isPresented: $showingClearConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                credentials.clearKeychainCredentials()
            }
        } message: {
            Text("This will remove all stored API keys and tokens.")
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(CredentialsManager())
}
