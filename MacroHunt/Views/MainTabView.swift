// Views/MainTabView.swift
import SwiftUI

/// The four primary surfaces.
enum AppTab: Hashable {
    case today, calendar, trends, settings
}

/// The app shell. A *system* `TabView` on purpose — not the hand-drawn floating bar it
/// replaced: the iPhone Duo lays a tab bar out as a vertical strip on its cover display and
/// its open inner display only for standard items that carry both a title and an SF Symbol
/// (HIG "Designing for iPhone Duo"); a custom bar stays a horizontal row at the bottom.
/// Logging a meal is a bar action on the Today/Calendar/Trends roots (`AddMealToolbarItem`)
/// rather than a fake center tab, for the same reason. `DuoBarsUITests` fails if either the
/// tabs or the Add action stop being system bar items.
struct MainTabView: View {
    @State private var tab: AppTab = Self.launchTab
    @State private var showAdd = Self.launchOpensAddMeal

    #if DEBUG
    /// Screenshot aid, Debug builds only: `MACROHUNT_DEBUG_TAB=today|calendar|trends|settings|add`
    /// in the launch environment picks the tab the app opens on (`add` opens Today with the
    /// Add-meal sheet up). Nothing else can switch tabs on the iPhone Duo's open inner display
    /// without a UI test, and `xcodebuild test` closes the Duo (the pose only comes back by
    /// hand in Device Hub); the Xcode device-interaction taps only reach the cover display.
    private static let debugTab = ProcessInfo.processInfo.environment["MACROHUNT_DEBUG_TAB"]
    private static var launchTab: AppTab {
        switch debugTab {
        case "calendar": return .calendar
        case "trends": return .trends
        case "settings": return .settings
        default: return .today
        }
    }
    private static var launchOpensAddMeal: Bool { debugTab == "add" }
    #else
    private static let launchTab: AppTab = .today
    private static let launchOpensAddMeal = false
    #endif

    var body: some View {
        TabView(selection: $tab) {
            Tab("Today", systemImage: "house", value: .today) {
                TodayView(onAddMeal: { showAdd = true })
            }
            Tab("Calendar", systemImage: "calendar", value: .calendar) {
                CalendarView(onAddMeal: { showAdd = true })
            }
            Tab("Trends", systemImage: "chart.bar", value: .trends) {
                TrendsView(onAddMeal: { showAdd = true })
            }
            Tab("Settings", systemImage: "gearshape", value: .settings) {
                SettingsView()
            }
        }
        .tint(Theme.accent)
        .sheet(isPresented: $showAdd) {
            AddMealView()
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(CredentialsManager())
        .modelContainer(for: Meal.self, inMemory: true)
}
