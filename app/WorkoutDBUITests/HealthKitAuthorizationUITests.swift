import XCTest

@MainActor
final class HealthKitAuthorizationUITests: XCTestCase {
    func testGrantHealthKitAuthorizationSheet() {
        let app = XCUIApplication()
        app.launchArguments = ["--healthkit-sim-spike"]
        app.launch()

        let healthPrivacy = XCUIApplication(bundleIdentifier: "com.apple.HealthPrivacyService")
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

        let sheet = healthPrivacy.wait(for: .runningForeground, timeout: 8)
            ? healthPrivacy
            : springboard

        let turnOnAll = sheet.cells["UIA.Health.AuthSheet.AllCategoryButton"]
        if turnOnAll.waitForExistence(timeout: 4) {
            turnOnAll.tap()
        } else {
            sheet.coordinate(withNormalizedOffset: CGVector(dx: 0.22, dy: 0.46)).tap()
        }

        let allow = sheet.buttons["UIA.Health.AuthSheet.DoneButton"]
        if allow.waitForExistence(timeout: 4) {
            allow.tap()
        } else {
            sheet.coordinate(withNormalizedOffset: CGVector(dx: 0.90, dy: 0.11)).tap()
        }

        XCTAssertFalse(allow.exists)
    }
}
