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

    func testHealthArchiveAutomaticAndManualExportUpdateVisibleStatus() {
        let app = launchSettings(exportOutcome: "success")
        defer { app.terminate() }

        setSwitch(id: "health-archive.automatic", value: "1", in: app)
        assertSwitch(id: "health-archive.automatic", value: "1", in: app)
        XCTAssertTrue(
            app.staticTexts["health-archive.next-attempt"].waitForExistence(timeout: 4)
        )
        XCTAssertNotEqual(app.staticTexts["health-archive.next-attempt"].label, "off")

        let export = app.buttons["health-archive.export-now"]
        scrollToElement(export, in: app)
        export.tap()

        let status = app.staticTexts["health-archive.status"]
        let deadline = Date().addingTimeInterval(6)
        while Date() < deadline, !status.label.contains("4 ·") {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertTrue(status.label.contains("4 ·"), "status label: \(status.label)")
    }

    func testHealthArchiveManualExportFailureUpdatesVisibleStatus() {
        let app = launchSettings(exportOutcome: "failed")
        defer { app.terminate() }

        let export = app.buttons["health-archive.export-now"]
        scrollToElement(export, in: app)
        export.tap()

        let status = app.staticTexts["health-archive.status"]
        let deadline = Date().addingTimeInterval(6)
        while Date() < deadline, !status.label.contains("failed · DebugExportFailure") {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertEqual(status.label, "failed · DebugExportFailure")
    }

    func testHealthArchiveManualExportShowsInFlightStatusBeforeCompletion() {
        let app = launchSettings(exportOutcome: "delayedSuccess")
        defer { app.terminate() }

        let export = app.buttons["health-archive.export-now"]
        scrollToElement(export, in: app)
        export.tap()

        let status = app.staticTexts["health-archive.status"]
        let exportingDeadline = Date().addingTimeInterval(3)
        while Date() < exportingDeadline, status.label != "exporting" {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertEqual(status.label, "exporting")

        let successDeadline = Date().addingTimeInterval(6)
        while Date() < successDeadline, !status.label.contains("4 ·") {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertTrue(status.label.contains("4 ·"), "status label: \(status.label)")
    }

    private func launchSettings(exportOutcome: String = "success") -> XCUIApplication {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = [
            "--debug-today-plan",
            "--debug-settings-tab",
            "--debug-health-archive-settings",
        ]
        app.launchEnvironment["WORKOUTDB_HEALTHKIT_PROBE_DEFAULT_STORE"] = "1"
        app.launchEnvironment["WORKOUTDB_DEBUG_HEALTH_ARCHIVE_EXPORT_OUTCOME"] = exportOutcome
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
