from pathlib import Path
from uuid import uuid4

from psycopg.errors import UniqueViolation
from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from fastapi.responses import FileResponse

from app.database import BASE_DIR, get_connection
from app.dependencies.auth import CurrentUser, get_current_user, get_optional_current_user
from app.schemas import AuthResponse, UserCreate, UserLogin, UserOut
from app.services.security import hash_password, issue_token, verify_password

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/signup", response_model=AuthResponse, status_code=status.HTTP_201_CREATED)
def signup(
    payload: UserCreate,
    current_user: CurrentUser | None = Depends(get_optional_current_user),
) -> AuthResponse:
    username = payload.username.strip()
    password = payload.password.strip()

    try:
        with get_connection() as db:
            existing_user_count = db.execute(
                "SELECT COUNT(*) AS count FROM users"
            ).fetchone()["count"]
            if existing_user_count:
                if current_user is None:
                    raise HTTPException(
                        status_code=status.HTTP_401_UNAUTHORIZED,
                        detail="Only an authenticated admin can create additional accounts.",
                        headers={"WWW-Authenticate": "Bearer"},
                    )
                if current_user.role != "admin":
                    raise HTTPException(
                        status_code=status.HTTP_403_FORBIDDEN,
                        detail="Only an admin can create additional accounts.",
                    )
            elif payload.role != "admin":
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="The first account must be an admin account.",
                )

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
                    """
                    INSERT INTO allocation_invigilators (username) VALUES (?)
                    ON CONFLICT (username) DO NOTHING
                    """,
                    (username,),
                )
    except UniqueViolation:
        raise HTTPException(status_code=409, detail="Username already exists.")

    return AuthResponse(
        user=UserOut(
            id=user_id,
            username=username,
            role=payload.role,
            profile_image_path=None,
        ),
        token=issue_token(user_id=user_id, username=username, role=payload.role),
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
        token=issue_token(
            user_id=user["id"],
            username=user["username"],
            role=user["role"],
        ),
    )


@router.post("/users/{user_id}/profile-picture", response_model=UserOut)
async def upload_profile_picture(
    user_id: int,
    profile_picture: UploadFile = File(...),
    current_user: CurrentUser = Depends(get_current_user),
) -> UserOut:
    if current_user.id != user_id and current_user.role != "admin":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You can only update your own profile picture.",
        )
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
def get_profile_picture(
    user_id: int,
    _: CurrentUser = Depends(get_current_user),
) -> FileResponse:
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
