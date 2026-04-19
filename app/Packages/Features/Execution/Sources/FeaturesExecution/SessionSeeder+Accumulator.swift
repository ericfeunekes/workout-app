// SessionSeeder+Accumulator.swift
//
// Normalization-result types and the per-block accumulator pattern used
// by `SessionSeeder.seedWithNormalization`. Extracted here so the main
// seeder enum body stays under SwiftLint's `type_body_length` cap and
// the core seeding function stays under `function_body_length`.

import Foundation
import CoreDomain
import CoreSession
import WorkoutCoreFoundation

extension SessionSeeder {

    /// Record that a tabata block authored with N>1 items was collapsed
    /// to its first item. Produced alongside the `SessionState` so the
    /// VM can emit `execution.tabata_multi_item_collapsed` — without this
    /// signal a user authoring a multi-item tabata and seeing a single-
    /// item render has no trace that the drop happened. See
    /// `normalizeBlockItems` for the collapse rationale.
    public struct TabataCollapse: Sendable, Equatable {
        public let blockIndex: Int
        public let droppedExerciseIDs: [UUID]

        public init(blockIndex: Int, droppedExerciseIDs: [UUID]) {
            self.blockIndex = blockIndex
            self.droppedExerciseIDs = droppedExerciseIDs
        }

        public var droppedItemCount: Int { droppedExerciseIDs.count }
    }

    /// Result of `seedWithNormalization`: the initial state plus any
    /// normalization drops the seeder had to apply. Empty `tabataCollapses`
    /// means the pulled context passed through untouched (the common case).
    public struct SeedResult: Sendable {
        public let state: SessionState
        public let tabataCollapses: [TabataCollapse]

        public init(state: SessionState, tabataCollapses: [TabataCollapse] = []) {
            self.state = state
            self.tabataCollapses = tabataCollapses
        }
    }

    /// Per-block seed output: the ItemLogs, their set counts, the
    /// advancement policy the reducer will use, and an optional collapse
    /// record when normalization dropped items. `itemsInBlock` tracks how
    /// many items survived normalization so the outer accumulator can
    /// populate `structure.itemsPerBlock`.
    struct BlockSeed {
        let itemLogs: [SessionState.ItemLog]
        let perBlock: [Int]
        let itemsInBlock: Int
        let advancement: SessionState.BlockAdvancement
        let collapse: TabataCollapse?
    }

    /// Mutable accumulator the top-level seed loop writes into. Extracts
    /// the list-building boilerplate out of the seeding function so that
    /// function can stay focused on the "what blocks, what state shape"
    /// concern.
    struct SeedAccumulator {
        var items: [SessionState.ItemLog] = []
        var setsPerItem: [[Int]] = []
        var itemsPerBlock: [Int] = []
        var advancementByBlock: [SessionState.BlockAdvancement] = []
        var collapses: [TabataCollapse] = []

        mutating func append(_ seed: BlockSeed) {
            items.append(contentsOf: seed.itemLogs)
            setsPerItem.append(seed.perBlock)
            itemsPerBlock.append(seed.itemsInBlock)
            advancementByBlock.append(seed.advancement)
            if let collapse = seed.collapse {
                collapses.append(collapse)
            }
        }
    }

    /// If the block got collapsed (pre-count > post-count), return a
    /// `TabataCollapse` record capturing the dropped exercise ids.
    /// Returns nil for blocks that passed through untouched — the common
    /// case. Factored here (off the main enum body) so the core seeder
    /// stays under SwiftLint's `type_body_length` cap.
    static func tabataCollapseRecord(
        rawBlockItems: [WorkoutItem],
        normalizedItems: [WorkoutItem],
        blockIndex: Int,
        block: Block?
    ) -> TabataCollapse? {
        guard block?.timingMode == .tabata,
              rawBlockItems.count > normalizedItems.count else {
            return nil
        }
        let keptIDs = Set(normalizedItems.map(\.id))
        let dropped = rawBlockItems
            .filter { !keptIDs.contains($0.id) }
            .map(\.exerciseID)
        return TabataCollapse(blockIndex: blockIndex, droppedExerciseIDs: dropped)
    }
}
