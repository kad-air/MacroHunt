// MacroHuntApp.swift
import SwiftUI
import SwiftData

@main
struct MacroHuntApp: App {
    @StateObject private var credentials = CredentialsManager()
    @State private var showingOnboarding = false

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Meal.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(credentials)
                .onAppear {
                    if !credentials.isValid {
                        showingOnboarding = true
                    }
                }
                .sheet(isPresented: $showingOnboarding) {
                    OnboardingView()
                        .environmentObject(credentials)
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
