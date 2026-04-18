// SettingsViewModelTests.swift
//
// Exercises the viewModel's contract:
//   - sections are built in the documented order (SERVER → DEVICE →
//     AUTOREG DEFAULTS → DATA) with the right row types
//   - tapping a destructive action populates `showDestructiveConfirm`
//   - confirming invokes the provided closure; cancelling does not
//   - the units picker mutates the store and the derived section
//   - autoreg "reset to defaults" wipes the store and rebuilds

import XCTest
import Foundation
@testable import FeaturesSettings

@MainActor
final class SettingsViewModelTests: XCTestCase {

    // MARK: - Sections shape

    func testSectionsHaveExpectedOrder() {
        let vm = makeViewModel()
        let ids = vm.sections.map { $0.id }
        XCTAssertEqual(ids, ["server", "device", "autoreg-defaults", "data"])
    }

    func testSectionsHaveExpectedTitles() {
        let vm = makeViewModel()
        let titles = vm.sections.map { $0.title }
        XCTAssertEqual(titles, ["SERVER", "DEVICE", "AUTOREG DEFAULTS", "DATA"])
    }

    func testServerSectionHasExpectedRows() {
        let vm = makeViewModel()
        let server = vm.sections.first { $0.id == "server" }!
        let ids = server.rows.map { $0.id }
        XCTAssertEqual(ids, [
            "server.url",
            "server.synced",
            "server.sync-now",
            "server.change",
        ])
        // Row types: two info, two action.
        XCTAssertTrue(isInfo(server.rows[0]))
        XCTAssertTrue(isInfo(server.rows[1]))
        XCTAssertTrue(isAction(server.rows[2]))
        XCTAssertTrue(isAction(server.rows[3]))
        // "change server" is destructive; "sync now" is not.
        XCTAssertFalse(actionDestructive(server.rows[2]))
        XCTAssertTrue(actionDestructive(server.rows[3]))
    }

    func testDeviceSectionHasPickerAndPairedWatchStub() {
        let vm = makeViewModel()
        let device = vm.sections.first { $0.id == "device" }!
        XCTAssertEqual(device.rows.count, 2)
        XCTAssertTrue(isPicker(device.rows[0]))
        XCTAssertTrue(isInfo(device.rows[1]))
        // Paired-watch stub value.
        if case .info(_, _, let value) = device.rows[1] {
            XCTAssertEqual(value, "no watch paired")
        } else {
            XCTFail("expected info row for paired watch")
        }
    }

    func testAutoregSectionHasThreeInfoRowsAndResetAction() {
        let vm = makeViewModel()
        let autoreg = vm.sections.first { $0.id == "autoreg-defaults" }!
        XCTAssertEqual(autoreg.rows.count, 4)
        XCTAssertTrue(isInfo(autoreg.rows[0]))
        XCTAssertTrue(isInfo(autoreg.rows[1]))
        XCTAssertTrue(isInfo(autoreg.rows[2]))
        XCTAssertTrue(isAction(autoreg.rows[3]))
        XCTAssertFalse(actionDestructive(autoreg.rows[3]))
    }

    func testDataSectionHasDestructiveResetAndBuildInfo() {
        let vm = makeViewModel()
        let data = vm.sections.first { $0.id == "data" }!
        XCTAssertEqual(data.rows.count, 2)
        XCTAssertTrue(isAction(data.rows[0]))
        XCTAssertTrue(actionDestructive(data.rows[0]))
        XCTAssertTrue(isInfo(data.rows[1]))
    }

    // MARK: - Server URL rendering

    func testServerRowShowsHostAndPortWhenConnectionIsSaved() {
        let token = FakeTokenStore(initial: (URL(string: "https://wdb.local:8080")!, "t"))
        let vm = makeViewModel(tokenStore: token)
        let url = firstInfoValue(in: vm, rowID: "server.url")
        XCTAssertEqual(url, "wdb.local:8080")
    }

    func testServerRowShowsNoServerConfiguredWhenTokenStoreEmpty() {
        let token = FakeTokenStore(initial: nil)
        let vm = makeViewModel(tokenStore: token)
        let url = firstInfoValue(in: vm, rowID: "server.url")
        XCTAssertEqual(url, "no server configured")
    }

    func testServerRowShowsUnavailableWhenTokenStoreThrows() {
        let token = FakeTokenStore(initial: (URL(string: "https://x")!, "t"))
        token.shouldThrowOnLoad = true
        let vm = makeViewModel(tokenStore: token)
        let url = firstInfoValue(in: vm, rowID: "server.url")
        XCTAssertEqual(url, "unavailable")
    }

    // MARK: - Sync-time rendering

    func testSyncedRowShowsPlaceholderWhenLastSyncIsNil() {
        let vm = makeViewModel(lastSync: nil)
        let synced = firstInfoValue(in: vm, rowID: "server.synced")
        XCTAssertEqual(synced, "—")
    }

    func testSyncedRowShowsMinutesAgoWhenRecent() {
        let now = Date(timeIntervalSince1970: 10_000)
        let lastSync = now.addingTimeInterval(-240) // 4 minutes ago
        let vm = makeViewModel(lastSync: lastSync, now: now)
        let synced = firstInfoValue(in: vm, rowID: "server.synced")
        XCTAssertEqual(synced, "4 min ago")
    }

    // MARK: - Change-server destructive flow

    func testChangeServerPopulatesDestructiveConfirm() async {
        let vm = makeViewModel()
        XCTAssertNil(vm.showDestructiveConfirm)
        await tapAction(in: vm, rowID: "server.change")
        let confirm = vm.showDestructiveConfirm
        XCTAssertNotNil(confirm)
        XCTAssertEqual(confirm?.id, "change-server")
        XCTAssertEqual(confirm?.title, "change server")
        XCTAssertEqual(confirm?.message, "CHANGING SERVERS WIPES LOCAL DATA")
    }

    func testConfirmChangeServerInvokesClosure() async {
        final class Box: @unchecked Sendable { var count = 0 }
        let box = Box()
        let vm = makeViewModel(onChangeServer: {
            box.count += 1
        })
        await tapAction(in: vm, rowID: "server.change")
        vm.confirmDestructive()
        // Clear the confirm immediately on the main actor.
        XCTAssertNil(vm.showDestructiveConfirm)
        // The underlying closure runs inside a Task; drain the queue.
        await drainPendingTasks()
        XCTAssertEqual(box.count, 1)
    }

    func testCancelDestructiveClearsConfirmAndDoesNotInvokeClosure() async {
        final class Box: @unchecked Sendable { var count = 0 }
        let box = Box()
        let vm = makeViewModel(onChangeServer: {
            box.count += 1
        })
        await tapAction(in: vm, rowID: "server.change")
        XCTAssertNotNil(vm.showDestructiveConfirm)
        vm.cancelDestructive()
        XCTAssertNil(vm.showDestructiveConfirm)
        await drainPendingTasks()
        XCTAssertEqual(box.count, 0)
    }

    // MARK: - Reset-local-data flow

    func testResetLocalDataPopulatesDestructiveConfirm() async {
        let vm = makeViewModel()
        await tapAction(in: vm, rowID: "data.reset-local")
        let confirm = vm.showDestructiveConfirm
        XCTAssertEqual(confirm?.id, "reset-local-data")
        XCTAssertEqual(confirm?.title, "reset local data")
    }

    func testConfirmResetLocalDataInvokesClosure() async {
        final class Box: @unchecked Sendable { var count = 0 }
        let box = Box()
        let vm = makeViewModel(onResetCache: {
            box.count += 1
        })
        await tapAction(in: vm, rowID: "data.reset-local")
        vm.confirmDestructive()
        await drainPendingTasks()
        XCTAssertEqual(box.count, 1)
    }

    // MARK: - Sync-now (non-destructive)

    func testSyncNowInvokesClosureWithoutConfirm() async {
        final class Box: @unchecked Sendable { var count = 0 }
        let box = Box()
        let vm = makeViewModel(onSyncNow: {
            box.count += 1
        })
        await tapAction(in: vm, rowID: "server.sync-now")
        XCTAssertNil(vm.showDestructiveConfirm)
        await drainPendingTasks()
        XCTAssertEqual(box.count, 1)
    }

    // MARK: - Units picker

    func testPickerChangeUpdatesStoreAndSection() async {
        let units = FakeUnitsStore(current: .kg)
        let vm = makeViewModel(unitsStore: units)
        XCTAssertEqual(units.current, .kg)
        XCTAssertEqual(pickerSelected(in: vm, rowID: "device.units"), "kg")

        await pickPicker(in: vm, rowID: "device.units", label: "lb")

        XCTAssertEqual(units.current, .lb)
        XCTAssertEqual(units.saveCount, 1)
        XCTAssertEqual(pickerSelected(in: vm, rowID: "device.units"), "lb")
    }

    func testPickerIgnoresUnknownLabel() async {
        let units = FakeUnitsStore(current: .kg)
        let vm = makeViewModel(unitsStore: units)
        await pickPicker(in: vm, rowID: "device.units", label: "stones")
        XCTAssertEqual(units.current, .kg)
    }

    // MARK: - Autoreg reset

    func testResetAutoregDefaultsInvokesStoreAndRebuilds() async {
        let store = FakeAutoregStore(current: AutoregDefaults(
            targetRIR: 5, overshootStepKg: 10, undershootStepKg: 7.5
        ))
        let vm = makeViewModel(autoregStore: store)

        XCTAssertEqual(firstInfoValue(in: vm, rowID: "autoreg.target-rir"), "rir 5")
        XCTAssertEqual(firstInfoValue(in: vm, rowID: "autoreg.overshoot"), "10 kg")

        await tapAction(in: vm, rowID: "autoreg.reset")

        XCTAssertEqual(store.resetCount, 1)
        XCTAssertEqual(firstInfoValue(in: vm, rowID: "autoreg.target-rir"), "rir 2")
        XCTAssertEqual(firstInfoValue(in: vm, rowID: "autoreg.overshoot"), "2.5 kg")
    }

    // MARK: - Formatting

    func testRelativeFormattingBoundaries() {
        let vm = makeViewModel()
        XCTAssertEqual(vm.formatRelative(elapsed: 0), "just now")
        XCTAssertEqual(vm.formatRelative(elapsed: 59), "just now")
        XCTAssertEqual(vm.formatRelative(elapsed: 60), "1 min ago")
        XCTAssertEqual(vm.formatRelative(elapsed: 3_599), "59 min ago")
        XCTAssertEqual(vm.formatRelative(elapsed: 3_600), "1 h ago")
        XCTAssertEqual(vm.formatRelative(elapsed: 60 * 60 * 24), "1 d ago")
    }

    func testRIRFormattingStripsIntegerDecimal() {
        let vm = makeViewModel()
        XCTAssertEqual(vm.formatRIR(2), "rir 2")
        XCTAssertEqual(vm.formatRIR(1.5), "rir 1.5")
    }

    func testKgFormattingStripsIntegerDecimal() {
        let vm = makeViewModel()
        XCTAssertEqual(vm.formatKg(5), "5 kg")
        XCTAssertEqual(vm.formatKg(2.5), "2.5 kg")
    }

    // MARK: - Build info

    func testBuildInfoRowRendersMainBundleValues() {
        let vm = makeViewModel(buildInfo: BuildInfo(
            version: "1.2.3", build: "42", commit: "abcd123"
        ))
        let build = firstInfoValue(in: vm, rowID: "data.build")
        XCTAssertEqual(build, "build 1.2.3 (42) · commit abcd123")
    }

    // MARK: - Refresh

    func testRefreshRebuildsSectionsFromStore() {
        let units = FakeUnitsStore(current: .kg)
        let vm = makeViewModel(unitsStore: units)
        XCTAssertEqual(pickerSelected(in: vm, rowID: "device.units"), "kg")

        // Mutate the store directly (simulating something outside Settings
        // writing a new value) and then call refresh.
        units.current = .lb
        vm.refresh()

        XCTAssertEqual(pickerSelected(in: vm, rowID: "device.units"), "lb")
    }

    // MARK: - Row identity

    func testRowEqualsIgnoringCallbacksHoldsAcrossRebuilds() {
        let vm = makeViewModel()
        let snapshot1 = vm.sections.flatMap { $0.rows }
        vm.refresh()
        let snapshot2 = vm.sections.flatMap { $0.rows }
        XCTAssertEqual(snapshot1.count, snapshot2.count)
        for (a, b) in zip(snapshot1, snapshot2) {
            XCTAssertTrue(
                a.equalsIgnoringCallbacks(b),
                "row \(a.id) differed across rebuild"
            )
        }
    }

    // MARK: - Helpers

    private func makeViewModel(
        tokenStore: FakeTokenStore = FakeTokenStore(
            initial: (URL(string: "https://wdb.local:8080")!, "t")
        ),
        autoregStore: FakeAutoregStore = FakeAutoregStore(),
        unitsStore: FakeUnitsStore = FakeUnitsStore(),
        buildInfo: BuildInfo = BuildInfo(version: "0.0.1", build: "1", commit: "dev"),
        lastSync: Date? = nil,
        pairedWatch: String? = nil,
        onSyncNow: @escaping @Sendable () async -> Void = {},
        onResetCache: @escaping @Sendable () async -> Void = {},
        onChangeServer: @escaping @Sendable () async -> Void = {},
        now: Date = Date(timeIntervalSince1970: 10_000)
    ) -> SettingsViewModel {
        SettingsViewModel(
            tokenStore: tokenStore,
            autoregStore: autoregStore,
            unitsStore: unitsStore,
            buildInfo: buildInfo,
            lastSyncProvider: { lastSync },
            pairedWatchProvider: { pairedWatch },
            onSyncNow: onSyncNow,
            onResetCache: onResetCache,
            onChangeServer: onChangeServer,
            now: { now }
        )
    }

    // MARK: - Row helpers

    private func firstInfoValue(in vm: SettingsViewModel, rowID: String) -> String? {
        for section in vm.sections {
            for row in section.rows {
                if row.id == rowID, case .info(_, _, let value) = row {
                    return value
                }
            }
        }
        return nil
    }

    private func tapAction(in vm: SettingsViewModel, rowID: String) async {
        for section in vm.sections {
            for row in section.rows {
                if row.id == rowID, case .action(_, _, _, let onTap) = row {
                    onTap()
                    // Row closures hop back to @MainActor inside an
                    // unstructured `Task`. Drain the queue so side effects
                    // (store writes, confirm-sheet population) are
                    // observable before we assert.
                    await drainPendingTasks()
                    return
                }
            }
        }
        XCTFail("no action row with id \(rowID)")
    }

    private func pickPicker(
        in vm: SettingsViewModel,
        rowID: String,
        label: String
    ) async {
        for section in vm.sections {
            for row in section.rows {
                if row.id == rowID, case .picker(_, _, _, _, let onPick) = row {
                    onPick(label)
                    await drainPendingTasks()
                    return
                }
            }
        }
        XCTFail("no picker row with id \(rowID)")
    }

    /// Yields several times so any `Task { @MainActor in ... }` enqueued
    /// by a row callback runs to completion before assertions fire. Three
    /// yields is empirically sufficient: the row closure hops onto
    /// MainActor → the MainActor block runs → any nested Task (e.g. the
    /// async `onResetCache`) gets scheduled → that Task runs.
    private func drainPendingTasks() async {
        for _ in 0..<5 {
            await Task.yield()
        }
    }

    private func pickerSelected(in vm: SettingsViewModel, rowID: String) -> String? {
        for section in vm.sections {
            for row in section.rows {
                if row.id == rowID, case .picker(_, _, _, let selected, _) = row {
                    return selected
                }
            }
        }
        return nil
    }

    private func isInfo(_ row: SettingsRow) -> Bool {
        if case .info = row { return true }
        return false
    }

    private func isAction(_ row: SettingsRow) -> Bool {
        if case .action = row { return true }
        return false
    }

    private func isPicker(_ row: SettingsRow) -> Bool {
        if case .picker = row { return true }
        return false
    }

    private func actionDestructive(_ row: SettingsRow) -> Bool {
        if case .action(_, _, let destructive, _) = row {
            return destructive
        }
        return false
    }
}
