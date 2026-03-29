import XCTest

final class MumbliAppUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testAppLaunches() throws {
        // Verify the app launched successfully as a menu bar app
        XCTAssertTrue(app.exists)
    }
}
