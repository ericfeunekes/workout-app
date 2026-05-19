import XCTest

@MainActor
final class ExecutionEndConfirmationUITests: XCTestCase {
    func testEndConfirmationDismissesAcrossRouteChangeAndCanReopen() {
        let app = launchApp(arguments: ["--start-active", "--debug-scenario", "primitive_intervals"])
        defer { app.terminate() }

        let activeEnd = app.buttons["execution.active.end"]
        XCTAssertTrue(activeEnd.waitForExistence(timeout: 8))
        activeEnd.tap()

        let alert = app.alerts["End workout?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 2))

        let staleAlertDismissed = NSPredicate(format: "exists == false")
        expectation(for: staleAlertDismissed, evaluatedWith: alert)
        waitForExpectations(timeout: 24)

        let endAfterRouteChange = app.buttons["execution.rest.end"]
        XCTAssertTrue(endAfterRouteChange.waitForExistence(timeout: 4))
        endAfterRouteChange.tap()

        let reopenedAlert = app.alerts["End workout?"]
        XCTAssertTrue(reopenedAlert.waitForExistence(timeout: 2))
        reopenedAlert.buttons["End"].tap()

        XCTAssertTrue(app.staticTexts["workout complete"].waitForExistence(timeout: 4))
    }

    func testEndConfirmationOpensFromRest() {
        let app = launchApp(arguments: ["--jump-rest"])
        defer { app.terminate() }

        let restEnd = app.buttons["execution.rest.end"]
        XCTAssertTrue(restEnd.waitForExistence(timeout: 8))
        restEnd.tap()

        let alert = app.alerts["End workout?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 2))
        alert.buttons["Cancel"].tap()
        XCTAssertFalse(alert.exists)
    }

    private func launchApp(arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = arguments
        app.launch()
        return app
    }
}
