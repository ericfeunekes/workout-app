import XCTest

@MainActor
final class WorkoutKitHandoffUITests: XCTestCase {
    func testProofCollectionPreviewActionShowsScheduledPresentation() throws {
        let app = XCUIApplication()
        app.terminate()
        defer { app.terminate() }
        app.launchArguments = [
            "--debug-seed",
            "--debug-today-plan",
            "--debug-workoutkit-pacer-plan",
            "--workoutkit-proof-collection-exposure",
        ]
        app.launch()

        let card = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@",
            "today.workout.detail."
        )).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()

        let scheduleButton = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@",
            "today.preview.workoutkit.schedule."
        )).firstMatch
        XCTAssertTrue(scheduleButton.waitForExistence(timeout: 5))
        scheduleButton.tap()

        XCTAssertTrue(app.staticTexts["Apple Workout"].waitForExistence(timeout: 5))
        let scheduledMessage = app.staticTexts.containing(NSPredicate(
            format: "label CONTAINS %@",
            "Scheduled in Apple Workout from this phone"
        )).firstMatch
        XCTAssertTrue(scheduledMessage.waitForExistence(timeout: 5))
    }
}
