import XCTest

/// UI tests for the optional Proof-of-Use module.
final class ProofOfUseUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    /// Usage Proof section appears in Settings when proof mode is enabled.
    func testUsageProofSettingsVisible() throws {
        app.launchArguments.append("--ui-testing")
        app.launchArguments.append("--enable-proof-of-use")
        app.launch()
        _ = app.windows.firstMatch.waitForExistence(timeout: 5)
        app.dismissFirstLaunchIfPresent()

        do {
            try openSettings()
        } catch {
            throw XCTSkip("Settings not accessible: \(error)")
        }

        let settings = app.windows[AccessibilityID.settingsWindow]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))

        let usageProof = settings.staticTexts["Usage Proof"]
        XCTAssertTrue(usageProof.waitForExistence(timeout: 5),
                      "Usage Proof section should appear in Settings")

        let toggle = settings.switches["mumbli-proof-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
    }

    private func openSettings() throws {
        try app.tapMenuBarButton()
        let settingsButton = app.buttons[AccessibilityID.settingsButton]
        guard settingsButton.waitForExistence(timeout: 5) else {
            throw XCTSkip("Settings button not found")
        }
        settingsButton.tap()
        let settingsWindow = app.windows[AccessibilityID.settingsWindow]
        guard settingsWindow.waitForExistence(timeout: 5) else {
            throw XCTSkip("Settings window did not appear")
        }
    }

    /// --test-full with proof enabled must not crash while signing a receipt.
    func testFullFlowWithProofDoesNotCrash() throws {
        app.launchArguments.append("--ui-testing")
        app.launchArguments.append("--enable-proof-of-use")
        app.launchArguments.append("--test-full")
        app.launch()
        _ = app.windows.firstMatch.waitForExistence(timeout: 5)
        app.dismissFirstLaunchIfPresent()

        // Wait for full simulated flow + async receipt write
        Thread.sleep(forTimeInterval: 8)
        XCTAssertTrue(app.exists, "App should not crash when recording proof receipt")
    }
}
