from __future__ import annotations

import json
import uuid
from pathlib import Path

from .action_models import ActionType, PlanScheduleAction, PlanSchedulePayload, ProposalFile
from .yaml_io import validate_yaml


def proposal_from_yaml(yaml_path: Path, title: str | None = None) -> ProposalFile:
    library = validate_yaml(yaml_path)
    actions = []
    for plan in library.plans:
        for day in plan.days:
            payload = PlanSchedulePayload(
                user=plan.user,
                date=day.date,
                template=day.template,
                rest=day.rest,
                status=day.status,
                notes=day.notes,
            )
            actions.append(
                PlanScheduleAction(
                    action_id=f"act-plan-{uuid.uuid4().hex}",
                    action_type=ActionType.PLAN_SCHEDULE,
                    payload=payload,
                    source_ref=f"plan:{plan.name or 'plan'}",
                )
            )
    return ProposalFile(title=title, actions=actions, metadata={"source": str(yaml_path)})


def proposal_from_days(
    *, user: str, days: list[dict], title: str | None = None, source_ref: str | None = None
) -> ProposalFile:
    actions = []
    for day in days:
        payload = PlanSchedulePayload(
            user=user,
            date=day["date"],
            template=day.get("template"),
            rest=day.get("rest", False),
            status=day.get("status"),
            notes=day.get("notes"),
        )
        actions.append(
            PlanScheduleAction(
                action_id=f"act-plan-{uuid.uuid4().hex}",
                action_type=ActionType.PLAN_SCHEDULE,
                payload=payload,
                source_ref=source_ref,
            )
        )
    return ProposalFile(title=title, actions=actions, metadata={"source": source_ref})


def write_proposal(proposal: ProposalFile, path: Path) -> None:
    path.write_text(proposal.model_dump_json(indent=2), encoding="utf-8")
