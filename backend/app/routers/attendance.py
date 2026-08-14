import logging
from datetime import date

from fastapi import APIRouter, File, Form, HTTPException, UploadFile
from fastapi.responses import FileResponse

from app.database import get_connection
from app.schemas import AttendanceCreate, AttendanceOut, RecognizedStudentOut
from app.services.face_recognition import face_service
from app.services.pdf_export import build_attendance_pdf

router = APIRouter(prefix="/attendance", tags=["attendance"])
logger = logging.getLogger(__name__)


@router.post("/recognize", response_model=RecognizedStudentOut)
async def recognize_student(
    recorded_by: str = Form("System"),
    face_image: UploadFile = File(...),
) -> RecognizedStudentOut:
    captured_embedding = await _embedding_from_upload(face_image)

    with get_connection() as db:
        students = db.execute(
            "SELECT student_id, full_name, programme, level, face_embedding FROM students"
        ).fetchall()

    best_student = None
    best_score = 0.0
    for student in students:
        score = face_service.similarity(
            captured_embedding,
            face_service.deserialize(student["face_embedding"]),
        )
        if score > best_score:
            best_score = score
            best_student = student

    if best_student is None or best_score < face_service.match_threshold:
        raise HTTPException(status_code=404, detail="No matching student found.")

    with get_connection() as db:
        exam = _today_exam_for_student(
            db,
            student_level=best_student["level"],
            recorded_by=recorded_by,
        )
        if exam is None:
            return RecognizedStudentOut(
                student_id=best_student["student_id"],
                full_name=best_student["full_name"],
                programme=best_student["programme"],
                level=best_student["level"],
                confidence=best_score,
                exam_scheduled_today=False,
                message=(
                    f"{best_student['full_name']} has no exam scheduled today. "
                    "Attendance was not recorded."
                ),
            )

        # A rescan must not create another line in the course attendance PDF.
        existing_record = db.execute(
            """
            SELECT id
            FROM attendance_records
            WHERE student_id = ?
              AND course_code = ?
              AND exam_date = ?
            LIMIT 1
            """,
            (best_student["student_id"], exam["course_code"], exam["exam_date"]),
        ).fetchone()
        if existing_record is None:
            db.execute(
                """
                INSERT INTO attendance_records
                    (student_id, full_name, course_title, course_code, venue, recorded_by, confidence, exam_date)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    best_student["student_id"],
                    best_student["full_name"],
                    exam["course_title"],
                    exam["course_code"],
                    exam["venue"],
                    recorded_by.strip() or "System",
                    best_score,
                    exam["exam_date"],
                ),
            )

    return RecognizedStudentOut(
        student_id=best_student["student_id"],
        full_name=best_student["full_name"],
        programme=best_student["programme"],
        level=best_student["level"],
        confidence=best_score,
        exam_scheduled_today=True,
        message="Exam scheduled today. Attendance recorded.",
        course_title=exam["course_title"],
        course_code=exam["course_code"],
        venue=exam["venue"],
        exam_date=exam["exam_date"],
        start_time=exam["start_time"],
        end_time=exam["end_time"],
    )


def _today_exam_for_student(db, *, student_level: str, recorded_by: str):
    """Find the paper for the recognised student without asking for course input.

    The invigilator account is part of the generated allocation.  It resolves
    the correct course and venue when a level has more than one paper on the
    same day.  If the account has no assignment, a single unambiguous paper
    for the student's level is still accepted.
    """
    today = date.today().isoformat()
    entries = db.execute(
        """
        SELECT course_code, course_title, exam_date, start_time, end_time, venue,
               student_level, invigilator_username
        FROM timetable_entries
        WHERE exam_date = ?
        ORDER BY start_time, venue
        """,
        (today,),
    ).fetchall()
    level_entries = [
        entry
        for entry in entries
        if _normalise_level(entry["student_level"]) == _normalise_level(student_level)
    ]
    if not level_entries:
        return None

    invigilator_entries = [
        entry
        for entry in level_entries
        if entry["invigilator_username"].strip().casefold()
        == recorded_by.strip().casefold()
    ]
    if invigilator_entries:
        return invigilator_entries[0]

    # A course can have multiple venue batches.  They still represent one
    # paper, so a non-assigned scanner can safely record that paper.
    course_codes = {entry["course_code"] for entry in level_entries}
    if len(course_codes) == 1:
        return level_entries[0]

    raise HTTPException(
        status_code=409,
        detail=(
            "More than one paper is scheduled for this student's level today. "
            "Sign in with the invigilator account assigned to the exam so the "
            "system can select the correct paper automatically."
        ),
    )


def _normalise_level(value: str) -> str:
    cleaned = value.casefold().replace("level", "").replace("year", "")
    return "".join(character for character in cleaned if character.isalnum())


async def _embedding_from_upload(face_image: UploadFile) -> list[float]:
    image_bytes = await face_image.read()
    try:
        return face_service.embedding_from_bytes(image_bytes)
    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error)) from error
    except Exception as error:
        logger.exception("Unable to process an attendance face image")
        raise HTTPException(
            status_code=422,
            detail=(
                "The face photo could not be processed. Capture a clear JPEG "
                "or PNG photo and try again."
            ),
        ) from error


@router.post("/record", response_model=AttendanceOut)
def record_attendance(payload: AttendanceCreate) -> AttendanceOut:
    with get_connection() as db:
        student = db.execute(
            "SELECT student_id, full_name FROM students WHERE student_id = ?",
            (payload.student_id,),
        ).fetchone()
        if student is None:
            raise HTTPException(status_code=404, detail="Student not found.")

        cursor = db.execute(
            """
            INSERT INTO attendance_records
                (student_id, full_name, course_title, course_code, venue, recorded_by, confidence)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            RETURNING
                id, student_id, full_name, course_title, course_code, venue, recorded_by,
                confidence, exam_date, recorded_at
            """,
            (
                student["student_id"],
                student["full_name"],
                payload.course_title,
                payload.course_code,
                payload.venue,
                payload.recorded_by,
                payload.confidence,
            ),
        )
        row = cursor.fetchone()

    return AttendanceOut(**dict(row))


@router.post("/recognize-and-record", response_model=AttendanceOut)
async def recognize_and_record(
    course_title: str = Form(...),
    course_code: str = Form(...),
    course_lecturer: str = Form(...),
    venue: str = Form(...),
    exam_date: str = Form(...),
    recorded_by: str = Form(...),
    face_image: UploadFile = File(...),
) -> AttendanceOut:
    captured_embedding = await _embedding_from_upload(face_image)

    with get_connection() as db:
        students = db.execute(
            "SELECT student_id, full_name, face_embedding FROM students"
        ).fetchall()

        best_student = None
        best_score = 0.0
        for student in students:
            score = face_service.similarity(
                captured_embedding,
                face_service.deserialize(student["face_embedding"]),
            )
            if score > best_score:
                best_score = score
                best_student = student

        if best_student is None or best_score < face_service.match_threshold:
            raise HTTPException(status_code=404, detail="No matching student found.")

        cursor = db.execute(
            """
            INSERT INTO attendance_records
                (student_id, full_name, course_title, course_code, venue, recorded_by, confidence, exam_date)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            RETURNING
                id, student_id, full_name, course_title, course_code, venue, recorded_by,
                confidence, exam_date, recorded_at
            """,
            (
                best_student["student_id"],
                best_student["full_name"],
                course_title,
                course_code,
                venue,
                course_lecturer.strip() or recorded_by,
                best_score,
                exam_date,
            ),
        )
        row = cursor.fetchone()

    return AttendanceOut(**dict(row))


@router.get("/records", response_model=list[AttendanceOut])
def list_attendance_records(course_code: str | None = None) -> list[AttendanceOut]:
    query = """
        SELECT
            id, student_id, full_name, course_title, course_code, venue, recorded_by,
            confidence, exam_date, recorded_at
        FROM attendance_records
    """
    parameters: tuple[str, ...] = ()
    if course_code:
        query += " WHERE course_code = ?"
        parameters = (course_code,)
    query += " ORDER BY recorded_at DESC"

    with get_connection() as db:
        rows = db.execute(query, parameters).fetchall()
    return [AttendanceOut(**dict(row)) for row in rows]


@router.get("/export/pdf")
def export_attendance_pdf(
    course_code: str, exam_date: str, course_title: str | None = None
) -> FileResponse:
    query = """
        SELECT
            attendance_records.id,
            attendance_records.student_id,
            attendance_records.full_name,
            attendance_records.course_title,
            attendance_records.course_code,
            attendance_records.venue,
            attendance_records.recorded_by,
            attendance_records.confidence,
            attendance_records.exam_date,
            attendance_records.recorded_at,
            students.face_image_path
        FROM attendance_records
        LEFT JOIN students
            ON students.student_id = attendance_records.student_id
    """
    query += """
        WHERE attendance_records.course_code = ?
          AND attendance_records.exam_date = ?
    """
    parameters = (course_code, exam_date)
    query += " ORDER BY attendance_records.recorded_at ASC"

    with get_connection() as db:
        rows = db.execute(query, parameters).fetchall()

    path = build_attendance_pdf(
        [dict(row) for row in rows],
        course_code=course_code,
        course_title=course_title,
        exam_date=exam_date,
    )
    return FileResponse(path, media_type="application/pdf", filename=path.name)
