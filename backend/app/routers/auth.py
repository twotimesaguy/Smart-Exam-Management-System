import sqlite3
from pathlib import Path
from uuid import uuid4

from fastapi import APIRouter, File, HTTPException, UploadFile, status
from fastapi.responses import FileResponse

from app.database import BASE_DIR, get_connection
from app.schemas import AuthResponse, UserCreate, UserLogin, UserOut
from app.services.security import hash_password, issue_token, verify_password

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/signup", response_model=AuthResponse, status_code=status.HTTP_201_CREATED)
def signup(payload: UserCreate) -> AuthResponse:
    username = payload.username.strip()
    password = payload.password.strip()

    try:
        with get_connection() as db:
            existing_user = db.execute(
                "SELECT id FROM users WHERE lower(username) = lower(?)",
                (username,),
            ).fetchone()
            if existing_user is not None:
                raise HTTPException(
                    status_code=409,
                    detail="Username already exists.",
                )

            row = db.execute(
                """
                INSERT INTO users (username, password_hash, role)
                VALUES (?, ?, ?)
                RETURNING id
                """,
                (username, hash_password(password), payload.role),
            ).fetchone()
            user_id = row["id"]

            if payload.role == "invigilator":
                db.execute(
                    "INSERT OR IGNORE INTO allocation_invigilators (username) VALUES (?)",
                    (username,),
                )
    except sqlite3.IntegrityError:
        raise HTTPException(status_code=409, detail="Username already exists.")

    return AuthResponse(
        user=UserOut(
            id=user_id,
            username=username,
            role=payload.role,
            profile_image_path=None,
        ),
        token=issue_token(),
    )


@router.post("/login", response_model=AuthResponse)
def login(payload: UserLogin) -> AuthResponse:
    username = payload.username.strip()
    password = payload.password.strip()

    with get_connection() as db:
        user = db.execute(
            """
            SELECT id, username, password_hash, role, profile_image_path
            FROM users
            WHERE lower(username) = lower(?)
            ORDER BY CASE WHEN username = ? THEN 0 ELSE 1 END, id DESC
            LIMIT 1
            """,
            (username, username),
        ).fetchone()

    if user is None or not verify_password(password, user["password_hash"]):
        raise HTTPException(status_code=401, detail="Invalid username or password.")

    return AuthResponse(
        user=UserOut(
            id=user["id"],
            username=user["username"],
            role=user["role"],
            profile_image_path=user["profile_image_path"],
        ),
        token=issue_token(),
    )


@router.post("/users/{user_id}/profile-picture", response_model=UserOut)
async def upload_profile_picture(
    user_id: int,
    profile_picture: UploadFile = File(...),
) -> UserOut:
    extension = Path(profile_picture.filename or "profile.jpg").suffix or ".jpg"
    image_dir = BASE_DIR / "data" / "profile_pictures"
    image_dir.mkdir(parents=True, exist_ok=True)
    image_path = image_dir / f"user_{user_id}_{uuid4().hex}{extension}"
    image_path.write_bytes(await profile_picture.read())

    with get_connection() as db:
        user = db.execute(
            """
            UPDATE users
            SET profile_image_path = ?
            WHERE id = ?
            RETURNING id, username, role, profile_image_path
            """,
            (str(image_path), user_id),
        ).fetchone()

    if user is None:
        raise HTTPException(status_code=404, detail="User not found.")

    return UserOut(**dict(user))


@router.get("/users/{user_id}/profile-picture")
def get_profile_picture(user_id: int) -> FileResponse:
    with get_connection() as db:
        user = db.execute(
            "SELECT profile_image_path FROM users WHERE id = ?",
            (user_id,),
        ).fetchone()

    if user is None:
        raise HTTPException(status_code=404, detail="User not found.")

    image_path = user["profile_image_path"]
    if not image_path:
        raise HTTPException(status_code=404, detail="Profile picture not found.")

    path = Path(image_path)
    if not path.exists() or not path.is_file():
        raise HTTPException(status_code=404, detail="Profile picture file not found.")

    return FileResponse(path)
