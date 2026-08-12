from pathlib import Path
from uuid import uuid4

from fastapi import APIRouter, File, Form, HTTPException, UploadFile
from fastapi.responses import FileResponse

from app.database import get_connection
from app.schemas import MalpracticeStatusUpdate
from app.services.malpractice_forwarder import forward_report
from app.services.notifications import notify_role
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
    incident_description: str = Form(...),
    student_statement: str = Form(...),
    student_face_image: UploadFile | None = File(None),
    foreign_material_image: UploadFile | None = File(None),
) -> dict:
    student_face_path = await _save_optional_file("student_face", student_id, student_face_image)
    material_path = await _save_optional_file("foreign_material", student_id, foreign_material_image)

    with get_connection() as db:
        cursor = db.execute(
            """
            INSERT INTO malpractice_reports
                (student_id, student_level, course_title, course_code, venue, invigilator_name,
                 incident_description, student_statement, student_face_image_path,
                 foreign_material_image_path)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            RETURNING *
            """,
            (
                student_id,
                student_level,
                course_title,
                course_code,
                venue,
                invigilator_name,
                incident_description,
                student_statement,
                str(student_face_path) if student_face_path else None,
                str(material_path) if material_path else None,
            ),
        )
        row = cursor.fetchone()
        report_id = row["id"]
        notify_role(
            db,
            role="disciplinary_officer",
            title="New malpractice report",
            message=(
                f"{invigilator_name} reported {student_id} for "
                f"{course_code} at {venue}."
            ),
        )

    report_payload = dict(row)
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

    return dict(updated)


@router.get("/reports")
def list_malpractice_reports() -> list[dict]:
    with get_connection() as db:
        rows = db.execute(
            "SELECT * FROM malpractice_reports ORDER BY created_at DESC"
        ).fetchall()
    return [dict(row) for row in rows]


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
                handled_at = CURRENT_TIMESTAMP
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

    return dict(updated)


@router.post("/reports/{report_id}/forward")
async def forward_existing_report(report_id: int) -> dict:
    with get_connection() as db:
        row = db.execute(
            "SELECT * FROM malpractice_reports WHERE id = ?",
            (report_id,),
        ).fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="Report not found.")

    status, error = await forward_report(dict(row))

    with get_connection() as db:
        db.execute(
            "UPDATE malpractice_reports SET forwarded_status = ?, forwarded_error = ? WHERE id = ?",
            (status, error, report_id),
        )
        updated = db.execute(
            "SELECT * FROM malpractice_reports WHERE id = ?",
            (report_id,),
        ).fetchone()

    return dict(updated)


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
