from fastapi import APIRouter, Depends, HTTPException

from app.database import get_connection
from app.dependencies.auth import CurrentUser, get_current_user, require_roles
from app.schemas import AssignmentStatusUpdate

router = APIRouter(
    prefix="/assignments",
    tags=["assignments"],
    dependencies=[Depends(get_current_user)],
)


@router.get("/{invigilator_username}")
def assignments_for_invigilator(
    invigilator_username: str,
    current_user: CurrentUser = Depends(require_roles("admin", "invigilator")),
) -> list[dict]:
    if (
        current_user.role == "invigilator"
        and current_user.username.casefold() != invigilator_username.casefold()
    ):
        raise HTTPException(status_code=403, detail="You can only view your own assignments.")
    with get_connection() as db:
        rows = db.execute(
            """
            SELECT
                assignments.id,
                assignments.status,
                timetable_entries.course_code,
                timetable_entries.course_title,
                timetable_entries.exam_date,
                timetable_entries.start_time,
                timetable_entries.end_time,
                timetable_entries.venue,
                timetable_entries.student_level,
                timetable_entries.student_count,
                timetable_entries.invigilator_username
            FROM assignments
            JOIN timetable_entries ON timetable_entries.id = assignments.timetable_entry_id
            WHERE lower(assignments.invigilator_username) = lower(?)
            ORDER BY timetable_entries.exam_date, timetable_entries.start_time
            """,
            (invigilator_username,),
        ).fetchall()
    return [dict(row) for row in rows]


@router.patch("/{assignment_id}/status")
def update_assignment_status(
    assignment_id: int,
    payload: AssignmentStatusUpdate,
    current_user: CurrentUser = Depends(require_roles("admin", "invigilator")),
) -> dict:
    with get_connection() as db:
        if current_user.role == "invigilator":
            assignment = db.execute(
                """
                SELECT assignments.id
                FROM assignments
                JOIN timetable_entries ON timetable_entries.id = assignments.timetable_entry_id
                WHERE assignments.id = ?
                  AND lower(timetable_entries.invigilator_username) = lower(?)
                """,
                (assignment_id, current_user.username),
            ).fetchone()
            if assignment is None:
                raise HTTPException(
                    status_code=403,
                    detail="You can only update your own assignments.",
                )
        cursor = db.execute(
            "UPDATE assignments SET status = ? WHERE id = ?",
            (payload.status, assignment_id),
        )
        if cursor.rowcount == 0:
            raise HTTPException(status_code=404, detail="Assignment not found.")
    return {"id": assignment_id, "status": payload.status}
