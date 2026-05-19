import XCTest

@MainActor
final class ExecutionWorkoutTypeMatrixUITests: XCTestCase {
    func testStraightSetsCanLaunchPerformOneActionAndEnd() {
        runExecutionSmoke(.matrixCase(named: "straight_sets"))
    }

    func testSupersetCanLaunchPerformOneActionAndEnd() {
        runExecutionSmoke(.matrixCase(named: "superset"))
    }

    func testCircuitCanLaunchPerformOneActionAndEnd() {
        runExecutionSmoke(.matrixCase(named: "circuit"))
    }

    func testContinuousCanLaunchPerformOneActionAndEnd() {
        runExecutionSmoke(.matrixCase(named: "continuous"))
    }

    func testAccumulateCanLaunchPerformOneActionAndEnd() {
        runExecutionSmoke(.matrixCase(named: "accumulate"))
    }

    func testCustomCanLaunchPerformOneActionAndEnd() {
        runExecutionSmoke(.matrixCase(named: "custom"))
    }

    func testRestCanLaunchPerformOneActionAndEnd() {
        runExecutionSmoke(.matrixCase(named: "rest"))
    }

    func testEmomCanLaunchPerformOneActionAndEnd() {
        runExecutionSmoke(.matrixCase(named: "emom"))
    }

    func testAmrapCanLaunchPerformOneActionAndEnd() {
        runExecutionSmoke(.matrixCase(named: "amrap"))
    }

    func testForTimeCanLaunchPerformOneActionAndEnd() {
        runExecutionSmoke(.matrixCase(named: "for_time"))
    }

    func testIntervalsCanLaunchPerformOneActionAndEnd() {
        runExecutionSmoke(.matrixCase(named: "intervals"))
    }

    func testTabataCanLaunchPerformOneActionAndEnd() {
        runExecutionSmoke(.matrixCase(named: "tabata"))
    }

    func testTimerGauntletStrengthCanLaunchPerformOneActionAndEnd() {
        runExecutionSmoke(.matrixCase(named: "timer_gauntlet_strength"))
    }

    func testTimerGauntletClockedCanLaunchPerformOneActionAndEnd() {
        runExecutionSmoke(.matrixCase(named: "timer_gauntlet_clocked"))
    }

    func testTimerGauntletEnduranceCanLaunchPerformOneActionAndEnd() {
        runExecutionSmoke(.matrixCase(named: "timer_gauntlet_endurance"))
    }

    func testPrimitiveCapstoneFastCanLaunchPerformOneActionAndEnd() {
        runExecutionSmoke(.matrixCase(named: "primitive_capstone_fast"))
    }

    func testPrimitiveChipperCanLaunchPerformOneActionAndEnd() {
        runExecutionSmoke(.matrixCase(named: "primitive_chipper"))
    }

    func testPrimitiveIntervalsCanLaunchPerformOneActionAndEnd() {
        runExecutionSmoke(.matrixCase(named: "primitive_intervals"))
    }

    func testPrimitiveCarryCircuitCanLaunchPerformOneActionAndEnd() {
        runExecutionSmoke(.matrixCase(named: "primitive_carry_circuit"))
    }

    func testPrimitiveStrengthDensityCanLaunchPerformOneActionAndEnd() {
        runExecutionSmoke(.matrixCase(named: "primitive_strength_density"))
    }

    func testPrimitiveCapstoneSaveAndDoneRendersHistoryPrimitiveRows() {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = [
            "--jump-complete",
            "--debug-scenario",
            "primitive_capstone_fast",
        ]
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(app.staticTexts["workout complete"].waitForExistence(timeout: 8))
        XCTAssertEqual(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "rows logged")).count,
            0
        )
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "reps")).count > 0)

        let saveAndDone = app.buttons["save & done"]
        XCTAssertTrue(
            saveAndDone.waitForExistence(timeout: 3),
            "primitive_capstone_fast completion expected Save & Done button"
        )
        XCTAssertTrue(
            saveAndDone.isHittable,
            "primitive_capstone_fast completion expected Save & Done button to be hittable"
        )
        XCTAssertGreaterThanOrEqual(
            saveAndDone.frame.height,
            44,
            "Save & Done must preserve at least the platform minimum hit target"
        )

        tapRequiredButton(
            "save & done",
            identifier: "save & done",
            in: app,
            name: "primitive_capstone_fast history readback",
            file: #filePath,
            line: #line
        )
        tapRequiredButton(
            "history",
            identifier: "history",
            in: app,
            name: "primitive_capstone_fast history readback",
            file: #filePath,
            line: #line
        )
        let completedSession = app.buttons
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "QA Primitive · Fast Mixed AMRAP"))
            .firstMatch
        XCTAssertTrue(
            completedSession.waitForExistence(timeout: 3),
            "primitive_capstone_fast history readback expected completed primitive session row"
        )
        completedSession.tap()

        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "history.session.setrow.")).count > 0,
            "History detail must render primitive result rows after Save & Done"
        )
        XCTAssertEqual(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "rows logged")).count,
            0,
            "History must not expose internal row-count copy"
        )
    }

    private func runExecutionSmoke(
        _ testCase: ExecutionSmokeCase,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = testCase.launchArguments
        app.launch()
        defer { app.terminate() }

        assertRoute(testCase.expectedInitialRoute, in: app, name: testCase.name, file: file, line: line)

        for step in testCase.steps {
            perform(step, in: app, name: testCase.name, file: file, line: line)
        }
        endWorkout(in: app, name: testCase.name, file: file, line: line)
    }

    private func assertRoute(
        _ route: ExecutionRouteExpectation,
        in app: XCUIApplication,
        name: String,
        file: StaticString,
        line: UInt
    ) {
        let element: XCUIElement
        switch route {
        case .active:
            element = app.buttons["execution.active.end"]
        case .rest:
            element = app.buttons["execution.rest.end"]
        }
        XCTAssertTrue(
            element.waitForExistence(timeout: 8),
            "\(name) did not enter expected \(route.rawValue) route",
            file: file,
            line: line
        )
    }

    private func perform(
        _ step: ExecutionSmokeStep,
        in app: XCUIApplication,
        name: String,
        file: StaticString,
        line: UInt
    ) {
        switch step {
        case .startExplicitWork(let label):
            tapRequiredButton(
                label,
                identifier: step.requiredButtonIdentifier,
                in: app,
                name: name,
                file: file,
                line: line
            )
        case .openLogSheet(let label):
            tapRequiredButton(
                label,
                identifier: step.requiredButtonIdentifier,
                in: app,
                name: name,
                file: file,
                line: line
            )
            XCTAssertTrue(
                app.buttons["logset.rir.2"].waitForExistence(timeout: 2),
                "\(name) tapped \(label) but LogSetSheet did not open",
                file: file,
                line: line
            )
        case .commitLogSheet:
            if app.buttons["logset.rir.2"].waitForExistence(timeout: 1) {
                app.buttons["logset.rir.2"].tap()
            }
            tapRequiredButton(
                "log",
                identifier: step.requiredButtonIdentifier,
                in: app,
                name: name,
                file: file,
                line: line
            )
        case .tapDirectLog(let label),
             .tapRoundRobinAdvance(let label),
             .tapMetconFinish(let label),
             .advanceRest(let label):
            tapRequiredButton(
                label,
                identifier: step.requiredButtonIdentifier,
                in: app,
                name: name,
                file: file,
                line: line
            )
        }
    }

    private func tapRequiredButton(
        _ label: String,
        identifier: String,
        in app: XCUIApplication,
        name: String,
        file: StaticString,
        line: UInt
    ) {
        let button = app.buttons[identifier]
        guard button.waitForExistence(timeout: 3), button.isHittable else {
            XCTFail(
                "\(name) expected required button '\(label)' with identifier '\(identifier)'",
                file: file,
                line: line
            )
            return
        }
        button.tap()
    }

    private func endWorkout(
        in app: XCUIApplication,
        name: String,
        file: StaticString,
        line: UInt
    ) {
        if app.staticTexts["workout complete"].waitForExistence(timeout: 1) {
            return
        }

        var completedEndAction = false
        for _ in 0..<3 {
            guard let endControl = firstExistingEndControl(in: app, timeout: 4) else {
                continue
            }
            endControl.tap()

            let alert = app.alerts["End workout?"]
            if alert.waitForExistence(timeout: 2) {
                alert.buttons["End"]
                    .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                    .tap()
                completedEndAction = true
                break
            }
            if finishMetconResultSheetIfNeeded(in: app) {
                // AMRAP-style flows intentionally collect the final partial
                // block result before routing to completion.
                completedEndAction = true
                break
            }
            if app.staticTexts["workout complete"].waitForExistence(timeout: 1) {
                completedEndAction = true
                break
            }
        }
        if !completedEndAction {
            XCTFail("\(name) did not show End confirmation or result sheet", file: file, line: line)
        }

        XCTAssertTrue(
            app.staticTexts["workout complete"].waitForExistence(timeout: 4),
            "\(name) did not reach the completion screen",
            file: file,
            line: line
        )
    }

    @discardableResult
    private func finishMetconResultSheetIfNeeded(in app: XCUIApplication) -> Bool {
        if let button = firstExistingButton(
            in: app,
            labels: ["save result", "save finish"],
            timeout: 2
        ) {
            button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            return true
        }
        return false
    }

    private func firstExistingEndControl(in app: XCUIApplication, timeout: TimeInterval) -> XCUIElement? {
        firstExisting(
            [
                app.buttons["execution.active.end"],
                app.buttons["execution.rest.end"],
            ],
            timeout: timeout
        )
    }

    private func firstExistingButton(
        in app: XCUIApplication,
        labels: [String],
        timeout: TimeInterval
    ) -> XCUIElement? {
        firstExisting(labels.map { app.buttons[$0] }, timeout: timeout)
    }

    private func firstExisting(_ elements: [XCUIElement], timeout: TimeInterval) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let element = elements.first(where: { $0.exists && $0.isHittable }) {
                return element
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        return nil
    }
}

final class ExecutionWorkoutTypeMatrixDataTests: XCTestCase {
    func testEveryMatrixCaseDeclaresAtLeastOneRequiredRuntimeStep() {
        for testCase in ExecutionSmokeCase.matrixCases {
            XCTAssertFalse(testCase.steps.isEmpty, "\(testCase.name) must not be launch-only")
        }
    }

    func testSheetOpeningStepsAreCommittedAndDirectStepsDoNotCommitSheets() {
        for testCase in ExecutionSmokeCase.matrixCases {
            for (index, step) in testCase.steps.enumerated() where step.opensLogSetSheet {
                let nextIndex = testCase.steps.index(after: index)
                XCTAssertLessThan(nextIndex, testCase.steps.count, "\(testCase.name) opens a sheet without commit")
                XCTAssertEqual(
                    testCase.steps[nextIndex],
                    .commitLogSheet,
                    "\(testCase.name) must commit immediately after opening LogSetSheet"
                )
            }

            for (index, step) in testCase.steps.enumerated() where step.logsDirectly {
                let nextIndex = testCase.steps.index(after: index)
                if nextIndex < testCase.steps.count {
                    XCTAssertNotEqual(
                        testCase.steps[nextIndex],
                        .commitLogSheet,
                        "\(testCase.name) direct-log step must not be followed by LogSetSheet commit"
                    )
                }
            }
        }
    }

    func testExplicitStartCasesStartBeforeOpeningLogSheet() {
        let explicitStartCases = ExecutionSmokeCase.matrixCases.filter(\.requiresExplicitStart)
        XCTAssertFalse(explicitStartCases.isEmpty)
        for testCase in explicitStartCases {
            XCTAssertEqual(
                testCase.steps.first,
                .startExplicitWork("set start"),
                "\(testCase.name) must start explicit work before logging"
            )
        }
    }

    func testRestCasesDeclareRestInitialRoute() {
        let restCases = ExecutionSmokeCase.matrixCases.filter {
            $0.steps.contains { step in
                if case .advanceRest = step { return true }
                return false
            }
        }
        XCTAssertFalse(restCases.isEmpty)
        for testCase in restCases {
            XCTAssertEqual(
                testCase.expectedInitialRoute,
                .rest,
                "\(testCase.name) rest action must start from the rest route"
            )
        }
    }
}

enum ExecutionRouteExpectation: String, Equatable {
    case active
    case rest
}

enum ExecutionSmokeStep: Equatable {
    case startExplicitWork(String)
    case openLogSheet(String)
    case commitLogSheet
    case tapDirectLog(String)
    case tapRoundRobinAdvance(String)
    case tapMetconFinish(String)
    case advanceRest(String)

    var opensLogSetSheet: Bool {
        if case .openLogSheet = self { return true }
        return false
    }

    var logsDirectly: Bool {
        switch self {
        case .tapDirectLog, .tapMetconFinish, .tapRoundRobinAdvance, .advanceRest:
            return true
        case .startExplicitWork, .openLogSheet, .commitLogSheet:
            return false
        }
    }

    var requiredButtonIdentifier: String {
        switch self {
        case .startExplicitWork:
            "execution.active.start"
        case .openLogSheet:
            "execution.active.log.open"
        case .commitLogSheet:
            "logset.commit"
        case .tapDirectLog(let label):
            label == "next" ? "execution.active.amrap.next" : "execution.active.cardio.log"
        case .tapRoundRobinAdvance:
            "execution.active.roundrobin.next"
        case .tapMetconFinish:
            "execution.active.finish"
        case .advanceRest:
            "execution.rest.next"
        }
    }
}

struct ExecutionSmokeCase: Equatable {
    var name: String
    var launchArguments: [String]
    var expectedInitialRoute: ExecutionRouteExpectation
    var steps: [ExecutionSmokeStep]
    var requiresExplicitStart: Bool

    static func timingMode(
        _ mode: String,
        expectedInitialRoute: ExecutionRouteExpectation = .active,
        steps: [ExecutionSmokeStep],
        requiresExplicitStart: Bool = false
    ) -> ExecutionSmokeCase {
        ExecutionSmokeCase(
            name: mode,
            launchArguments: ["--start-active", "--debug-mode", mode],
            expectedInitialRoute: expectedInitialRoute,
            steps: steps,
            requiresExplicitStart: requiresExplicitStart
        )
    }

    static func scenario(
        _ scenario: String,
        expectedInitialRoute: ExecutionRouteExpectation = .active,
        steps: [ExecutionSmokeStep],
        requiresExplicitStart: Bool = false
    ) -> ExecutionSmokeCase {
        ExecutionSmokeCase(
            name: scenario,
            launchArguments: ["--start-active", "--debug-scenario", scenario],
            expectedInitialRoute: expectedInitialRoute,
            steps: steps,
            requiresExplicitStart: requiresExplicitStart
        )
    }

    static let matrixCases: [ExecutionSmokeCase] = [
        .timingMode(
            "straight_sets",
            steps: [.startExplicitWork("set start"), .openLogSheet("done"), .commitLogSheet],
            requiresExplicitStart: true
        ),
        .timingMode("superset", steps: [.tapRoundRobinAdvance("next station")]),
        .timingMode("circuit", steps: [.openLogSheet("log station"), .commitLogSheet]),
        .timingMode("continuous", steps: [.tapDirectLog("end")]),
        .timingMode(
            "accumulate",
            steps: [.startExplicitWork("set start"), .openLogSheet("log chunk"), .commitLogSheet],
            requiresExplicitStart: true
        ),
        .timingMode("custom", steps: [.tapDirectLog("log segment 1")]),
        .timingMode("rest", expectedInitialRoute: .rest, steps: [.advanceRest("next")]),
        .timingMode(
            "emom",
            steps: [.startExplicitWork("set start"), .openLogSheet("log interval 1"), .commitLogSheet],
            requiresExplicitStart: true
        ),
        .timingMode("amrap", steps: [.tapDirectLog("next")]),
        .timingMode("for_time", steps: [.tapMetconFinish("finish")]),
        .timingMode("intervals", steps: [.tapDirectLog("log interval 1")]),
        .timingMode("tabata", steps: [.tapDirectLog("log round 1")]),
        .scenario(
            "timer_gauntlet_strength",
            expectedInitialRoute: .rest,
            steps: [.advanceRest("next")]
        ),
        .scenario(
            "timer_gauntlet_clocked",
            steps: [.startExplicitWork("set start"), .openLogSheet("log interval 1"), .commitLogSheet],
            requiresExplicitStart: true
        ),
        .scenario("timer_gauntlet_endurance", steps: [.tapDirectLog("log interval 1")]),
        .scenario("primitive_capstone_fast", steps: [.tapDirectLog("next")]),
        .scenario("primitive_chipper", steps: [.tapMetconFinish("finish")]),
        .scenario("primitive_intervals", steps: [.tapDirectLog("log interval 1")]),
        .scenario("primitive_carry_circuit", steps: [.tapDirectLog("log set 1")]),
        .scenario(
            "primitive_strength_density",
            steps: [.startExplicitWork("set start"), .openLogSheet("log interval 1"), .commitLogSheet],
            requiresExplicitStart: true
        ),
    ]

    static func matrixCase(named name: String) -> ExecutionSmokeCase {
        guard let testCase = matrixCases.first(where: { $0.name == name }) else {
            preconditionFailure("Missing workout type matrix case: \(name)")
        }
        return testCase
    }
}
