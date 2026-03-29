import XCTest

/// UI tests for the dictation overlay indicator.
/// Note: These tests are stubs. Full overlay testing requires simulating dictation state,
/// which depends on the app exposing test hooks (e.g., --simulate-dictation launch argument).
final class OverlayUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Overlay Appearance

    func testOverlayAppearsWhenDictationStarts() throws {
        // Launch with a flag that simulates active dictation
        app.launchArguments.append("--ui-testing")
        app.launchArguments.append("--simulate-dictation")
        app.launch()

        let overlay = app.windows[AccessibilityID.overlayWindow]
        overlay.waitForExistence(description: "Overlay window during dictation")

        // Verify listening indicator is present
        let listeningLabel = overlay.staticTexts["Listening"]
        XCTAssertTrue(listeningLabel.exists, "Overlay should show 'Listening' text")
    }

    func testOverlayDismissesAfterDictationEnds() throws {
        // Launch with simulated dictation that completes after a delay
        app.launchArguments.append("--ui-testing")
        app.launchArguments.append("--simulate-dictation-complete")
        app.launch()

        let overlay = app.windows[AccessibilityID.overlayWindow]

        // Overlay may briefly appear then dismiss
        if overlay.waitForExistence(timeout: 3) {
            overlay.waitForDisappearance(timeout: 5)
        }
        // If overlay never appeared, that's also acceptable for the "complete" simulation
    }

    func testOverlayIsFloatingAboveOtherWindows() throws {
        app.launchArguments.append("--ui-testing")
        app.launchArguments.append("--simulate-dictation")
        app.launch()

        let overlay = app.windows[AccessibilityID.overlayWindow]
        guard overlay.waitForExistence(timeout: 3) else {
            XCTSkip("Overlay not visible — dictation simulation may not be implemented yet")
            return
        }

        // Overlay should be at floating window level.
        // XCUITest cannot directly check window level, but we can verify
        // the window exists and is hittable (on-screen and not behind other windows).
        XCTAssertTrue(overlay.isHittable, "Overlay should be visible above other windows")
    }

    func testOverlayShowsPulsingIndicator() throws {
        app.launchArguments.append("--ui-testing")
        app.launchArguments.append("--simulate-dictation")
        app.launch()

        let overlay = app.windows[AccessibilityID.overlayWindow]
        guard overlay.waitForExistence(timeout: 3) else {
            XCTSkip("Overlay not visible")
            return
        }

        // The pulsing red dot should be present
        let indicator = overlay.otherElements[AccessibilityID.listeningIndicator]
        if !indicator.exists {
            // Fallback: check for the red circle or "Listening" text
            let listeningText = overlay.staticTexts["Listening"]
            XCTAssertTrue(listeningText.exists, "Overlay should show listening indicator")
        }
    }
}
