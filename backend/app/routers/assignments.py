from fastapi import APIRouter, HTTPException

from app.database import get_connection
from app.schemas import AssignmentStatusUpdate

router = APIRouter(prefix="/assignments", tags=["assignments"])


@router.get("/{invigilator_username}")
def assignments_for_invigilator(invigilator_username: str) -> list[dict]:
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
def update_assignment_status(assignment_id: int, payload: AssignmentStatusUpdate) -> dict:
    with get_connection() as db:
        cursor = db.execute(
            "UPDATE assignments SET status = ? WHERE id = ?",
            (payload.status, assignment_id),
        )
        if cursor.rowcount == 0:
            raise HTTPException(status_code=404, detail="Assignment not found.")
    return {"id": assignment_id, "status": payload.status}
