"""Pure primitive contract validation shared by server routes."""

from dataclasses import dataclass
from typing import Protocol

PrimitiveTreeNode = dict[str, object]


class PrimitiveLogLike(Protocol):
    id: str
    role: str
    slot_id: str | None
    set_id: str | None
    block_id: str | None
    workout_id: str
    planned_exercise_id: str | None
    performed_exercise_id: str | None
    set_index: int
    set_repeat_index: int
    block_repeat_index: int


@dataclass(frozen=True)
class PrimitiveContractError(Exception):
    field: str
    log_id: str
    workout_id: str

    def __str__(self) -> str:
        return (
            f"primitive log {self.log_id} has {self.field} outside "
            f"workout {self.workout_id}'s primitive tree"
        )


class PrimitiveLogTreeIndex:
    def __init__(self, blocks: list[dict]) -> None:
        self.block_by_id: dict[str, PrimitiveTreeNode] = {}
        self.set_by_id: dict[str, PrimitiveTreeNode] = {}
        self.set_to_block: dict[str, str] = {}
        self.slot_to_set: dict[str, str] = {}
        self.slot_to_exercise: dict[str, str] = {}
        for block in blocks:
            block_id = block["id"]
            self.block_by_id[block_id] = block
            for primitive_set in block.get("sets", []):
                set_id = primitive_set["id"]
                self.set_by_id[set_id] = primitive_set
                self.set_to_block[set_id] = block_id
                for slot in primitive_set.get("slots", []):
                    slot_id = slot["id"]
                    self.slot_to_set[slot_id] = set_id
                    self.slot_to_exercise[slot_id] = slot["exercise_id"]


def validate_primitive_log_references(log: PrimitiveLogLike, blocks: list[dict]) -> None:
    index = PrimitiveLogTreeIndex(blocks)
    if log.role == "block_result":
        _validate_block_result_log(log, index)
        return
    primitive_set = _validate_log_set_coordinates(log, index)
    if log.role == "set_result":
        _validate_set_result_log(log, primitive_set)
        return
    _validate_slot_log(log, index)


def _validate_block_result_log(log: PrimitiveLogLike, index: PrimitiveLogTreeIndex) -> None:
    block = index.block_by_id.get(log.block_id or "")
    if block is None:
        _raise_invalid_primitive_log("block_id", log)
    if log.block_repeat_index >= block.get("repeat", 1):
        _raise_invalid_primitive_log("block_repeat_index", log)
    if not block.get("work_target"):
        _raise_invalid_primitive_log("block_result", log)
    if log.set_repeat_index != 0 or log.set_index != 0:
        _raise_invalid_primitive_log("aggregate_index", log)


def _validate_log_set_coordinates(
    log: PrimitiveLogLike, index: PrimitiveLogTreeIndex
) -> PrimitiveTreeNode:
    primitive_set = index.set_by_id.get(log.set_id or "")
    if primitive_set is None or index.set_to_block.get(log.set_id or "") != log.block_id:
        _raise_invalid_primitive_log("set_id", log)
    block = index.block_by_id[log.block_id or ""]
    if log.block_repeat_index >= block.get("repeat", 1):
        _raise_invalid_primitive_log("block_repeat_index", log)
    if log.set_repeat_index >= primitive_set.get("repeat", 1):
        _raise_invalid_primitive_log("set_repeat_index", log)
    return primitive_set


def _validate_set_result_log(log: PrimitiveLogLike, primitive_set: PrimitiveTreeNode) -> None:
    if not primitive_set.get("work_target"):
        _raise_invalid_primitive_log("set_result", log)
    if log.set_index != 0:
        _raise_invalid_primitive_log("aggregate_index", log)


def _validate_slot_log(log: PrimitiveLogLike, index: PrimitiveLogTreeIndex) -> None:
    if log.slot_id is None or index.slot_to_set.get(log.slot_id) != log.set_id:
        _raise_invalid_primitive_log("slot_id", log)
    if (
        log.planned_exercise_id is not None
        and index.slot_to_exercise.get(log.slot_id) != log.planned_exercise_id
    ):
        _raise_invalid_primitive_log("planned_exercise_id", log)
    if (
        log.performed_exercise_id is not None
        and index.slot_to_exercise.get(log.slot_id) != log.performed_exercise_id
    ):
        _raise_invalid_primitive_log("performed_exercise_id", log)


def _raise_invalid_primitive_log(field: str, log: PrimitiveLogLike) -> None:
    raise PrimitiveContractError(field=field, log_id=log.id, workout_id=log.workout_id)
