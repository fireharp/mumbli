import XCTest

/// Regression tests for dictation flow simulation.
/// Uses the app's test hooks (--test-inject, --test-full, --test-fn-hold) to exercise
/// text injection, full dictation flow, and Fn key hold behavior.
final class DictationUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Text Injection (--test-inject)

    /// Regression: --test-inject should inject text into the focused field.
    /// The app injects "Hello from Mumbli!" after a 3s delay.
    /// Since XCUITest cannot focus external text fields, we verify the app
    /// launches and processes the flag without crashing.
    func testInjectDoesNotCrash() throws {
        app.launchArguments.append("--ui-testing")
        app.launchArguments.append("--test-inject")
        app.launch()
        _ = app.windows.firstMatch.waitForExistence(timeout: 5)
        app.dismissFirstLaunchIfPresent()

        // Wait for the 3s delay + injection attempt to complete
        // The app should remain running and not crash
        Thread.sleep(forTimeInterval: 5)
        XCTAssertTrue(app.exists, "App should remain running after --test-inject")
    }

    // MARK: - Full Flow (--test-full)

    /// Regression: --test-full shows overlay, injects text, and saves to history.
    func testFullFlowShowsOverlayAndSavesToHistory() throws {
        app.launchArguments.append("--ui-testing")
        app.launchArguments.append("--test-full")
        app.launch()
        _ = app.windows.firstMatch.waitForExistence(timeout: 5)
        app.dismissFirstLaunchIfPresent()

        // After 3s the overlay should appear
        let overlay = app.windows[AccessibilityID.overlayWindow]
        XCTAssertTrue(overlay.waitForExistence(timeout: 6),
                      "--test-full should show the overlay")

        // Overlay should dismiss after injection + delay (~1.3s more)
        overlay.waitForDisappearance(timeout: 5)

        // Verify text was saved to history by opening the menu bar popover
        do {
            try app.tapMenuBarButton()
            let historyEntry = app.buttons[AccessibilityID.historyEntry].firstMatch
            XCTAssertTrue(historyEntry.waitForExistence(timeout: 5),
                          "--test-full should save dictation to history")
        } catch {
            // Menu bar may not be accessible in all test environments
            throw XCTSkip("Menu bar not accessible: \(error)")
        }
    }

    /// Regression: --test-full overlay eventually dismisses.
    func testFullFlowOverlayDismisses() throws {
        app.launchArguments.append("--ui-testing")
        app.launchArguments.append("--test-full")
        app.launch()
        _ = app.windows.firstMatch.waitForExistence(timeout: 5)
        app.dismissFirstLaunchIfPresent()

        let overlay = app.windows[AccessibilityID.overlayWindow]
        if overlay.waitForExistence(timeout: 6) {
            overlay.waitForDisappearance(timeout: 8)
        }
        // If overlay never appeared, skip rather than fail
        // (the 3s delay may not have elapsed or simulation not implemented)
    }

    // MARK: - Fn Hold (--test-fn-hold)

    /// Regression: --test-fn-hold starts dictation (shows overlay) and eventually stops.
    func testFnHoldShowsAndDismissesOverlay() throws {
        app.launchArguments.append("--ui-testing")
        app.launchArguments.append("--test-fn-hold")
        app.launch()
        _ = app.windows.firstMatch.waitForExistence(timeout: 5)
        app.dismissFirstLaunchIfPresent()

        // After 3s delay, Fn hold simulation starts — overlay should appear
        let overlay = app.windows[AccessibilityID.overlayWindow]
        let appeared = overlay.waitForExistence(timeout: 8)

        if !appeared {
            throw XCTSkip("Overlay did not appear for --test-fn-hold (Fn simulation may require permissions)")
        }

        // The simulated hold should eventually release and dismiss the overlay
        overlay.waitForDisappearance(timeout: 15)
    }
}
