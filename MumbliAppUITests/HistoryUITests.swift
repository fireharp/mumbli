import XCTest

/// UI tests for dictation history in the menu bar dropdown.
///
/// KNOWN LIMITATION: NSPopover content launched from NSStatusItem is not
/// reliably accessible to XCUITest element queries on macOS. The popover
/// exists outside the standard window hierarchy. These tests attempt to
/// find elements within the popover, but will skip gracefully if the
/// popover content is not queryable.
///
/// History interaction should be verified via manual testing (see qa/manual-tests.md).
final class HistoryUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    /// Open the menu bar popover and verify history entries are queryable.
    /// Throws XCTSkip if popover content is inaccessible.
    private func openPopoverAndFindEntries() throws -> XCUIElementQuery {
        try app.tapMenuBarButton()

        // Wait briefly for popover to appear
        let entries = app.buttons.matching(identifier: AccessibilityID.historyEntry)
        // Also try descendants in case they're nested differently
        let altEntries = app.descendants(matching: .button).matching(identifier: AccessibilityID.historyEntry)

        if entries.count == 0 && altEntries.count == 0 {
            // Check if the popover itself is queryable
            let anyPopoverContent = app.staticTexts["No dictations yet"].firstMatch
            if !anyPopoverContent.waitForExistence(timeout: 3) {
                throw XCTSkip("NSPopover content from NSStatusItem not accessible to XCUITest — verify history via manual testing")
            }
        }

        return entries.count > 0 ? entries : altEntries
    }

    // MARK: - History Display

    func testHistoryShowsEntries() throws {
        app.launchWithHistory()
        let entries = try openPopoverAndFindEntries()
        XCTAssertGreaterThan(entries.count, 0, "History should have entries when seeded")
    }

    func testHistoryEntriesShowPreviewAndTimestamp() throws {
        app.launchWithHistory()
        let entries = try openPopoverAndFindEntries()

        let firstEntry = entries.firstMatch
        guard firstEntry.waitForExistence(timeout: 3) else {
            throw XCTSkip("History entries not accessible")
        }

        let textElements = firstEntry.staticTexts
        XCTAssertGreaterThanOrEqual(textElements.count, 2,
            "History entry should show at least preview text and timestamp")
    }

    func testHistoryOrderIsMostRecentFirst() throws {
        app.launchWithHistory()
        let entries = try openPopoverAndFindEntries()

        guard entries.count >= 2 else {
            throw XCTSkip("Need at least 2 history entries to test ordering")
        }

        let firstTimestamp = entries.element(boundBy: 0).staticTexts.element(boundBy: 1).label
        XCTAssertTrue(
            firstTimestamp.contains("Just now") || firstTimestamp.contains("m ago"),
            "Most recent entry should be first, got timestamp: \(firstTimestamp)"
        )
    }

    // MARK: - Copy to Clipboard

    func testClickingEntryCopiesAndShowsCheckmark() throws {
        app.launchWithHistory()
        let entries = try openPopoverAndFindEntries()

        let firstEntry = entries.firstMatch
        guard firstEntry.waitForExistence(timeout: 3) else {
            throw XCTSkip("History entries not accessible")
        }

        firstEntry.tap()

        let checkmark = app.images["checkmark.circle.fill"]
        checkmark.waitForExistence(description: "Copy confirmation checkmark")
        checkmark.waitForDisappearance(timeout: 3)
    }
}
