// ExecutionNextUpPresentation.swift
//
// Small "what happens after this?" read model for execution views.
// This is sequence display only; it does not make programming decisions.

import Foundation
import CoreDomain
import CoreSession

struct ExecutionNextUpPresentation: Equatable, Sendable {
    let label: String
    let title: String
    let detail: String?
}

extension ExecutionViewModel {
    var nextUpPresentation: ExecutionNextUpPresentation? {
        guard state.route == .today || state.route == .active || state.route == .rest else {
            return nil
        }
        guard let nextCursor = nextCursorAfterCurrent() else {
            return ExecutionNextUpPresentation(
                label: "up next",
                title: "Finish workout",
                detail: nil
            )
        }

        if isZeroItemBlock(nextCursor.blockIndex) {
            return ExecutionNextUpPresentation(
                label: label(for: nextCursor),
                title: "Rest block",
                detail: nil
            )
        }

        var previewState = state
        previewState.cursor = nextCursor
        guard let block = context.block(at: nextCursor.blockIndex) else { return nil }
        guard let content = driverRegistry
            .driver(for: block.timingMode)
            .activeContent(state: previewState, context: context) else {
            return nil
        }

        return ExecutionNextUpPresentation(
            label: label(for: nextCursor),
            title: content.exerciseName,
            detail: detail(for: content, cursor: nextCursor)
        )
    }

    private func detail(for content: ActiveContent, cursor: SessionState.Cursor) -> String {
        if let composite = compositeSet(at: cursor) {
            let unit = compositeUnitLabel(for: composite)
            return "\(content.loadDisplay) · \(composite.targetRepsPerSlot) reps × \(composite.slotCount) \(unit)s (\(content.repsDisplay) total)"
        }
        switch content.kind {
        case .strength:
            return "\(content.loadDisplay) · \(content.repsDisplay) reps"
        case .cardio:
            return "\(content.repsDisplay) · \(content.loadDisplay)"
        }
    }

    private func compositeSet(at cursor: SessionState.Cursor) -> SessionState.CompositeSetProgress? {
        guard let item = context.item(at: cursor.blockIndex, itemIndex: cursor.itemIndex) else {
            return nil
        }
        return state.compositeSets.first { progress in
            progress.itemID == item.id && progress.setIndex == cursor.setIndex
        }
    }

    private func label(for cursor: SessionState.Cursor) -> String {
        if cursor.blockIndex != state.cursor.blockIndex {
            return isZeroItemBlock(cursor.blockIndex) ? "next block" : "next block"
        }
        if cursor.itemIndex != state.cursor.itemIndex {
            return "next exercise"
        }
        if cursor.setIndex != state.cursor.setIndex {
            return "next set"
        }
        return "up next"
    }

    private func isZeroItemBlock(_ blockIndex: Int) -> Bool {
        guard blockIndex >= 0,
              blockIndex < state.structure.itemsPerBlock.count else {
            return false
        }
        return state.structure.itemsPerBlock[blockIndex] == 0
    }

    private func nextCursorAfterCurrent() -> SessionState.Cursor? {
        let cursor = state.cursor
        let structure = state.structure
        let blockIndex = cursor.blockIndex
        guard blockIndex >= 0,
              blockIndex < structure.itemsPerBlock.count else {
            return nil
        }

        if structure.itemsPerBlock[blockIndex] == 0 {
            return firstCursorOfNextBlock(after: blockIndex, in: structure)
        }

        let advancement = blockIndex < structure.advancementByBlock.count
            ? structure.advancementByBlock[blockIndex]
            : .setMajor

        switch advancement {
        case .setMajor:
            return nextSetMajorCursor(after: cursor, in: structure)
        case .roundRobin:
            return nextRoundRobinCursor(after: cursor, in: structure)
        case .zeroItem:
            return firstCursorOfNextBlock(after: blockIndex, in: structure)
        }
    }

    private func nextSetMajorCursor(
        after cursor: SessionState.Cursor,
        in structure: SessionState.Structure
    ) -> SessionState.Cursor? {
        let blockIndex = cursor.blockIndex
        let itemIndex = cursor.itemIndex
        guard itemIndex < structure.setsPerItem[blockIndex].count else {
            return nil
        }
        let setsInItem = structure.setsPerItem[blockIndex][itemIndex]
        if cursor.setIndex < setsInItem {
            return SessionState.Cursor(
                blockIndex: blockIndex,
                itemIndex: itemIndex,
                setIndex: cursor.setIndex + 1
            )
        }
        if itemIndex + 1 < structure.itemsPerBlock[blockIndex] {
            return SessionState.Cursor(
                blockIndex: blockIndex,
                itemIndex: itemIndex + 1,
                setIndex: 1
            )
        }
        return firstCursorOfNextBlock(after: blockIndex, in: structure)
    }

    private func nextRoundRobinCursor(
        after cursor: SessionState.Cursor,
        in structure: SessionState.Structure
    ) -> SessionState.Cursor? {
        let blockIndex = cursor.blockIndex
        let itemIndex = cursor.itemIndex
        guard itemIndex < structure.setsPerItem[blockIndex].count else {
            return nil
        }
        if itemIndex + 1 < structure.itemsPerBlock[blockIndex] {
            return SessionState.Cursor(
                blockIndex: blockIndex,
                itemIndex: itemIndex + 1,
                setIndex: cursor.setIndex
            )
        }
        let roundsInBlock = structure.setsPerItem[blockIndex][itemIndex]
        if cursor.setIndex < roundsInBlock {
            return SessionState.Cursor(
                blockIndex: blockIndex,
                itemIndex: 0,
                setIndex: cursor.setIndex + 1
            )
        }
        return firstCursorOfNextBlock(after: blockIndex, in: structure)
    }

    private func firstCursorOfNextBlock(
        after blockIndex: Int,
        in structure: SessionState.Structure
    ) -> SessionState.Cursor? {
        let nextBlock = blockIndex + 1
        guard nextBlock < structure.itemsPerBlock.count else { return nil }
        return SessionState.Cursor(blockIndex: nextBlock, itemIndex: 0, setIndex: 1)
    }
}
