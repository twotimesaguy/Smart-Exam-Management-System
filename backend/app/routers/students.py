import logging
from pathlib import Path

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, status
from fastapi.responses import FileResponse

from app.database import BASE_DIR, get_connection
from app.dependencies.auth import CurrentUser, get_current_user, require_roles
from app.schemas import StudentOut
from app.services.face_recognition import face_service
from app.services.pdf_export import build_students_pdf

router = APIRouter(
    prefix="/students",
    tags=["students"],
    dependencies=[Depends(get_current_user)],
)
logger = logging.getLogger(__name__)


@router.post("", response_model=StudentOut, status_code=status.HTTP_201_CREATED)
async def create_student(
    student_id: str = Form(...),
    full_name: str = Form(...),
    programme: str = Form(...),
    level: str = Form(...),
    face_image: UploadFile = File(...),
    _: CurrentUser = Depends(require_roles("admin")),
) -> StudentOut:
    with get_connection() as db:
        existing = db.execute(
            "SELECT 1 FROM students WHERE student_id = ?",
            (student_id.strip(),),
        ).fetchone()
        if existing is not None:
            raise HTTPException(status_code=409, detail="Student ID already exists.")

    image_bytes = await face_image.read()
    try:
        embedding = face_service.embedding_from_bytes(image_bytes)
    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error))
    except Exception:
        logger.exception("Could not process the face image for student %s", student_id)
        raise HTTPException(
            status_code=422,
            detail=(
                "The face photo could not be processed. Capture a clear JPEG "
                "or PNG photo and try again."
            ),
        )

    image_path = _save_student_image(student_id, image_bytes, face_image.filename)

    with get_connection() as db:
        db.execute(
            """
            INSERT INTO students
                (student_id, full_name, programme, level, face_image_path, face_image_data, face_embedding)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (
                student_id.strip(),
                full_name.strip(),
                programme.strip(),
                level.strip(),
                str(image_path),
                image_bytes,
                face_service.serialize(embedding),
            ),
        )
        row = db.execute(
            """
            SELECT student_id, full_name, programme, level, registered_at
            FROM students
            WHERE student_id = ?
            """,
            (student_id.strip(),),
        ).fetchone()

    return StudentOut(**dict(row))


@router.get("", response_model=list[StudentOut])
def list_students(
    _: CurrentUser = Depends(require_roles("admin")),
) -> list[StudentOut]:
    with get_connection() as db:
        rows = db.execute(
            """
            SELECT student_id, full_name, programme, level, registered_at
            FROM students
            ORDER BY registered_at DESC
            """
        ).fetchall()
    return [StudentOut(**dict(row)) for row in rows]


@router.get("/export/pdf")
def export_students_pdf(
    _: CurrentUser = Depends(require_roles("admin")),
) -> FileResponse:
    with get_connection() as db:
        rows = db.execute(
            """
            SELECT student_id, full_name, programme, level, registered_at
            FROM students
            ORDER BY registered_at ASC
            """
        ).fetchall()

    path = build_students_pdf([dict(row) for row in rows])
    return FileResponse(path, media_type="application/pdf", filename=path.name)


def _save_student_image(student_id: str, image_bytes: bytes, filename: str | None) -> Path:
    extension = Path(filename or "face.jpg").suffix or ".jpg"
    image_dir = BASE_DIR / "data" / "student_faces"
    image_dir.mkdir(parents=True, exist_ok=True)
    path = image_dir / f"{student_id.strip()}{extension}"
    path.write_bytes(image_bytes)
    return path
