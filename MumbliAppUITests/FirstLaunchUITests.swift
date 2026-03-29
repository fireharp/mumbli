import XCTest

/// UI tests for the first launch permission flow.
final class FirstLaunchUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helpers

    /// Tap the advance button ("Skip for now" or "Continue") on permission steps.
    private func tapAdvanceButton() {
        let skip = app.buttons["Skip for now"].firstMatch
        let cont = app.buttons["Continue"].firstMatch
        if skip.waitForExistence(timeout: 2) {
            skip.tap()
        } else if cont.waitForExistence(timeout: 2) {
            cont.tap()
        } else {
            XCTFail("Neither 'Skip for now' nor 'Continue' button found")
        }
    }

    // MARK: - Tests

    func testFirstLaunchShowsWelcomeScreen() throws {
        app.launchAsFirstLaunch()

        let welcomeTitle = app.staticTexts["Welcome to Mumbli"]
        welcomeTitle.waitForExistence(description: "Welcome title")

        let getStarted = app.buttons["Get Started"]
        XCTAssertTrue(getStarted.exists, "Get Started button should be visible")
    }

    func testFirstLaunchStepProgression() throws {
        app.launchAsFirstLaunch()

        // Step 1: Welcome
        let getStarted = app.buttons["Get Started"]
        getStarted.waitForExistence(description: "Get Started button")
        getStarted.tap()

        // Step 2: Microphone
        let micTitle = app.staticTexts["Microphone Access"]
        micTitle.waitForExistence(description: "Microphone step title")
        tapAdvanceButton()

        // Step 3: Accessibility
        let accessTitle = app.staticTexts["Accessibility Access"]
        accessTitle.waitForExistence(description: "Accessibility step title")
        tapAdvanceButton()

        // Step 4: Ready
        let readyTitle = app.staticTexts["You're all set!"]
        readyTitle.waitForExistence(description: "Ready step title")
    }

    func testFirstLaunchCompletionDismissesFlow() throws {
        app.launchAsFirstLaunch()

        app.buttons["Get Started"].waitForExistence().tap()
        tapAdvanceButton()
        tapAdvanceButton()

        let startUsing = app.buttons["Start Using Mumbli"]
        startUsing.waitForExistence(description: "Start Using button")
        startUsing.tap()

        let welcomeTitle = app.staticTexts["Welcome to Mumbli"]
        welcomeTitle.waitForDisappearance()
    }

    func testSubsequentLaunchSkipsFirstLaunchFlow() throws {
        // First, complete the first launch flow to set hasCompletedFirstLaunch
        app.launchAsFirstLaunch()
        app.buttons["Get Started"].waitForExistence().tap()
        tapAdvanceButton()
        tapAdvanceButton()
        let startUsing = app.buttons["Start Using Mumbli"]
        startUsing.waitForExistence(description: "Start Using button")
        // Use coordinate tap — button may not be "hittable" due to window layering
        startUsing.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.terminate()

        // Relaunch WITHOUT --reset-first-launch
        let freshApp = XCUIApplication()
        freshApp.launchArguments.append("--ui-testing")
        freshApp.launch()

        let welcomeTitle = freshApp.staticTexts["Welcome to Mumbli"]
        XCTAssertFalse(welcomeTitle.waitForExistence(timeout: 2),
                       "Welcome screen should not appear on subsequent launches")
    }
}
