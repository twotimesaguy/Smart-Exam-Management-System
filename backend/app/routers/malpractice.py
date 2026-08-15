import mimetypes
from pathlib import Path
from uuid import uuid4

from fastapi import APIRouter, File, Form, HTTPException, UploadFile
from fastapi.responses import FileResponse, Response

from app.database import get_connection
from app.schemas import MalpracticeStatusUpdate
from app.services.malpractice_forwarder import forward_report
from app.services.pdf_export import build_malpractice_pdf

router = APIRouter(prefix="/malpractice", tags=["malpractice"])


@router.post("/reports", status_code=201)
async def create_malpractice_report(
    student_id: str = Form(...),
    student_level: str = Form(...),
    course_title: str = Form(...),
    course_code: str = Form(...),
    venue: str = Form(...),
    invigilator_name: str = Form(...),
    chief_invigilator_name: str = Form(...),
    chief_invigilator_approved: bool = Form(...),
    incident_description: str = Form(...),
    student_statement: str = Form(...),
    student_face_image: UploadFile | None = File(None),
    foreign_material_image: UploadFile | None = File(None),
    student_statement_audio: UploadFile | None = File(None),
) -> dict:
    student_face_path = await _save_optional_file("student_face", student_id, student_face_image)
    material_path = await _save_optional_file("foreign_material", student_id, foreign_material_image)
    audio_bytes, audio_content_type, audio_filename = await _read_optional_audio(
        student_statement_audio
    )

    with get_connection() as db:
        cursor = db.execute(
            """
            INSERT INTO malpractice_reports
                (student_id, student_level, course_title, course_code, venue, invigilator_name,
                 chief_invigilator_name, chief_invigilator_approved, incident_description, student_statement, student_face_image_path,
                 foreign_material_image_path, student_statement_audio,
                 student_statement_audio_content_type, student_statement_audio_filename)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            RETURNING *
            """,
            (
                student_id,
                student_level,
                course_title,
                course_code,
                venue,
                invigilator_name,
                chief_invigilator_name,
                chief_invigilator_approved,
                incident_description,
                student_statement,
                str(student_face_path) if student_face_path else None,
                str(material_path) if material_path else None,
                audio_bytes,
                audio_content_type,
                audio_filename,
            ),
        )
        row = cursor.fetchone()
        report_id = row["id"]

    report_payload = _report_payload(row)
    status, error = await forward_report(report_payload)

    with get_connection() as db:
        db.execute(
            """
            UPDATE malpractice_reports
            SET forwarded_status = ?, forwarded_error = ?
            WHERE id = ?
            """,
            (status, error, report_id),
        )
        updated = db.execute(
            "SELECT * FROM malpractice_reports WHERE id = ?",
            (report_id,),
        ).fetchone()

    return _report_payload(updated)


@router.get("/reports")
def list_malpractice_reports() -> list[dict]:
    with get_connection() as db:
        rows = db.execute(
            "SELECT * FROM malpractice_reports ORDER BY created_at DESC"
        ).fetchall()
    return [_report_payload(row) for row in rows]


@router.get("/reports/export/pdf")
def export_malpractice_reports_pdf() -> FileResponse:
    with get_connection() as db:
        rows = db.execute(
            "SELECT * FROM malpractice_reports ORDER BY created_at ASC"
        ).fetchall()

    path = build_malpractice_pdf([dict(row) for row in rows])
    return FileResponse(path, media_type="application/pdf", filename=path.name)


@router.get("/reports/{report_id}/evidence/{evidence_type}")
def get_malpractice_evidence(report_id: int, evidence_type: str) -> FileResponse:
    image_columns = {
        "student-face": "student_face_image_path",
        "foreign-material": "foreign_material_image_path",
    }
    image_column = image_columns.get(evidence_type)
    if image_column is None:
        raise HTTPException(status_code=404, detail="Evidence image not found.")

    with get_connection() as db:
        row = db.execute(
            f"SELECT {image_column} FROM malpractice_reports WHERE id = ?",
            (report_id,),
        ).fetchone()

    if row is None:
        raise HTTPException(status_code=404, detail="Report not found.")

    image_path = row[image_column]
    if not image_path:
        raise HTTPException(status_code=404, detail="Evidence image not found.")

    path = Path(image_path)
    if not path.exists():
        raise HTTPException(status_code=404, detail="Evidence image not found.")

    return FileResponse(path)


@router.get("/reports/{report_id}/statement-audio")
def get_student_statement_audio(report_id: int) -> Response:
    with get_connection() as db:
        row = db.execute(
            """
            SELECT student_statement_audio, student_statement_audio_content_type,
                   student_statement_audio_filename
            FROM malpractice_reports
            WHERE id = ?
            """,
            (report_id,),
        ).fetchone()

    if row is None or row["student_statement_audio"] is None:
        raise HTTPException(status_code=404, detail="Voice recording not found.")

    filename = Path(row["student_statement_audio_filename"] or "student_statement.m4a").name
    return Response(
        content=bytes(row["student_statement_audio"]),
        media_type=row["student_statement_audio_content_type"] or "audio/mp4",
        headers={"Content-Disposition": f'inline; filename="{filename}"'},
    )


@router.patch("/reports/{report_id}")
def update_malpractice_report(
    report_id: int,
    payload: MalpracticeStatusUpdate,
) -> dict:
    with get_connection() as db:
        row = db.execute(
            "SELECT id FROM malpractice_reports WHERE id = ?",
            (report_id,),
        ).fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="Report not found.")

        updated = db.execute(
            """
            UPDATE malpractice_reports
            SET case_status = ?,
                resolution_notes = ?,
                handled_by = ?,
                handled_at = CURRENT_TIMESTAMP::text
            WHERE id = ?
            RETURNING *
            """,
            (
                payload.case_status,
                payload.resolution_notes,
                payload.handled_by,
                report_id,
            ),
        ).fetchone()

    return _report_payload(updated)


@router.post("/reports/{report_id}/forward")
async def forward_existing_report(report_id: int) -> dict:
    with get_connection() as db:
        row = db.execute(
            "SELECT * FROM malpractice_reports WHERE id = ?",
            (report_id,),
        ).fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="Report not found.")

    status, error = await forward_report(_report_payload(row))

    with get_connection() as db:
        db.execute(
            "UPDATE malpractice_reports SET forwarded_status = ?, forwarded_error = ? WHERE id = ?",
            (status, error, report_id),
        )
        updated = db.execute(
            "SELECT * FROM malpractice_reports WHERE id = ?",
            (report_id,),
        ).fetchone()

    return _report_payload(updated)


async def _save_optional_file(
    evidence_type: str,
    student_id: str,
    upload: UploadFile | None,
) -> Path | None:
    if upload is None:
        return None

    evidence_dir = Path("backend/data/malpractice_evidence")
    evidence_dir.mkdir(parents=True, exist_ok=True)
    extension = Path(upload.filename or "evidence.jpg").suffix or ".jpg"
    path = evidence_dir / f"{student_id}_{evidence_type}_{uuid4().hex}{extension}"
    path.write_bytes(await upload.read())
    return path


async def _read_optional_audio(
    upload: UploadFile | None,
) -> tuple[bytes | None, str | None, str | None]:
    if upload is None:
        return None, None, None

    audio_bytes = await upload.read()
    if not audio_bytes:
        raise HTTPException(status_code=400, detail="The voice recording is empty.")
    if len(audio_bytes) > 15 * 1024 * 1024:
        raise HTTPException(
            status_code=413,
            detail="The voice recording is too large. Keep it under 15 MB.",
        )

    filename = Path(upload.filename or "student_statement.m4a").name
    guessed_content_type = mimetypes.guess_type(filename)[0]
    content_type = (
        upload.content_type
        if upload.content_type and upload.content_type.startswith("audio/")
        else guessed_content_type or "audio/mp4"
    )
    return audio_bytes, content_type, filename


def _report_payload(row) -> dict:
    """Return report metadata without sending the audio blob in JSON/webhooks."""
    report = dict(row)
    report.pop("student_statement_audio", None)
    return report
