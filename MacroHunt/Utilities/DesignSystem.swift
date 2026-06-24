// Utilities/DesignSystem.swift
// MacroHunt design system — warm "Liquid Glass" revamp.
//
// A single warm palette that adapts to light/dark (the app follows the system
// appearance). Colors, glass surfaces, the calorie ring, macro tracks, meal rows,
// stat tiles and the custom tab bar all live here so the screens stay declarative.

import SwiftUI
import UIKit

// MARK: - Color helpers

extension UIColor {
    /// Builds a UIColor from a 0xRRGGBB literal with an optional alpha.
    convenience init(rgb: Int, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255.0,
            green: CGFloat((rgb >> 8) & 0xFF) / 255.0,
            blue: CGFloat(rgb & 0xFF) / 255.0,
            alpha: alpha
        )
    }
}

extension Color {
    /// A dynamic color that resolves per trait collection, so the warm palette tracks
    /// the system light/dark setting automatically.
    init(light: UIColor, dark: UIColor) {
        self = Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}

// MARK: - Theme palette

/// The warm token palette mirrored from the Claude Design revamp. Accent is green
/// (the design's default), macros are coral / blue / gold, text steps through three
/// "ink" levels. Every token adapts to light/dark.
enum Theme {
    // Text
    static let ink   = Color(light: UIColor(rgb: 0x221D17), dark: UIColor(rgb: 0xF3EEE6))
    static let ink2  = Color(light: UIColor(rgb: 0x6F685F), dark: UIColor(rgb: 0xA59E93))
    static let ink3  = Color(light: UIColor(rgb: 0x211D18, alpha: 0.36), dark: UIColor(rgb: 0xF3EEE6, alpha: 0.34))

    // Accent (green)
    static let accent     = Color(light: UIColor(rgb: 0x2E9E5B), dark: UIColor(rgb: 0x54C883))
    static let accent2    = Color(light: UIColor(rgb: 0x34A862), dark: UIColor(rgb: 0x6FD497))
    static let accentSoft = Color(light: UIColor(rgb: 0x2E9E5B, alpha: 0.12), dark: UIColor(rgb: 0x54C883, alpha: 0.16))
    /// High-contrast ink used for text/glyphs that sit *on* the accent fill.
    static let onAccent   = Color(light: UIColor.white, dark: UIColor(rgb: 0x171008))

    // Macros + status
    static let protein = Color(light: UIColor(rgb: 0xE0574A), dark: UIColor(rgb: 0xFF6F61))
    static let carbs   = Color(light: UIColor(rgb: 0x3E84C6), dark: UIColor(rgb: 0x5AA0DE))
    static let fat     = Color(light: UIColor(rgb: 0xD99A2B), dark: UIColor(rgb: 0xE9B85A))
    static let good    = Color(light: UIColor(rgb: 0x3DA866), dark: UIColor(rgb: 0x63C089))

    // Surfaces
    static let chip        = Color(light: UIColor(rgb: 0x14100C, alpha: 0.05), dark: UIColor(white: 1, alpha: 0.07))
    static let hair        = Color(light: UIColor(rgb: 0x14100C, alpha: 0.08), dark: UIColor(white: 1, alpha: 0.09))
    static let track       = Color(light: UIColor(rgb: 0x14100C, alpha: 0.10), dark: UIColor(white: 1, alpha: 0.14))
    static let glassTint   = Color(light: UIColor(white: 1, alpha: 0.45), dark: UIColor(rgb: 0x2A2621, alpha: 0.45))
    static let glassBorder = Color(light: UIColor(white: 1, alpha: 0.85), dark: UIColor(white: 1, alpha: 0.14))
    static let glassInset  = Color(light: UIColor(white: 1, alpha: 0.70), dark: UIColor(white: 1, alpha: 0.08))
}

// MARK: - Warm background

/// The full-bleed warm gradient field behind every screen: a base vertical gradient
/// with three soft radial glows (two warm at the top, one cool at the bottom).
struct WarmBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let maxSide = max(w, h)

            ZStack {
                // Base vertical wash
                LinearGradient(
                    colors: scheme == .dark
                        ? [Color(red: 0.102, green: 0.086, blue: 0.067), Color(red: 0.075, green: 0.063, blue: 0.035)]
                        : [Color(red: 0.984, green: 0.965, blue: 0.941), Color(red: 0.953, green: 0.925, blue: 0.886)],
                    startPoint: .top, endPoint: .bottom
                )

                // Warm glow, top-left
                radial(
                    color: scheme == .dark
                        ? Color(red: 1.0, green: 0.55, blue: 0.24).opacity(0.22)
                        : Color(red: 1.0, green: 0.91, blue: 0.82).opacity(0.95),
                    center: UnitPoint(x: 0.16, y: -0.02), radius: maxSide * 0.8
                )

                // Warm glow, top-right
                radial(
                    color: scheme == .dark
                        ? Color(red: 1.0, green: 0.47, blue: 0.31).opacity(0.15)
                        : Color(red: 0.984, green: 0.851, blue: 0.769).opacity(0.9),
                    center: UnitPoint(x: 0.92, y: 0.12), radius: maxSide * 0.7
                )

                // Cool glow, bottom
                radial(
                    color: scheme == .dark
                        ? Color(red: 0.27, green: 0.43, blue: 0.63).opacity(0.20)
                        : Color(red: 0.906, green: 0.933, blue: 0.965).opacity(0.95),
                    center: UnitPoint(x: 0.70, y: 1.02), radius: maxSide * 0.85
                )
            }
        }
        .ignoresSafeArea()
    }

    private func radial(color: Color, center: UnitPoint, radius: CGFloat) -> some View {
        RadialGradient(colors: [color, color.opacity(0)], center: center, startRadius: 0, endRadius: radius)
    }
}

/// Back-compat alias — every screen uses `LiquidGlassBackground()` as its backdrop.
/// It now renders the warm gradient field.
struct LiquidGlassBackground: View {
    var body: some View { WarmBackground() }
}

// MARK: - Glass surfaces

struct GlassContainerModifier: ViewModifier {
    var cornerRadius: CGFloat = 26

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                shape
                    .fill(.ultraThinMaterial)
                    .overlay(shape.fill(Theme.glassTint))
            }
            .overlay {
                shape.strokeBorder(Theme.glassBorder, lineWidth: 1)
            }
            .clipShape(shape)
            .shadow(color: .black.opacity(0.28), radius: 22, x: 0, y: 16)
    }
}

extension View {
    func glassContainer(cornerRadius: CGFloat = 26) -> some View {
        modifier(GlassContainerModifier(cornerRadius: cornerRadius))
    }
}

/// The standard translucent card. Keeps the long-standing `GlassCard { … }` /
/// `GlassCard(padding:) { … }` call sites working.
struct GlassCard<Content: View>: View {
    let padding: CGFloat
    let cornerRadius: CGFloat
    let content: Content

    init(padding: CGFloat = 22, cornerRadius: CGFloat = 26, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .glassContainer(cornerRadius: cornerRadius)
    }
}

// MARK: - Type & layout helpers

/// Small uppercase, letter-spaced section label (e.g. "TODAY", "ENERGY BALANCE").
/// `icon` is accepted for source compatibility with older call sites but the revamp
/// renders a clean text-only label.
struct SectionHeader: View {
    let title: String
    var icon: String?

    init(title: String, icon: String? = nil) {
        self.title = title
        self.icon = icon
    }

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(1.3)
            .foregroundStyle(Theme.ink2)
    }
}

/// A two-line screen header: a soft "kicker" line above a large rounded title.
struct MHHeader: View {
    let kicker: String
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(kicker)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.ink2)
            Text(title)
                .font(.system(size: 29, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat

    init(spacing: CGFloat = 8) { self.spacing = spacing }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangeSubviews(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: .unspecified
            )
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var frames: [CGRect] = []

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            frames.append(CGRect(x: currentX, y: currentY, width: size.width, height: size.height))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
        }
        return (CGSize(width: maxWidth, height: currentY + lineHeight), frames)
    }
}

// MARK: - Button styles

struct PrimaryButtonStyle: ButtonStyle {
    var isEnabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(isEnabled ? Theme.onAccent : Theme.ink3)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isEnabled ? Theme.accent : Theme.chip)
            )
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.chip)
            )
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}

struct LiquidGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity)
            .padding()
            .glassContainer(cornerRadius: 16)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}

extension ButtonStyle where Self == LiquidGlassButtonStyle {
    static var liquidGlass: LiquidGlassButtonStyle { LiquidGlassButtonStyle() }
}

// MARK: - Input field

struct InputFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 15))
            .foregroundStyle(Theme.ink)
            .padding(.vertical, 13)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Theme.chip)
                    .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(Theme.hair, lineWidth: 1))
            )
    }
}

extension View {
    func inputFieldStyle() -> some View { modifier(InputFieldStyle()) }
}

// MARK: - Calorie ring

/// The hero ring on Today: a large progress arc with the "kcal left" headline inside.
struct CalorieRing: View {
    let eaten: Int
    let goal: Int

    private var remaining: Int { max(goal - eaten, 0) }
    private var progress: Double {
        guard goal > 0 else { return 0 }
        return min(Double(eaten) / Double(goal), 1.0)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.track, lineWidth: 13)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 13, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: progress)

            VStack(spacing: 0) {
                Text(remaining.formatted(.number.grouping(.automatic)))
                    .font(.system(size: 45, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .monospacedDigit()
                Text("kcal left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink2)
                    .padding(.top, 1)
            }
        }
        .frame(width: 214, height: 214)
    }
}

// MARK: - Macro track

/// A single macro column under the ring: name + dot, value / goal, and a progress bar.
struct MacroTrack: View {
    let name: String
    let value: Double
    let goal: Int
    let color: Color

    private var fraction: CGFloat {
        guard goal > 0 else { return 0 }
        return min(CGFloat(value) / CGFloat(goal), 1.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(name)
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.4)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.ink2)
            }
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("\(Int(value))")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .monospacedDigit()
                Text(" / \(goal) g")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.ink3)
            }
            .padding(.top, 9)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.track)
                    Capsule().fill(color).frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 6)
            .padding(.top, 9)
        }
    }
}

// MARK: - Segmented toggle

/// A pill-style segmented control matching the design's Week/Month and range switchers.
struct SegmentedToggle: View {
    let options: [String]
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let isOn = option == selection
                Button {
                    selection = option
                } label: {
                    Text(option)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isOn ? Theme.ink : Theme.ink2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isOn ? Theme.glassBorder : Color.clear)
                                .shadow(color: isOn ? .black.opacity(0.12) : .clear, radius: 3, y: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Theme.chip))
    }
}

// MARK: - Pill

struct StatusPill: View {
    let text: String
    var tone: Color = Theme.good

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tone)
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .background(Capsule().fill(tone.opacity(0.16)))
    }
}

// MARK: - Stat tile

/// A compact value tile (label / big value+unit / optional caption) used in Trends,
/// Settings and the day summary. Neutral by design — no good/bad framing.
struct StatTile: View {
    let label: String
    let value: String
    var unit: String? = nil
    var caption: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(Theme.ink2)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .monospacedDigit()
                if let unit {
                    Text(unit)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.ink2)
                }
            }
            .padding(.top, 7)
            if let caption {
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.ink3)
                    .padding(.top, 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.chip))
    }
}

// MARK: - Macro ring (legacy small ring, retained for compatibility)

struct MacroRingView: View {
    let value: Double
    let goal: Double
    let color: Color
    let label: String
    let unit: String

    private var progress: Double {
        guard goal > 0 else { return 0 }
        return min(value / goal, 1.0)
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().stroke(color.opacity(0.2), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(Int(value))")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text(unit).font(.system(size: 10)).foregroundStyle(Theme.ink2)
                }
            }
            .frame(width: 60, height: 60)
            Text(label).font(.caption).foregroundStyle(Theme.ink2)
        }
    }
}
