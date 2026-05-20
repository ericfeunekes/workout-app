import XCTest

@MainActor
final class SettingsHealthArchiveUITests: XCTestCase {
    func testHealthArchiveControlsPersistThroughRelaunch() {
        let app = launchSettings()
        defer { app.terminate() }

        setScope("all supported", in: app)
        setScope("custom", in: app)

        let heartRate = "health-archive.descriptor.HKQuantityTypeIdentifierHeartRate"
        setSwitch(id: heartRate, value: "0", in: app)

        app.terminate()
        app.launch()
        openSettings(in: app)
        setScope("custom", in: app)

        assertSwitch(id: heartRate, value: "0", in: app)
    }

    private func launchSettings() -> XCUIApplication {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = ["--debug-today-plan", "--debug-settings-tab"]
        app.launchEnvironment["WORKOUTDB_HEALTHKIT_PROBE_DEFAULT_STORE"] = "1"
        app.launch()
        openSettings(in: app)
        return app
    }

    private func openSettings(in app: XCUIApplication) {
        let tab = app.buttons["root.tab.settings"]
        XCTAssertTrue(tab.waitForExistence(timeout: 8))
        tab.tap()
        XCTAssertTrue(scopePicker(in: app).waitForExistence(timeout: 4))
    }

    private func setScope(_ value: String, in app: XCUIApplication) {
        let picker = scopePicker(in: app)
        XCTAssertTrue(picker.waitForExistence(timeout: 4))
        let button = picker.buttons[value]
        XCTAssertTrue(button.waitForExistence(timeout: 2))
        button.tap()
    }

    private func scopePicker(in app: XCUIApplication) -> XCUIElement {
        app.segmentedControls["settings.row.health-archive.scope-mode"]
    }

    private func setSwitch(id: String, value: String, in app: XCUIApplication) {
        let element = findSwitch(id: id, in: app)
        if element.value as? String == value {
            return
        }
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        waitForSwitch(element, value: value)
    }

    private func assertSwitch(id: String, value: String, in app: XCUIApplication) {
        let element = findSwitch(id: id, in: app)
        XCTAssertEqual(element.value as? String, value)
    }

    private func findSwitch(id: String, in app: XCUIApplication) -> XCUIElement {
        let element = app.switches[id]
        scrollToElement(element, in: app)
        return element
    }

    private func waitForSwitch(_ element: XCUIElement, value: String) {
        let predicate = NSPredicate(format: "value == %@", value)
        expectation(for: predicate, evaluatedWith: element)
        waitForExpectations(timeout: 4)
    }

    private func scrollToElement(_ element: XCUIElement, in app: XCUIApplication) {
        let scrollView = app.scrollViews.firstMatch
        for _ in 0..<6 {
            if element.isHittable { return }
            scrollView.swipeUp()
        }
        for _ in 0..<12 {
            if element.isHittable { return }
            scrollView.swipeDown()
        }
        for _ in 0..<6 {
            if element.isHittable { return }
            scrollView.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }
}
