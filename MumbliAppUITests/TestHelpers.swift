import XCTest

// MARK: - Accessibility Identifiers

/// Central registry of accessibility identifiers used in UI tests.
/// The app should set these identifiers on the corresponding UI elements.
enum AccessibilityID {
    // Menu bar
    static let menuBarButton = "mumbli-menu-bar-button"
    static let menuBarPopover = "mumbli-menu-bar-popover"
    static let settingsButton = "mumbli-settings-button"
    static let quitButton = "mumbli-quit-button"

    // History
    static let historyList = "mumbli-history-list"
    static let historyEntry = "mumbli-history-entry"
    static let historyEmptyState = "mumbli-history-empty"
    static let historyCopyCheckmark = "mumbli-history-checkmark"

    // Overlay
    static let overlayWindow = "mumbli-overlay-window"
    static let listeningIndicator = "mumbli-listening-indicator"
    static let listeningLabel = "mumbli-listening-label"

    // First launch
    static let firstLaunchWindow = "mumbli-first-launch"
    static let welcomeTitle = "mumbli-welcome-title"
    static let getStartedButton = "mumbli-get-started"
    static let grantMicButton = "mumbli-grant-mic"
    static let openAccessibilityButton = "mumbli-open-accessibility"
    static let startUsingButton = "mumbli-start-using"
    static let stepIndicator = "mumbli-step-indicator"

    // Overlay — VU bars and mode indicators
    static let vuBar0 = "mumbli-vu-bar-0"
    static let vuBar1 = "mumbli-vu-bar-1"
    static let vuBar2 = "mumbli-vu-bar-2"
    static let vuBar3 = "mumbli-vu-bar-3"
    static let vuBar4 = "mumbli-vu-bar-4"
    static let recDot = "mumbli-rec-dot"
    static let processingIndicator = "mumbli-processing-indicator"

    // Settings
    static let settingsWindow = "mumbli-settings-window"
    static let microphonePicker = "mumbli-mic-picker"

    // Settings — sections (matched by section title text)
    static let sectionAudioInput = "Audio Input"
    static let sectionAPIKeys = "API Keys"
    static let sectionTextPolishing = "Text Polishing"
    static let sectionShortcuts = "Shortcuts"
    static let sectionAbout = "About"

    // Settings — API key fields
    static let elevenLabsKeyField = "mumbli-elevenlabs-key"
    static let openAIKeyField = "mumbli-openai-key"

    // Settings — polishing controls
    static let polishingToggle = "Enable text polishing"
    static let polishingPresetPicker = "Preset"
    static let polishingModelPicker = "Model"
    static let customPromptEditor = "Enter your custom polishing prompt..."
    static let customModelField = "e.g. gpt-4-turbo"
}

// MARK: - XCUIApplication Helpers

extension XCUIApplication {
    /// Launch the app with a flag indicating UI test mode.
    /// The app switches to .regular activation policy so XCUITest's
    /// automation server can connect (LSUIElement apps are backgrounded).
    func launchForTesting() {
        launchArguments.append("--ui-testing")
        launch()
        _ = windows.firstMatch.waitForExistence(timeout: 5)
        dismissFirstLaunchIfPresent()
    }

    /// Launch the app simulating a first launch (no saved state).
    func launchAsFirstLaunch() {
        launchArguments.append("--ui-testing")
        launchArguments.append("--reset-first-launch")
        launch()
        _ = windows.firstMatch.waitForExistence(timeout: 5)
    }

    /// Launch with simulated dictation in hold mode.
    func launchWithDictation() {
        launchArguments.append("--ui-testing")
        launchArguments.append("--simulate-dictation")
        launch()
        _ = windows.firstMatch.waitForExistence(timeout: 5)
        dismissFirstLaunchIfPresent()
    }

    /// Launch with simulated dictation in hands-free mode.
    func launchWithHandsFreeDictation() {
        launchArguments.append("--ui-testing")
        launchArguments.append("--simulate-dictation-handsfree")
        launch()
        _ = windows.firstMatch.waitForExistence(timeout: 5)
        dismissFirstLaunchIfPresent()
    }

    /// Launch with simulated dictation that transitions to processing state.
    func launchWithProcessing() {
        launchArguments.append("--ui-testing")
        launchArguments.append("--simulate-dictation-processing")
        launch()
        _ = windows.firstMatch.waitForExistence(timeout: 5)
        dismissFirstLaunchIfPresent()
    }

    /// Launch with pre-populated history entries for testing.
    func launchWithHistory() {
        launchArguments.append("--ui-testing")
        launchArguments.append("--seed-history")
        launch()
        _ = windows.firstMatch.waitForExistence(timeout: 5)
        dismissFirstLaunchIfPresent()
    }

    /// If the first launch flow is showing, complete it quickly so tests
    /// that need the main app state can proceed.
    func dismissFirstLaunchIfPresent() {
        let welcomeTitle = staticTexts["Welcome to Mumbli"]
        guard welcomeTitle.waitForExistence(timeout: 2) else { return }

        buttons["Get Started"].tap()

        // The button label is "Skip for now" or "Continue" depending on permission state
        tapFirstLaunchAdvanceButton()
        tapFirstLaunchAdvanceButton()

        let startUsing = buttons["Start Using Mumbli"]
        if startUsing.waitForExistence(timeout: 3) {
            startUsing.tap()
        }
    }

    /// Tap whichever advance button is visible in the first launch flow.
    private func tapFirstLaunchAdvanceButton() {
        let skip = buttons["Skip for now"].firstMatch
        let cont = buttons["Continue"].firstMatch
        if skip.waitForExistence(timeout: 2) {
            skip.tap()
        } else if cont.waitForExistence(timeout: 2) {
            cont.tap()
        }
    }

    /// Find the menu bar status item and tap it.
    /// NSStatusItem can report offscreen coordinates in XCUITest,
    /// so we use coordinate-based tap as a workaround.
    func tapMenuBarButton() throws {
        let statusItem = statusItems[AccessibilityID.menuBarButton]
        guard statusItem.waitForExistence(timeout: 5) else {
            throw XCTSkip("Menu bar button not accessible in UI tests")
        }
        statusItem.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }
}

// MARK: - Element Query Helpers

extension XCUIElement {
    /// Wait for the element to exist with a timeout, then return it.
    @discardableResult
    func waitForExistence(description: String = "", timeout: TimeInterval = 5) -> XCUIElement {
        let exists = self.waitForExistence(timeout: timeout)
        XCTAssertTrue(exists, "Expected element to exist: \(description.isEmpty ? self.debugDescription : description)")
        return self
    }

    /// Wait for the element to disappear.
    func waitForDisappearance(timeout: TimeInterval = 5) {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(result, .completed, "Expected element to disappear: \(self.debugDescription)")
    }
}

// MARK: - Common Assertions

enum MumbliAssert {
    /// Assert that the menu bar popover is visible with expected sections.
    static func menuBarPopoverIsVisible(app: XCUIApplication) {
        let popover = app.popovers[AccessibilityID.menuBarPopover]
        popover.waitForExistence(description: "Menu bar popover")
    }

    /// Assert that the overlay window is visible with listening indicator.
    static func overlayIsVisible(app: XCUIApplication) {
        let overlay = app.windows[AccessibilityID.overlayWindow]
        overlay.waitForExistence(description: "Overlay window")

        let indicator = overlay.otherElements[AccessibilityID.listeningIndicator]
        XCTAssertTrue(indicator.exists, "Listening indicator should be visible in overlay")
    }

    /// Assert that no overlay is visible.
    static func overlayIsHidden(app: XCUIApplication) {
        let overlay = app.windows[AccessibilityID.overlayWindow]
        if overlay.exists {
            overlay.waitForDisappearance()
        }
    }

    /// Assert history has a given number of entries.
    /// History entries are SwiftUI Buttons, so query buttons not cells.
    static func historyHasEntries(count: Int, app: XCUIApplication) {
        let entries = app.buttons.matching(identifier: AccessibilityID.historyEntry)
        XCTAssertEqual(entries.count, count, "Expected \(count) history entries, found \(entries.count)")
    }
}
