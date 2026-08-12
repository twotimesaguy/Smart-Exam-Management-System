from fastapi import APIRouter, HTTPException

from app.database import get_connection
from app.schemas import NotificationOut

router = APIRouter(prefix="/notifications", tags=["notifications"])


@router.get("", response_model=list[NotificationOut])
def list_notifications(username: str, role: str) -> list[NotificationOut]:
    with get_connection() as db:
        rows = db.execute(
            """
            SELECT id, title, message, is_read, created_at
            FROM notifications
            WHERE lower(COALESCE(recipient_username, '')) = lower(?)
               OR recipient_role = ?
            ORDER BY created_at DESC, id DESC
            LIMIT 50
            """,
            (username.strip(), role),
        ).fetchall()

    return [
        NotificationOut(
            id=row["id"],
            title=row["title"],
            message=row["message"],
            is_read=bool(row["is_read"]),
            created_at=row["created_at"],
        )
        for row in rows
    ]


@router.patch("/{notification_id}/read")
def mark_notification_read(notification_id: int) -> dict[str, int | bool]:
    with get_connection() as db:
        cursor = db.execute(
            "UPDATE notifications SET is_read = 1 WHERE id = ?",
            (notification_id,),
        )
        if cursor.rowcount == 0:
            raise HTTPException(status_code=404, detail="Notification not found.")

    return {"id": notification_id, "is_read": True}
