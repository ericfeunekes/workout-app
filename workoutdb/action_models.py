from __future__ import annotations

from datetime import date
from enum import Enum
from typing import Any, Annotated, Literal

from pydantic import BaseModel, Field, model_validator


class ActionStatus(str, Enum):
    STAGED = "staged"
    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"


class ActionType(str, Enum):
    PLAN_SCHEDULE = "plan_schedule"


class ActionBase(BaseModel):
    action_id: str
    source_ref: str | None = None


class PlanSchedulePayload(BaseModel):
    user: str
    date: date
    template: str | None = None
    rest: bool = False
    status: Literal["planned", "skipped", "done"] | None = None
    notes: str | None = None

    @model_validator(mode="after")
    def _validate_rest(self) -> "PlanSchedulePayload":
        if self.rest and self.template:
            raise ValueError("plan action cannot have both rest=true and template")
        if not self.rest and not self.template:
            raise ValueError("plan action must include template or rest=true")
        return self


class PlanScheduleAction(ActionBase):
    action_type: Literal[ActionType.PLAN_SCHEDULE]
    payload: PlanSchedulePayload


Action = Annotated[
    PlanScheduleAction,
    Field(discriminator="action_type"),
]


class ProposalFile(BaseModel):
    title: str | None = None
    actions: list[Action] = Field(default_factory=list)
    metadata: dict[str, Any] | None = None
