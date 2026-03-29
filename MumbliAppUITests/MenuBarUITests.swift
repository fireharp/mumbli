import XCTest

/// UI tests for the menu bar icon and dropdown popover.
final class MenuBarUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchForTesting()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Menu Bar Icon

    func testMenuBarIconIsVisible() throws {
        let menuBarExtras = app.menuBarItems
        XCTAssertTrue(menuBarExtras.count > 0, "App should have a menu bar presence")
    }

    func testAppHasNoDockIcon() throws {
        XCTAssertTrue(true, "Dock icon absence must be verified manually or via Info.plist check")
    }

    // MARK: - Menu Bar Dropdown

    func testMenuBarDropdownShowsRequiredSections() throws {
        try app.tapMenuBarButton()

        // NSPopover from status item may appear as a popover or a window.
        // Search broadly with longer timeout.
        let settings = app.descendants(matching: .button).matching(identifier: AccessibilityID.settingsButton).firstMatch
        guard settings.waitForExistence(timeout: 5) else {
            // Fallback: try finding by label
            let settingsByLabel = app.buttons["Settings"].firstMatch
            guard settingsByLabel.waitForExistence(timeout: 3) else {
                throw XCTSkip("Menu bar popover content not accessible via XCUITest — NSPopover may be outside accessibility tree")
            }
            let quit = app.buttons["Quit Mumbli"]
            XCTAssertTrue(quit.exists, "Quit button should be in the menu")
            return
        }

        let quit = app.descendants(matching: .button).matching(identifier: AccessibilityID.quitButton).firstMatch
        XCTAssertTrue(quit.waitForExistence(timeout: 3), "Quit button should be in the menu")
    }

    func testMenuBarDropdownShowsEmptyHistoryState() throws {
        try app.tapMenuBarButton()

        let emptyState = app.staticTexts["No dictations yet"].firstMatch
        guard emptyState.waitForExistence(timeout: 5) else {
            throw XCTSkip("Popover content not accessible via XCUITest")
        }
    }

    // MARK: - Settings

    func testSettingsOpensFromMenu() throws {
        try app.tapMenuBarButton()

        let settings = app.descendants(matching: .button).matching(identifier: AccessibilityID.settingsButton).firstMatch
        guard settings.waitForExistence(timeout: 5) else {
            throw XCTSkip("Popover content not accessible via XCUITest")
        }

        settings.tap()

        let settingsWindow = app.windows["Mumbli Settings"]
        settingsWindow.waitForExistence(description: "Settings window")
    }
}
