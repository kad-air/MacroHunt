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
    @State private var tab: AppTab = .today
    @State private var showAdd = false

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
