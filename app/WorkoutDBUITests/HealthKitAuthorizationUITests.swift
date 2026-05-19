import XCTest

@MainActor
final class HealthKitAuthorizationUITests: XCTestCase {
    func testSignedHealthKitArchiveProjectionProbe() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = ["--healthkit-sim-spike"]
        app.launchEnvironment["WORKOUTDB_HEALTHKIT_PROBE_DEFAULT_STORE"] = "1"
        app.launch()
        defer { app.terminate() }

        let healthPrivacy = XCUIApplication(bundleIdentifier: "com.apple.HealthPrivacyService")
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

        let observedAuthorizationSheet = grantHealthAccessIfPresented(
            healthPrivacy: healthPrivacy,
            springboard: springboard
        )

        let output = app.staticTexts["healthkit-probe-output"]
        let proof = NSPredicate(format: """
        label CONTAINS %@ AND label CONTAINS %@ AND label CONTAINS %@ AND label CONTAINS %@ AND \
        label CONTAINS %@ AND label CONTAINS %@ AND label CONTAINS %@ AND label CONTAINS %@ AND \
        label CONTAINS %@ AND label CONTAINS %@ AND label CONTAINS %@ AND label CONTAINS %@ AND \
        label CONTAINS %@
        """,
        #""authorizationRequestCompleted" : true"#,
        #""archiveFetchSucceeded" : true"#,
        #""thisRunSamplesFetched" : true"#,
        #""projectionPersisted" : true"#,
        #""firstCursorPresent" : true"#,
        #""secondCursorPresent" : true"#,
        #""secondFetchUsedFirstCursor" : true"#,
        #""deletedRecordMatchedFirstPass" : true"#,
        #""projectionMatchedDeletedRecord" : true"#,
        #""projectionMatchedRecords" : true"#,
        #""projectionMatchedCursor" : true"#,
        #""projectionStoreKind" : "default_on_disk""#,
        #""projectionReopenMatched" : true"#)
        let proofExpectation = expectation(for: proof, evaluatedWith: output)
        let proofResult = XCTWaiter().wait(for: [proofExpectation], timeout: 20)

        let data = try XCTUnwrap(output.label.data(using: .utf8))
        let decoded = try JSONDecoder().decode(HealthKitArchiveProbeProof.self, from: data)
        if proofResult != .completed {
            XCTFail("HealthKit archive proof did not complete: \(decoded.archiveFetchError ?? output.label)")
            return
        }
        XCTAssertEqual(decoded.authorizedRequestTypeIDs, decoded.fetchedRequestTypeIDs)
        XCTAssertEqual(decoded.authorizedRequestFingerprints, decoded.fetchedRequestFingerprints)
        if observedAuthorizationSheet {
            XCTAssertTrue(observedAuthorizationSheet)
        }
        XCTAssertFalse(decoded.requestSetKey.isEmpty)
        XCTAssertFalse(decoded.representativeRecordIDs.isEmpty)
        XCTAssertFalse(decoded.deletedExternalIDs.isEmpty)
        XCTAssertFalse(decoded.projectionDeletedExternalIDs.isEmpty)
        XCTAssertFalse(decoded.projectionRecordExternalIDs.isEmpty)
        XCTAssertEqual(decoded.firstCursorValue, decoded.secondFetchCursorInput)
        XCTAssertEqual(decoded.secondCursorValue, decoded.projectionCursorValue)
        XCTAssertEqual(decoded.projectionStoreKind, "default_on_disk")
        XCTAssertTrue(decoded.projectionReopenMatched)
        let expectedPersistedRecordIDs = decoded.representativeRecordIDs
            .filter { !decoded.deletedExternalIDs.contains($0) }
        XCTAssertFalse(expectedPersistedRecordIDs.isEmpty)
        XCTAssertTrue(expectedPersistedRecordIDs.allSatisfy {
            decoded.projectionRecordExternalIDs.contains($0)
        })
        XCTAssertTrue(decoded.deletedExternalIDs.allSatisfy {
            decoded.projectionDeletedExternalIDs.contains($0)
        })
    }

    private func grantHealthAccessIfPresented(
        healthPrivacy: XCUIApplication,
        springboard: XCUIApplication
    ) -> Bool {
        let candidates = healthPrivacy.wait(for: .runningForeground, timeout: 8)
            ? [healthPrivacy, springboard]
            : [springboard, healthPrivacy]

        for sheet in candidates {
            if tapFirstExistingElement(
                in: sheet,
                identifiers: [
                    "UIA.Health.AuthSheet.AllCategoryButton",
                    "Turn On All",
                    "Turn All On"
                ],
                timeout: 0.25
            ) {
                tapFirstExistingElement(
                    in: sheet,
                    identifiers: [
                        "UIA.Health.AuthSheet.DoneButton",
                        "Allow"
                    ],
                    timeout: 0.25
                )
                if !sheet.buttons["UIA.Health.AuthSheet.DoneButton"].exists
                    && !sheet.buttons["Allow"].exists
                {
                    return true
                }
            }
        }

        // The Health authorization sheet is hosted by HealthPrivacyService and
        // some simulator/Xcode combinations expose unstable accessibility
        // identifiers. Keep this as the last resort after selector-based taps.
        let fallbackSheet = healthPrivacy.state == .runningForeground ? healthPrivacy : springboard
        fallbackSheet.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.46)).tap()
        fallbackSheet.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.115)).tap()
        return !fallbackSheet.buttons["Allow"].waitForExistence(timeout: 2)
    }

    @discardableResult
    private func tapFirstExistingElement(
        in app: XCUIApplication,
        identifiers: [String],
        timeout: TimeInterval
    ) -> Bool {
        let queries: [(XCUIApplication, String) -> XCUIElement] = [
            { $0.buttons[$1] },
            { $0.cells[$1] },
            { $0.staticTexts[$1] },
            { $0.descendants(matching: .any)[$1] }
        ]
        for identifier in identifiers {
            for query in queries {
                let element = query(app, identifier)
                if element.waitForExistence(timeout: timeout) {
                    element.tap()
                    return true
                }
            }
        }
        return false
    }
}

private struct HealthKitArchiveProbeProof: Decodable {
    let requestSetKey: String
    let authorizedRequestTypeIDs: [String]
    let fetchedRequestTypeIDs: [String]
    let authorizedRequestFingerprints: [String]
    let fetchedRequestFingerprints: [String]
    let firstCursorValue: String?
    let secondFetchCursorInput: String?
    let secondCursorValue: String?
    let projectionCursorValue: String?
    let representativeRecordIDs: [String]
    let projectionRecordExternalIDs: [String]
    let deletedExternalIDs: [String]
    let projectionDeletedExternalIDs: [String]
    let archiveFetchError: String?
    let projectionStoreKind: String?
    let projectionReopenMatched: Bool
}
