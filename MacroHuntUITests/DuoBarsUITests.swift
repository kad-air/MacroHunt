import UIKit
import XCTest

/// Proves the iPhone Duo HIG bar migration (CLAUDE.md, "iPhone Duo"): the four tabs are a
/// *system* `TabView` and the "Add meal" action is a real `.toolbar` item attached to each
/// tab root's NavigationStack content — and that both land where Apple's HIG says a bar's
/// items belong for the window's current pose: a VERTICAL column pinned to the TRAILING
/// edge on the Duo's cover display or its inner display in landscape (the two poses the
/// system lays bars out vertically for), or the ordinary horizontal bars everywhere else
/// (a horizontal tab row along the bottom, a top bar row for the action).
///
/// A hand-drawn tab bar (what `MainTabView` used to be) fails the Duo branch because it
/// stays a horizontal row at the bottom; a re-hidden navigation bar fails everywhere because
/// the "Add meal" item vanishes.
///
/// `MACROHUNT_DEBUG_ANTHROPIC_KEY` seeds a bogus-but-present Anthropic key so onboarding
/// (which blocks until a key exists) never covers the tabs. Nothing is written to the
/// keychain; the reflection call fails harmlessly.
///
/// Runs via `scripts/duo-check.sh` on the iPhone Duo simulator (the `MacroHunt` scheme's
/// test action picks this target up). On an iPhone/iPad simulator it expects the ordinary
/// horizontal bars instead, so it passes there too — the device is read from the simulator's
/// model identifier, never from a width threshold, and the pose from the screen the app is
/// actually drawing on (`activeScreen()`), never `XCUIScreen.main` or `app.frame`.
///
/// Each surface is attached to the `.xcresult` with `.keepAlways`, so a run on the Duo doubles
/// as the eyes-on capture: `xcrun xcresulttool export attachments --path <xcresult> --output-path <dir>`.
final class DuoBarsUITests: XCTestCase {
    func testTabsAndAddMealAreSystemBarItems() {
        let app = XCUIApplication()
        app.launchEnvironment = ["MACROHUNT_DEBUG_ANTHROPIC_KEY": "ui-test"]
        app.launch()

        let tabs = ["Today", "Calendar", "Trends", "Settings"].map { loose(app, $0) }
        for (label, element) in zip(["Today", "Calendar", "Trends", "Settings"], tabs) {
            XCTAssertTrue(element.waitForExistence(timeout: 20), "\"\(label)\" tab never appeared")
            XCTAssertTrue(element.isHittable, "\"\(label)\" tab exists but isn't hittable")
        }

        let screen = currentScreenSize(app)
        XCTContext.runActivity(named: "Pose: \(Int(screen.width))×\(Int(screen.height))pt, \(lastScreenDescription)") { _ in }
        assertTabBarAxis(tabs, screenSize: screen)

        // The action must exist on every root it's declared on, not just the first tab.
        for tab in ["Today", "Calendar", "Trends"] {
            loose(app, tab).tap()
            let add = loose(app, "Add meal")
            XCTAssertTrue(add.waitForExistence(timeout: 20), "\"Add meal\" never appeared on \(tab)")
            XCTAssertTrue(add.isHittable, "\"Add meal\" exists but isn't hittable on \(tab)")
            assertActionAxis(add, screenSize: currentScreenSize(app), screen: tab)
            attachScreenshot(tab.lowercased())
        }
        loose(app, "Settings").tap()
        attachScreenshot("settings")

        // The Add-meal sheet's Cancel is a `.cancellationAction` bar item (title + symbol); the
        // hand-drawn xmark chip it replaced would not be laid out by the system.
        loose(app, "Today").tap()
        loose(app, "Add meal").tap()
        let cancel = loose(app, "Cancel")
        XCTAssertTrue(cancel.waitForExistence(timeout: 20), "\"Cancel\" never appeared on the Add-meal sheet")
        XCTAssertTrue(cancel.isHittable, "\"Cancel\" exists but isn't hittable on the Add-meal sheet")
        attachScreenshot("add-meal")
        cancel.tap()
        XCTAssertTrue(loose(app, "Add meal").waitForExistence(timeout: 20), "Today's \"Add meal\" did not come back after Cancel")
    }

    // MARK: - Helpers

    /// Loose-by-label lookup across every element kind: on the Duo the vertical bar may not be
    /// classified as a `tabBars`/`navigationBars` element the way a horizontal bar is.
    private func loose(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    /// Only an iPhone Duo lays bars out vertically, and only in two of its poses: the COVER
    /// display (~466×678pt, portrait) and the INNER display in landscape (~951×669pt, the
    /// fully-open pose). A width threshold can't tell the cover from an iPhone (402pt), so the
    /// device is read from the simulator's own model identifier — `iPhone19,4` is the Duo
    /// (CoreSimulator's `iPhone Duo.simdevicetype` profile) — and the pose from the screen's
    /// aspect. On a physical device the runner exposes no such variable and the
    /// horizontal-bar branch applies.
    private var isDuoSimulator: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["SIMULATOR_MODEL_IDENTIFIER"] == "iPhone19,4"
            || (env["SIMULATOR_DEVICE_NAME"] ?? "").localizedCaseInsensitiveContains("duo")
    }

    /// Kept in the `.xcresult` regardless of outcome (see the class doc).
    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: activeScreen().screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// The screen the app is actually drawing on. On the Duo, `XCUIScreen.main` is the COVER
    /// display even when the device is open, so its screenshot is a black 466×678pt image while
    /// the app is on the lit 951×669pt inner display; a pose read from it lands on the
    /// vertical-bar branch for the wrong reason and measures the trailing edge against the
    /// wrong width. Every screen is shot, the black ones (the display that is off in the
    /// current pose) are dropped, and the largest lit one wins. A phone or iPad has one screen,
    /// so this is `XCUIScreen.main` there.
    private func activeScreen() -> (screenshot: XCUIScreenshot, size: CGSize, description: String) {
        var lit: [(XCUIScreenshot, CGSize, Int)] = []
        var seen: [String] = []
        for screen in XCUIScreen.screens {
            let shot = screen.screenshot()
            let size = shot.image.size
            let brightness = Self.meanBrightness(of: shot.image)
            seen.append("\(Int(size.width))×\(Int(size.height))@\(brightness)")
            if brightness > 5 { lit.append((shot, size, brightness)) }
        }
        let description = "screens [\(seen.joined(separator: ", "))]"
        if let best = lit.max(by: { $0.1.width * $0.1.height < $1.1.width * $1.1.height }) {
            return (best.0, best.1, description)
        }
        let main = XCUIScreen.main.screenshot()
        return (main, main.image.size, description + " (none lit; using main)")
    }

    /// Mean of a 16×16 downsample's RGB bytes, 0...255. Enough to tell an off display (0)
    /// from anything drawn on one.
    private static func meanBrightness(of image: UIImage) -> Int {
        guard let cg = image.cgImage else { return 0 }
        let side = 16
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = CGContext(
            data: &pixels, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 0 }
        context.interpolationQuality = .low
        context.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
        var total = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            total += Int(pixels[i]) + Int(pixels[i + 1]) + Int(pixels[i + 2])
        }
        return total / (side * side * 3)
    }

    /// The size of what is actually on screen, in points. NOT `app.frame`: on the Duo's inner
    /// display in the fully-open (landscape) pose `app.frame` still reports the unrotated
    /// 669×951 while every element frame is in the landscape screen space, so a pose derived
    /// from the window frame picks the wrong branch. `activeScreen()` makes sure it is also the
    /// screen the app is on.
    private func currentScreenSize(_ app: XCUIApplication) -> CGSize {
        let screen = activeScreen()
        lastScreenDescription = screen.description
        return screen.size.width > 0 && screen.size.height > 0 ? screen.size : app.frame.size
    }

    /// What `activeScreen()` saw on the last pose read, folded into assertion messages so a
    /// failure says which display it measured.
    private var lastScreenDescription = ""

    private func isDuoPose(_ screenSize: CGSize) -> Bool {
        isDuoSimulator && (screenSize.width > screenSize.height || screenSize.width < 500)
    }

    private func describe(_ screenSize: CGSize, _ frames: [CGRect]) -> String {
        "\(isDuoSimulator ? "Duo" : "non-Duo") device, \(isDuoPose(screenSize) ? "vertical-bar" : "horizontal-bar") pose, screen \(screenSize.width)×\(screenSize.height), \(lastScreenDescription), frames \(frames)"
    }

    /// Tabs: a vertical column at the trailing edge in a Duo pose, else a horizontal row
    /// hugging one screen edge — the bottom on an iPhone, the TOP on an iPad (iPadOS draws
    /// a system tab bar there). The old floating bar also sat at the bottom, so the non-Duo
    /// branch is only a sanity check — the Duo branch is the proof.
    private func assertTabBarAxis(_ elements: [XCUIElement], screenSize: CGSize, file: StaticString = #filePath, line: UInt = #line) {
        let frames = elements.map(\.frame)
        let pose = describe(screenSize, frames)
        if isDuoPose(screenSize) {
            let midXs = frames.map(\.midX)
            for midX in midXs.dropFirst() {
                XCTAssertLessThan(abs(midX - midXs[0]), 2, "Tabs: expected a VERTICAL column (\(pose)) but frames aren't x-aligned", file: file, line: line)
            }
            for frame in frames {
                XCTAssertGreaterThan(frame.maxX, screenSize.width - 100, "Tabs: expected items pinned to the TRAILING edge (\(pose))", file: file, line: line)
            }
        } else {
            let midYs = frames.map(\.midY)
            for midY in midYs.dropFirst() {
                XCTAssertLessThan(abs(midY - midYs[0]), 2, "Tabs: expected a HORIZONTAL row (\(pose)) but frames aren't y-aligned", file: file, line: line)
            }
            for frame in frames {
                XCTAssertTrue(frame.midY < 120 || frame.midY > screenSize.height - 120, "Tabs: expected a tab row at the top or bottom edge (\(pose)) but a frame is mid-screen", file: file, line: line)
            }
        }
    }

    /// The tab-root action: within the trailing strip in a Duo pose, else in the top bar.
    private func assertActionAxis(_ element: XCUIElement, screenSize: CGSize, screen: String, file: StaticString = #filePath, line: UInt = #line) {
        let frame = element.frame
        let pose = describe(screenSize, [frame])
        if isDuoPose(screenSize) {
            XCTAssertGreaterThan(frame.maxX, screenSize.width - 100, "\(screen): expected \"Add meal\" pinned to the TRAILING edge (\(pose))", file: file, line: line)
        } else {
            XCTAssertLessThan(frame.midY, 120, "\(screen): expected \"Add meal\" in the top bar (\(pose))", file: file, line: line)
        }
    }
}
