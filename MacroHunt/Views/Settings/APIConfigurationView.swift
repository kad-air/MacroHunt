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
                            SectionHeader(title: "Gemini API", icon: "sparkles")

                            VStack(alignment: .leading, spacing: 8) {
                                Text("API Key")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                SecureField("Enter your Gemini API key", text: $credentials.geminiKey)
                                    .inputFieldStyle()
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
}

#Preview {
    NavigationStack {
        APIConfigurationView()
            .environmentObject(CredentialsManager())
    }
}
