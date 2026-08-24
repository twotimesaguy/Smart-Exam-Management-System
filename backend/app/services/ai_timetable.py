"""Gemini integration for interpreting timetable edits, never for writing data."""

import json
import os
from typing import Any

import httpx


class AiTimetableConfigurationError(RuntimeError):
    """Raised when the server cannot authenticate with Gemini."""


class AiTimetableInterpretationError(RuntimeError):
    """Raised when Gemini cannot return a safe, usable edit proposal."""


_SYSTEM_INSTRUCTION = """
You are a timetable-edit interpreter. Return ONLY a JSON object, with no markdown
or prose. You cannot access a database and you must never claim to apply a change.
Use only the timetable context supplied by the user message.

Schema:
{
  "changes": [
    {"operation":"update", "exam_id": 12, "field":"exam_date", "old":"2026-09-01", "new":"2026-09-08"},
    {"operation":"update", "exam_id": 12, "field":"venue", "old":"Room B12", "new":"Room B14"},
    {"operation":"create", "values":{"course_code":"CHEM101", "course_title":"Chemistry", "exam_date":"2026-09-04", "start_time":"10:00", "end_time":"12:00", "venue":"Room C3", "student_level":"Level 100", "student_count":40, "invigilator_username":"Dr Name"}}
  ],
  "unresolved": ["short explanation for an ambiguous or unknown request"]
}

For updates use the exact exam_id and the exact current values supplied. Valid
update fields are exam_date, start_time, end_time, venue, invigilator_username,
course_code, course_title, student_level, and student_count. The aliases day,
date, time, room, and invigilator are allowed but exact field names are preferred.
For a time move, update start_time; retain the same duration unless a distinct
end_time change is necessary. For a new exam, include every field in values.
Do not invent rooms, invigilators, student counts, courses, or dates. Put anything
that cannot be identified unambiguously in unresolved instead of changes.
""".strip()


async def interpret_timetable_edit(*, prompt: str, context: dict[str, Any]) -> dict[str, Any]:
    """Ask Gemini for a JSON proposal; callers validate it before writing anything."""
    api_key = os.getenv("GEMINI_API_KEY", "").strip()
    if not api_key:
        raise AiTimetableConfigurationError(
            "AI timetable editing is not configured. Add GEMINI_API_KEY to the backend service."
        )

    model = os.getenv("GEMINI_MODEL", "gemini-2.5-flash-lite").strip()
    if not model:
        raise AiTimetableConfigurationError(
            "AI timetable editing is not configured because GEMINI_MODEL is missing."
        )

    payload = {
        "systemInstruction": {"parts": [{"text": _SYSTEM_INSTRUCTION}]},
        "contents": [
            {
                "role": "user",
                "parts": [
                    {
                        "text": json.dumps(
                            {"instruction": prompt, "timetable_context": context},
                            ensure_ascii=False,
                        )
                    }
                ],
            }
        ],
        "generationConfig": {
            "temperature": 0,
            "responseMimeType": "application/json",
        },
    }

    try:
        async with httpx.AsyncClient(timeout=httpx.Timeout(60.0)) as client:
            response = await client.post(
                f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent",
                headers={"x-goog-api-key": api_key},
                json=payload,
            )
        response.raise_for_status()
    except httpx.HTTPStatusError as error:
        if error.response.status_code in {400, 401, 403}:
            raise AiTimetableConfigurationError(
                "AI timetable editing could not authenticate with Gemini. Check GEMINI_API_KEY and GEMINI_MODEL."
            ) from error
        raise AiTimetableInterpretationError(
            "The AI timetable service is temporarily unavailable. Please try again."
        ) from error
    except httpx.HTTPError as error:
        raise AiTimetableInterpretationError(
            "The AI timetable service could not be reached. Please try again."
        ) from error

    return _proposal_from_response(response.json())


def _proposal_from_response(payload: dict[str, Any]) -> dict[str, Any]:
    candidates = payload.get("candidates", [])
    if not candidates:
        raise AiTimetableInterpretationError(
            "The AI could not produce an edit proposal. Please rephrase the request."
        )

    parts = candidates[0].get("content", {}).get("parts", [])
    text = "".join(
        part.get("text", "") for part in parts if isinstance(part, dict)
    ).strip()
    if text.startswith("```"):
        text = text.strip("`").removeprefix("json").strip()

    try:
        proposal = json.loads(text)
    except json.JSONDecodeError as error:
        raise AiTimetableInterpretationError(
            "The AI returned an invalid edit proposal. Please try again."
        ) from error

    if not isinstance(proposal, dict) or not isinstance(proposal.get("changes", []), list):
        raise AiTimetableInterpretationError(
            "The AI returned an invalid edit proposal. Please try again."
        )
    if not isinstance(proposal.get("unresolved", []), list):
        proposal["unresolved"] = []
    return proposal
