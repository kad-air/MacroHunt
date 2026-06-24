// Views/MainTabView.swift
import SwiftUI

/// The four primary surfaces. The center "+" in the tab bar is an action, not a tab,
/// so it isn't part of this enum.
enum AppTab: Hashable {
    case today, calendar, trends, settings
}

struct MainTabView: View {
    @State private var tab: AppTab = .today
    @State private var showAdd = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // Screens. Each draws its own warm background + scroll content; the tab bar
            // floats above them all.
            Group {
                switch tab {
                case .today:    TodayView(onAddMeal: { showAdd = true })
                case .calendar: CalendarView()
                case .trends:   TrendsView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            MHTabBar(selection: $tab, onAdd: { showAdd = true })
        }
        .tint(Theme.accent)
        .sheet(isPresented: $showAdd) {
            AddMealView()
        }
    }
}

// MARK: - Custom tab bar

/// The floating glass tab bar: Today · Calendar · [ + ] · Trends · Settings.
/// The settings glyph is a plain `gearshape` (one place only — no duplicate gear in the
/// Today header).
struct MHTabBar: View {
    @Binding var selection: AppTab
    var onAdd: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            tab(.today, icon: "house", label: "Today")
            tab(.calendar, icon: "calendar", label: "Calendar")
            addButton
            tab(.trends, icon: "chart.bar", label: "Trends")
            tab(.settings, icon: "gearshape", label: "Settings")
        }
        .padding(.horizontal, 14)
        .padding(.top, 11)
        .frame(maxWidth: .infinity)
        .frame(height: 72, alignment: .top)
        .background(alignment: .top) {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Rectangle().fill(Theme.glassTint))
                .overlay(alignment: .top) { Rectangle().fill(Theme.hair).frame(height: 1) }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func tab(_ value: AppTab, icon: String, label: String) -> some View {
        let isOn = selection == value
        return Button {
            selection = value
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .regular))
                    .frame(height: 26)
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(isOn ? Theme.accent : Theme.ink2)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private var addButton: some View {
        Button(action: onAdd) {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 54, height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.accent)
                )
                .shadow(color: Theme.accent.opacity(0.5), radius: 12, y: 6)
                .offset(y: -6)
        }
        .buttonStyle(.plain)
        .frame(width: 64)
    }
}

#Preview {
    MainTabView()
        .environmentObject(CredentialsManager())
        .modelContainer(for: Meal.self, inMemory: true)
}
