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
                .tint(Theme.accent)
                .onAppear {
                    #if DEBUG
                    DebugMealSeed.seedIfRequested(sharedModelContainer.mainContext)
                    #endif
                    // Craft is optional, so onboarding only blocks until the AI key is set.
                    if !credentials.isAIConfigured {
                        showingOnboarding = true
                    }
                }
                .sheet(isPresented: $showingOnboarding) {
                    OnboardingView()
                        .environmentObject(credentials)
                        .tint(Theme.accent)
                }
        }
        .modelContainer(sharedModelContainer)
    }
}

#if DEBUG
/// Screenshot aid, Debug builds only: `MACROHUNT_DEBUG_SEED_MEALS=1` in the launch environment
/// fills an EMPTY store with two weeks of sample meals, so captures of Today, Calendar and
/// Trends show real cards, calendar dots and charts instead of empty states. A store that
/// already holds a meal is never touched. Nothing is mirrored to Craft or Apple Health (the
/// meals go straight into SwiftData, not through `MealRepository`).
@MainActor
enum DebugMealSeed {
    static func seedIfRequested(_ context: ModelContext) {
        guard ProcessInfo.processInfo.environment["MACROHUNT_DEBUG_SEED_MEALS"] == "1",
              (try? context.fetchCount(FetchDescriptor<Meal>())) == 0 else { return }

        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        // (name, type, hour, minute, kcal, protein, carbs, fat)
        let menu: [(String, MealType, Int, Int, Int, Double, Double, Double)] = [
            ("Greek yogurt & berries", .breakfast, 8, 0, 320, 22, 38, 8),
            ("Chicken burrito bowl", .lunch, 12, 30, 680, 42, 72, 22),
            ("Apple & peanut butter", .snack, 15, 30, 260, 7, 28, 16),
            ("Salmon, rice & greens", .dinner, 18, 45, 610, 40, 55, 24),
        ]
        var count = 0
        // Days 1–13 back; days 5 and 10 stay untracked so the calendar shows gaps.
        for daysAgo in 1...13 where daysAgo != 5 && daysAgo != 10 {
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: today)!
            for (index, item) in menu.enumerated() {
                // Skip the snack every third day; vary portions so the trend line moves.
                if index == 2 && daysAgo % 3 == 0 { continue }
                let scale = 0.8 + Double((daysAgo * 7 + index * 3) % 6) * 0.08
                let date = calendar.date(bySettingHour: item.2, minute: item.3, second: 0, of: day)!
                context.insert(Meal(
                    name: item.0, date: date, mealType: item.1,
                    calories: Int(Double(item.4) * scale),
                    protein: (item.5 * scale).rounded(), carbs: (item.6 * scale).rounded(), fat: (item.7 * scale).rounded()
                ))
                count += 1
            }
        }
        // Today: two meals already logged, earlier than now.
        context.insert(Meal(name: "Greek yogurt & berries", date: now.addingTimeInterval(-3 * 3600), mealType: .breakfast,
                            calories: 320, protein: 22, carbs: 38, fat: 8))
        context.insert(Meal(name: "Oat latte & banana", date: now.addingTimeInterval(-3600), mealType: .snack,
                            calories: 240, protein: 8, carbs: 44, fat: 5))
        count += 2
        do {
            try context.save()
            print("[DebugMealSeed] seeded \(count) sample meals")
        } catch {
            print("[DebugMealSeed] save failed: \(error)")
        }
    }
}
#endif
