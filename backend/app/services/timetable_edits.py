"""Server-side planning and validation of AI timetable edit proposals."""

from copy import deepcopy
from datetime import datetime, timedelta
from typing import Any

from app.schemas import AiTimetableChange, TimetableEntryOut, VenueInput
from app.services.timetable import validate_live_timetable_entries


_FIELD_ALIASES = {
    "day": "exam_date",
    "date": "exam_date",
    "time": "start_time",
    "room": "venue",
    "invigilator": "invigilator_username",
    "lecturer": "invigilator_username",
}
_EDITABLE_FIELDS = {
    "exam_date",
    "start_time",
    "end_time",
    "venue",
    "invigilator_username",
    "course_code",
    "course_title",
    "student_level",
    "student_count",
}


def plan_ai_timetable_edits(
    *,
    changes: list[AiTimetableChange],
    entries: list[dict[str, Any]],
    venues: list[VenueInput],
    invigilators: list[str],
    course_catalogue: dict[str, dict[str, Any]],
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], list[dict[str, Any]]]:
    """Return final entries plus applied/rejected summaries without database writes."""
    original = deepcopy(entries)
    candidate = deepcopy(entries)
    accepted: list[tuple[AiTimetableChange, dict[str, Any]]] = []
    rejected: list[dict[str, Any]] = []
    next_temporary_id = -1

    for change in changes:
        error, next_temporary_id = _apply_change(
            candidate,
            change,
            course_catalogue,
            next_temporary_id,
        )
        if error:
            rejected.append(_rejected(change, error))
        else:
            accepted.append((change, _summary(change)))

    if not accepted:
        return original, [], rejected

    try:
        _validate(candidate, venues, invigilators)
        return candidate, [summary for _, summary in accepted], rejected
    except ValueError:
        # A full proposal is necessary for safe swaps: neither half of a room
        # swap is valid on its own.  If the whole plan is invalid, try each
        # independently so unrelated valid edits can still be applied.
        working = deepcopy(original)
        applied: list[dict[str, Any]] = []
        next_temporary_id = -1
        for change, summary in accepted:
            trial = deepcopy(working)
            error, next_temporary_id = _apply_change(
                trial,
                change,
                course_catalogue,
                next_temporary_id,
            )
            if error:
                rejected.append(_rejected(change, error))
                continue
            try:
                _validate(trial, venues, invigilators)
            except ValueError as validation_error:
                rejected.append(_rejected(change, str(validation_error)))
                continue
            working = trial
            applied.append(summary)
        return working, applied, rejected


def _apply_change(
    entries: list[dict[str, Any]],
    change: AiTimetableChange,
    course_catalogue: dict[str, dict[str, Any]],
    next_temporary_id: int,
) -> tuple[str | None, int]:
    if change.operation == "create":
        values = {key: value for key, value in change.values.items()}
        course_code = str(values.get("course_code", "")).strip().upper()
        course = course_catalogue.get(course_code.lower())
        if not course:
            return "New exams must use a known course with stored enrolment data.", next_temporary_id
        required = ("exam_date", "start_time", "venue", "invigilator_username")
        missing = [field for field in required if not str(values.get(field, "")).strip()]
        if missing:
            return f"A new exam is missing: {', '.join(missing)}.", next_temporary_id
        try:
            start_time = _normalise_time(values["start_time"])
            end_time = _normalise_time(values.get("end_time") or _end_from_duration(start_time, course["duration_minutes"]))
            student_count = int(values.get("student_count", course["student_count"]))
        except (TypeError, ValueError):
            return "A new exam has an invalid time or student count.", next_temporary_id
        entries.append(
            {
                "id": next_temporary_id,
                "course_code": course["course_code"],
                "course_title": course["course_title"],
                "exam_date": str(values["exam_date"]).strip(),
                "start_time": start_time,
                "end_time": end_time,
                "venue": str(values["venue"]).strip(),
                "student_level": course["student_level"],
                "student_count": student_count,
                "invigilator_username": str(values["invigilator_username"]).strip(),
            }
        )
        return None, next_temporary_id - 1

    if change.exam_id is None:
        return "An update must identify an exam_id.", next_temporary_id
    entry = next((item for item in entries if item["id"] == change.exam_id), None)
    if entry is None:
        return f"Exam {change.exam_id} no longer exists.", next_temporary_id
    field = _FIELD_ALIASES.get((change.field or "").strip().lower(), (change.field or "").strip())
    if field not in _EDITABLE_FIELDS:
        return f"{change.field or 'That'} is not an editable timetable field.", next_temporary_id
    if change.new is None:
        return f"No new value was supplied for {field}.", next_temporary_id
    # The timetable version is checked by the router immediately before this
    # proposal is planned and again atomically when it is saved.  Do not use
    # ``change.old`` as another concurrency token: it is model-generated text
    # and can differ from the supplied value only in formatting or be stale
    # within the same fresh request.  Treating it as authoritative caused
    # repeatable false "has changed since the AI read it" rejections.
    try:
        if field == "start_time":
            duration = _duration_minutes(entry["start_time"], entry["end_time"])
            entry[field] = _normalise_time(change.new)
            entry["end_time"] = _end_from_duration(entry[field], duration)
        elif field == "end_time":
            entry[field] = _normalise_time(change.new)
        elif field == "student_count":
            entry[field] = int(change.new)
        else:
            entry[field] = str(change.new).strip()
    except (TypeError, ValueError):
        return f"The new value for {field} is invalid.", next_temporary_id
    return None, next_temporary_id


def _validate(entries: list[dict[str, Any]], venues: list[VenueInput], invigilators: list[str]) -> None:
    validate_live_timetable_entries(
        [TimetableEntryOut(**entry) for entry in entries],
        venues=venues,
        invigilators=invigilators,
    )


def _normalise_time(value: Any) -> str:
    return datetime.strptime(str(value).strip()[:5], "%H:%M").strftime("%H:%M")


def _duration_minutes(start_time: str, end_time: str) -> int:
    start = datetime.strptime(start_time[:5], "%H:%M")
    end = datetime.strptime(end_time[:5], "%H:%M")
    return int((end - start).total_seconds() // 60)


def _end_from_duration(start_time: str, minutes: int) -> str:
    start = datetime.strptime(start_time[:5], "%H:%M")
    return (start + timedelta(minutes=minutes)).strftime("%H:%M")


def _summary(change: AiTimetableChange) -> dict[str, Any]:
    if change.operation == "create":
        return {"operation": "create", "course_code": change.values.get("course_code")}
    return {
        "operation": "update",
        "exam_id": change.exam_id,
        "field": change.field,
        "old": change.old,
        "new": change.new,
    }


def _rejected(change: AiTimetableChange, reason: str) -> dict[str, Any]:
    return {**_summary(change), "reason": reason}
