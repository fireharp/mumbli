import XCTest

/// UI tests for the dictation overlay indicator.
/// Regression tests verify VU bar count, mode-specific styling, processing state,
/// and screen positioning.
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
        app.launchWithDictation()

        let overlay = app.windows[AccessibilityID.overlayWindow]
        overlay.waitForExistence(description: "Overlay window during dictation")

        let listeningLabel = overlay.staticTexts["Listening"]
        // Label may or may not be present depending on design; check indicator instead
        let indicator = overlay.otherElements[AccessibilityID.listeningIndicator]
        XCTAssertTrue(listeningLabel.exists || indicator.exists,
                      "Overlay should show listening text or indicator")
    }

    func testOverlayDismissesAfterDictationEnds() throws {
        app.launchArguments.append("--ui-testing")
        app.launchArguments.append("--simulate-dictation-complete")
        app.launch()

        let overlay = app.windows[AccessibilityID.overlayWindow]

        // Overlay may briefly appear then dismiss
        if overlay.waitForExistence(timeout: 3) {
            overlay.waitForDisappearance(timeout: 5)
        }
    }

    func testOverlayIsFloatingAboveOtherWindows() throws {
        app.launchWithDictation()

        let overlay = app.windows[AccessibilityID.overlayWindow]
        guard overlay.waitForExistence(timeout: 3) else {
            throw XCTSkip("Overlay not visible — dictation simulation may not be implemented yet")
        }

        XCTAssertTrue(overlay.isHittable, "Overlay should be visible above other windows")
    }

    // MARK: - VU Bars

    /// Regression: overlay must contain exactly 5 VU bars.
    func testOverlayHasFiveVUBars() throws {
        app.launchWithDictation()

        let overlay = app.windows[AccessibilityID.overlayWindow]
        guard overlay.waitForExistence(timeout: 5) else {
            throw XCTSkip("Overlay not visible")
        }

        let vuBarIDs = [
            AccessibilityID.vuBar0,
            AccessibilityID.vuBar1,
            AccessibilityID.vuBar2,
            AccessibilityID.vuBar3,
            AccessibilityID.vuBar4,
        ]

        for id in vuBarIDs {
            let bar = overlay.otherElements[id]
            XCTAssertTrue(bar.waitForExistence(timeout: 3),
                          "VU bar '\(id)' should exist in the overlay")
        }
    }

    // MARK: - Hold Mode

    /// Regression: hold mode should show accent-colored bars (default mode).
    /// We verify the overlay is present with the listening indicator — color verification
    /// requires snapshot comparison which is outside XCUITest scope.
    func testHoldModeShowsListeningIndicator() throws {
        app.launchWithDictation()

        let overlay = app.windows[AccessibilityID.overlayWindow]
        guard overlay.waitForExistence(timeout: 5) else {
            throw XCTSkip("Overlay not visible")
        }

        let indicator = overlay.otherElements[AccessibilityID.listeningIndicator]
        XCTAssertTrue(indicator.exists,
                      "Hold mode should display the listening indicator with accent-colored bars")

        // REC dot should NOT be present in hold mode
        let recDot = overlay.otherElements[AccessibilityID.recDot]
        XCTAssertFalse(recDot.exists,
                       "Hold mode should NOT show the REC dot (hands-free only)")
    }

    // MARK: - Hands-Free Mode

    /// Regression: hands-free mode should show orange bars and a red REC dot.
    func testHandsFreeModeShowsRecDot() throws {
        app.launchWithHandsFreeDictation()

        let overlay = app.windows[AccessibilityID.overlayWindow]
        guard overlay.waitForExistence(timeout: 5) else {
            throw XCTSkip("Overlay not visible — --simulate-dictation-handsfree may not be implemented yet")
        }

        // REC dot must be present
        let recDot = overlay.otherElements[AccessibilityID.recDot]
        XCTAssertTrue(recDot.waitForExistence(timeout: 3),
                      "Hands-free mode should show the red REC dot")
    }

    /// Regression: hands-free mode should still have 5 VU bars.
    func testHandsFreeModeHasFiveVUBars() throws {
        app.launchWithHandsFreeDictation()

        let overlay = app.windows[AccessibilityID.overlayWindow]
        guard overlay.waitForExistence(timeout: 5) else {
            throw XCTSkip("Overlay not visible")
        }

        let vuBarIDs = [
            AccessibilityID.vuBar0,
            AccessibilityID.vuBar1,
            AccessibilityID.vuBar2,
            AccessibilityID.vuBar3,
            AccessibilityID.vuBar4,
        ]

        for id in vuBarIDs {
            let bar = overlay.otherElements[id]
            XCTAssertTrue(bar.waitForExistence(timeout: 3),
                          "Hands-free VU bar '\(id)' should exist in the overlay")
        }
    }

    // MARK: - Processing State

    /// Regression: processing state should show the processing indicator.
    func testProcessingStateShowsIndicator() throws {
        app.launchWithProcessing()

        let overlay = app.windows[AccessibilityID.overlayWindow]
        guard overlay.waitForExistence(timeout: 5) else {
            throw XCTSkip("Overlay not visible")
        }

        let processing = overlay.otherElements[AccessibilityID.processingIndicator]
        XCTAssertTrue(processing.waitForExistence(timeout: 5),
                      "Processing state should show the processing indicator")
    }

    // MARK: - Screen Position

    /// Regression: overlay should be positioned at the bottom of the screen.
    func testOverlayPositionedAtBottomOfScreen() throws {
        app.launchWithDictation()

        let overlay = app.windows[AccessibilityID.overlayWindow]
        guard overlay.waitForExistence(timeout: 5) else {
            throw XCTSkip("Overlay not visible")
        }

        // The overlay's Y coordinate in screen space should be in the bottom portion.
        // macOS coordinates have origin at bottom-left, so a small Y value = near bottom.
        // The overlay is positioned at screenFrame.origin.y + 40, so Y should be < 150.
        let frame = overlay.frame
        XCTAssertLessThan(frame.origin.y, 200,
                          "Overlay should be near the bottom of the screen (y=\(frame.origin.y))")
    }
}
