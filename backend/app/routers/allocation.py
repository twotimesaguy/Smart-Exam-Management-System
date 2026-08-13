from datetime import date, datetime, timedelta
from io import BytesIO
from pathlib import Path
from zipfile import ZipFile
import xml.etree.ElementTree as ET

from fastapi import APIRouter, File, Form, HTTPException, UploadFile
from fastapi.responses import FileResponse
from openpyxl import load_workbook

from app.database import clear_expired_timetables, get_connection
from app.schemas import CourseInput, TimetableOut, TimetableRequest, VenueInput
from app.services.excel_export import build_timetable_workbook
from app.services.timetable import (
    generate_timetable_entries,
    generate_wizard_timetable_entries,
)

router = APIRouter(prefix="/allocation", tags=["allocation"])


@router.post("/generate", response_model=TimetableOut)
def generate_timetable(payload: TimetableRequest) -> TimetableOut:
    try:
        generated_entries = generate_timetable_entries(payload)
    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error))

    return _save_generated_timetable(payload, generated_entries)


@router.post("/generate/stored", response_model=TimetableOut)
def generate_timetable_from_stored_data() -> TimetableOut:
    payload = _stored_timetable_request()
    try:
        generated_entries = generate_timetable_entries(payload)
    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error))

    return _save_generated_timetable(payload, generated_entries, replace_existing=True)


@router.post("/generate/wizard", response_model=TimetableOut)
async def generate_timetable_from_wizard(
    title: str = Form("Smart Allocation Timetable"),
    start_date: str = Form(...),
    end_date: str = Form(...),
    semester: str = Form("First Semester"),
    time_slots: str = Form(...),
    lecturers: str = Form(""),
    venues: str = Form(""),
    courses: str = Form(""),
    programmes: str = Form(""),
    course_lecturers: str = Form(""),
    max_session_duration_minutes: int = Form(120),
    lecturer_files: list[UploadFile] | None = File(default=None),
    venue_files: list[UploadFile] | None = File(default=None),
    course_files: list[UploadFile] | None = File(default=None),
    programme_files: list[UploadFile] | None = File(default=None),
    course_lecturer_files: list[UploadFile] | None = File(default=None),
) -> TimetableOut:
    uploaded_data = await _extract_uploaded_documents(
        {
            "lecturers": lecturer_files,
            "venues": venue_files,
            "courses": course_files,
            "programmes": programme_files,
            "course_lecturers": course_lecturer_files,
        }
    )
    try:
        generated_entries = generate_wizard_timetable_entries(
            title=title,
            start_date=start_date,
            end_date=end_date,
            semester=semester,
            time_slots=time_slots,
            lecturers=_combine_source_text(lecturers, uploaded_data["lecturers"]),
            venues=_combine_source_text(venues, uploaded_data["venues"]),
            courses=_combine_source_text(courses, uploaded_data["courses"]),
            programmes=_combine_source_text(programmes, uploaded_data["programmes"]),
            course_lecturers=_combine_source_text(
                course_lecturers, uploaded_data["course_lecturers"]
            ),
            max_session_duration_minutes=max_session_duration_minutes,
        )
    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error))

    payload = TimetableRequest(
        title=title,
        exam_period=f"{start_date} to {end_date}",
        exam_dates=[],
        start_times=[],
        courses=[],
        venues=[],
        invigilators=[],
    )
    return _save_generated_timetable(payload, generated_entries, replace_existing=True)


def _save_generated_timetable(
    payload: TimetableRequest,
    generated_entries,
    *,
    replace_existing: bool = False,
) -> TimetableOut:
    with get_connection() as db:
        if replace_existing:
            db.execute("DELETE FROM timetables")

        cursor = db.execute(
            "INSERT INTO timetables (title, exam_period) VALUES (?, ?) RETURNING id",
            (payload.title, payload.exam_period),
        )
        timetable_id = cursor.fetchone()["id"]
        saved_entries = []

        for entry in generated_entries:
            entry_cursor = db.execute(
                """
                INSERT INTO timetable_entries
                    (timetable_id, course_code, course_title, exam_date, start_time, end_time,
                     venue, student_level, student_count, invigilator_username)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                RETURNING id
                """,
                (
                    timetable_id,
                    entry.course_code,
                    entry.course_title,
                    entry.exam_date,
                    entry.start_time,
                    entry.end_time,
                    entry.venue,
                    entry.student_level,
                    entry.student_count,
                    entry.invigilator_username,
                ),
            )
            entry_id = entry_cursor.fetchone()["id"]
            db.execute(
                "INSERT INTO assignments (timetable_entry_id, invigilator_username) VALUES (?, ?)",
                (entry_id, entry.invigilator_username),
            )
            saved_entries.append(entry.model_copy(update={"id": entry_id}))

    timetable = TimetableOut(
        id=timetable_id,
        title=payload.title,
        exam_period=payload.exam_period,
        entries=saved_entries,
    )
    build_timetable_workbook(
        {"id": timetable.id, "title": timetable.title, "exam_period": timetable.exam_period},
        [entry.model_dump() for entry in timetable.entries],
    )
    return timetable


@router.get("/timetables", response_model=list[TimetableOut])
def list_timetables() -> list[TimetableOut]:
    clear_expired_timetables()

    with get_connection() as db:
        timetables = db.execute(
            "SELECT id, title, exam_period FROM timetables ORDER BY generated_at DESC"
        ).fetchall()

        result = []
        for timetable in timetables:
            entries = db.execute(
                "SELECT * FROM timetable_entries WHERE timetable_id = ? ORDER BY exam_date, start_time",
                (timetable["id"],),
            ).fetchall()
            result.append(
                TimetableOut(
                    id=timetable["id"],
                    title=timetable["title"],
                    exam_period=timetable["exam_period"],
                    entries=[_entry_out(row) for row in entries],
                )
            )
    return result


@router.delete("/timetables")
def clear_timetables() -> dict[str, str]:
    with get_connection() as db:
        db.execute("DELETE FROM timetables")
    return {"message": "Generated timetable cleared."}


@router.get("/timetable/{timetable_id}/excel")
def download_timetable_excel(timetable_id: int) -> FileResponse:
    clear_expired_timetables()

    with get_connection() as db:
        timetable = db.execute(
            "SELECT id, title, exam_period FROM timetables WHERE id = ?",
            (timetable_id,),
        ).fetchone()
        if timetable is None:
            raise HTTPException(status_code=404, detail="Timetable not found.")

        entries = db.execute(
            "SELECT * FROM timetable_entries WHERE timetable_id = ? ORDER BY exam_date, start_time",
            (timetable_id,),
        ).fetchall()

    path = build_timetable_workbook(dict(timetable), [dict(row) for row in entries])
    return FileResponse(
        path,
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        filename=path.name,
    )


def _entry_out(row) -> dict:
    return {
        "id": row["id"],
        "course_code": row["course_code"],
        "course_title": row["course_title"],
        "exam_date": str(row["exam_date"]),
        "start_time": str(row["start_time"])[:5],
        "end_time": str(row["end_time"])[:5],
        "venue": row["venue"],
        "student_level": row["student_level"],
        "student_count": row["student_count"],
        "invigilator_username": row["invigilator_username"],
    }


async def _extract_uploaded_documents(
    files_by_type: dict[str, list[UploadFile] | None],
) -> dict[str, str]:
    extracted = {
        "lecturers": [],
        "venues": [],
        "courses": [],
        "programmes": [],
        "course_lecturers": [],
    }
    for source_type, files in files_by_type.items():
        for upload in files or []:
            filename = upload.filename or "uploaded-file"
            content = await upload.read()
            if content:
                extracted[source_type].append(_extract_document_text(filename, content))
    return {source_type: "\n\n".join(notes) for source_type, notes in extracted.items()}


def _combine_source_text(typed_text: str, uploaded_text: str) -> str:
    return "\n".join(value for value in (typed_text.strip(), uploaded_text.strip()) if value)


def _extract_document_text(filename: str, content: bytes) -> str:
    extension = Path(filename).suffix.lower()
    try:
        if extension in {".xlsx", ".xlsm"}:
            text = _extract_excel_text(content)
        elif extension == ".docx":
            text = _extract_docx_text(content)
        elif extension == ".pdf":
            text = _extract_pdf_text(content)
        elif extension in {".txt", ".csv"}:
            text = content.decode("utf-8", errors="ignore")
        else:
            text = ""
    except Exception as error:
        text = f"Could not extract text from this file: {error}"

    # Keep all extractable records for the deterministic local scheduler.
    extracted_text = text.strip()
    if not extracted_text:
        extracted_text = "Uploaded file accepted, but no readable text could be extracted."
    return f"File: {filename}\n{extracted_text}"


def _extract_excel_text(content: bytes) -> str:
    workbook = load_workbook(BytesIO(content), data_only=True, read_only=True)
    lines = []
    for sheet in workbook.worksheets:
        lines.append(f"Sheet: {sheet.title}")
        for row in sheet.iter_rows(values_only=True):
            # Keep empty cells. Dropping them shifts later values into the
            # wrong columns (for example, a capacity can become a venue name).
            values = ["" if value is None else str(value).strip() for value in row]
            while values and not values[-1]:
                values.pop()
            if any(values):
                lines.append(" | ".join(values))
    return "\n".join(lines)


def _extract_docx_text(content: bytes) -> str:
    with ZipFile(BytesIO(content)) as archive:
        try:
            document = archive.read("word/document.xml")
        except KeyError:
            return ""
    root = ET.fromstring(document)
    namespace = {"w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main"}
    paragraphs = []
    for paragraph in root.findall("./w:body/w:p", namespace):
        text = "".join(node.text or "" for node in paragraph.findall(".//w:t", namespace))
        if text.strip():
            paragraphs.append(text.strip())
    for table_row in root.findall(".//w:tr", namespace):
        cells = []
        for cell in table_row.findall(".//w:tc", namespace):
            cell_text = "".join(
                node.text or "" for node in cell.findall(".//w:t", namespace)
            ).strip()
            cells.append(cell_text)
        while cells and not cells[-1]:
            cells.pop()
        if any(cells):
            paragraphs.append(" | ".join(cells))
    return "\n".join(paragraphs)


def _extract_pdf_text(content: bytes) -> str:
    try:
        from pypdf import PdfReader
    except ImportError:
        return "PDF uploaded. Install pypdf on the backend to extract PDF text."

    reader = PdfReader(BytesIO(content))
    return "\n".join(page.extract_text() or "" for page in reader.pages)


def _stored_timetable_request() -> TimetableRequest:
    with get_connection() as db:
        settings = db.execute("SELECT * FROM allocation_settings WHERE id = 1").fetchone()
        courses = db.execute(
            """
            SELECT course_code, course_title, student_level, student_count, duration_minutes
            FROM allocation_courses
            ORDER BY id
            """
        ).fetchall()
        venues = db.execute(
            "SELECT name, capacity FROM allocation_venues ORDER BY id"
        ).fetchall()
        invigilators = db.execute(
            """
            SELECT username, MIN(sort_order) AS sort_order
            FROM (
                SELECT username, id AS sort_order
                FROM allocation_invigilators
                UNION ALL
                SELECT username, 1000000 + id AS sort_order
                FROM users
                WHERE role = 'invigilator'
            )
            GROUP BY lower(username)
            ORDER BY sort_order
            """
        ).fetchall()

    if settings is None:
        raise HTTPException(status_code=400, detail="Allocation settings are not configured.")
    if date.today() > date.fromisoformat(settings["exam_end_date"]):
        clear_expired_timetables()
        raise HTTPException(
            status_code=400,
            detail="The exam period is over, so the timetable has been cleared.",
        )

    return TimetableRequest(
        title=settings["title"],
        exam_period=settings["exam_period"],
        exam_dates=_weekly_exam_dates(
            settings["exam_start_date"],
            settings["exam_end_date"],
            max(len(courses), len(invigilators)),
        ),
        start_times=[
            item.strip()
            for item in settings["start_times"].split(",")
            if item.strip()
        ],
        courses=[
            CourseInput(
                course_code=row["course_code"],
                course_title=row["course_title"],
                student_level=row["student_level"],
                student_count=row["student_count"],
                duration_minutes=row["duration_minutes"],
            )
            for row in courses
        ],
        venues=[
            VenueInput(name=row["name"], capacity=row["capacity"])
            for row in venues
        ],
        invigilators=[row["username"] for row in invigilators],
    )


def _weekly_exam_dates(start_date: str, end_date: str, needed_count: int) -> list[str]:
    start = datetime.strptime(start_date, "%Y-%m-%d").date()
    end = datetime.strptime(end_date, "%Y-%m-%d").date()
    dates: list[date] = []
    current = start

    while current <= end and len(dates) < needed_count:
        dates.append(current)
        current += timedelta(days=7)

    if not dates:
        return []

    while len(dates) < needed_count:
        dates.append(dates[-1])

    return [item.isoformat() for item in dates]
