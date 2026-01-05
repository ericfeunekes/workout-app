from __future__ import annotations

from datetime import date
from typing import Any, Literal

from pydantic import BaseModel, Field, field_validator, model_validator


class YamlModel(BaseModel):
    model_config = {"extra": "forbid"}


class Prescription(YamlModel):
    sets: int | None = None

    reps_target: int | None = None
    reps_min: int | None = None
    reps_max: int | None = None
    reps_is_per_side: bool = False

    time_sec_target: int | None = None
    time_sec_min: int | None = None
    time_sec_max: int | None = None

    distance_m_target: float | None = None
    distance_m_min: float | None = None
    distance_m_max: float | None = None

    pace_sec_per_m_target: float | None = None
    pace_sec_per_m_min: float | None = None
    pace_sec_per_m_max: float | None = None

    extra: dict[str, Any] = Field(default_factory=dict)

    @field_validator("sets")
    @classmethod
    def _validate_sets(cls, value: int | None) -> int | None:
        if value is None:
            return value
        if value <= 0:
            raise ValueError("sets must be > 0")
        return value

    @field_validator(
        "reps_target",
        "reps_min",
        "reps_max",
        "time_sec_target",
        "time_sec_min",
        "time_sec_max",
    )
    @classmethod
    def _validate_int_positive(cls, value: int | None) -> int | None:
        if value is None:
            return value
        if value < 0:
            raise ValueError("value must be >= 0")
        return value

    @field_validator(
        "distance_m_target",
        "distance_m_min",
        "distance_m_max",
        "pace_sec_per_m_target",
        "pace_sec_per_m_min",
        "pace_sec_per_m_max",
    )
    @classmethod
    def _validate_float_positive(cls, value: float | None) -> float | None:
        if value is None:
            return value
        if value < 0:
            raise ValueError("value must be >= 0")
        return value

    @model_validator(mode="after")
    def _validate_ranges(self) -> "Prescription":
        _validate_target_or_range(self.reps_target, self.reps_min, self.reps_max, "reps")
        _validate_target_or_range(
            self.time_sec_target, self.time_sec_min, self.time_sec_max, "time_sec"
        )
        _validate_target_or_range(
            self.distance_m_target, self.distance_m_min, self.distance_m_max, "distance_m"
        )
        _validate_target_or_range(
            self.pace_sec_per_m_target,
            self.pace_sec_per_m_min,
            self.pace_sec_per_m_max,
            "pace_sec_per_m",
        )
        return self


class SetPrescription(Prescription):
    sets: int | None = None

    @model_validator(mode="after")
    def _validate_sets_not_allowed(self) -> "SetPrescription":
        if self.sets is not None:
            raise ValueError("set_prescriptions must not include sets")
        return self


class Item(YamlModel):
    exercise: str
    prescription: Prescription | None = None
    set_prescriptions: list[SetPrescription] | None = None
    notes: str | None = None

    @model_validator(mode="after")
    def _validate_prescriptions(self) -> "Item":
        if self.set_prescriptions and self.prescription and self.prescription.sets is not None:
            raise ValueError("use set_prescriptions or prescription.sets, not both")
        return self


BlockType = Literal["warmup", "strength", "conditioning", "accessory", "mobility", "skill", "other"]
StructureType = Literal[
    "straight_sets",
    "superset",
    "circuit",
    "amrap",
    "emom",
    "intervals",
    "for_time",
    "freeform",
]


class Block(YamlModel):
    name: str | None = None
    block_type: BlockType
    structure_type: StructureType
    intent: dict[str, Any] = Field(default_factory=dict)
    items: list[Item]

    @model_validator(mode="after")
    def _validate_items(self) -> "Block":
        if not self.items:
            raise ValueError("block.items must not be empty")
        return self


class Template(YamlModel):
    name: str
    description: str | None = None
    intent: dict[str, Any] = Field(default_factory=dict)
    tags: list[str] = Field(default_factory=list)
    blocks: list[Block]

    @model_validator(mode="after")
    def _validate_blocks(self) -> "Template":
        if not self.blocks:
            raise ValueError("template.blocks must not be empty")
        return self


class User(YamlModel):
    name: str


class PlanDay(YamlModel):
    date: date
    template: str | None = None
    rest: bool = False
    notes: str | None = None
    status: Literal["planned", "skipped", "done"] | None = None

    @model_validator(mode="after")
    def _validate_rest(self) -> "PlanDay":
        if self.rest and self.template:
            raise ValueError("plan day cannot have both rest=true and template")
        if not self.rest and not self.template:
            raise ValueError("plan day must include template or rest=true")
        return self


class Plan(YamlModel):
    name: str | None = None
    user: str
    days: list[PlanDay]

    @model_validator(mode="after")
    def _validate_days(self) -> "Plan":
        if not self.days:
            raise ValueError("plan.days must not be empty")
        return self


class LibraryYaml(YamlModel):
    version: Literal[1]
    users: list[User] = Field(default_factory=list)
    templates: list[Template] = Field(default_factory=list)
    plans: list[Plan] = Field(default_factory=list)


def _validate_target_or_range(target: Any, min_v: Any, max_v: Any, label: str) -> None:
    if target is not None and (min_v is not None or max_v is not None):
        raise ValueError(f"{label}: target is mutually exclusive with min/max")
    if (min_v is None) ^ (max_v is None):
        raise ValueError(f"{label}: min and max must be provided together")
    if min_v is not None and max_v is not None and min_v > max_v:
        raise ValueError(f"{label}: min must be <= max")
