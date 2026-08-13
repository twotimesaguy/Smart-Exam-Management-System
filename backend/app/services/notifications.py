from typing import Any


def notify_user(
    db: Any,
    *,
    username: str,
    title: str,
    message: str,
) -> None:
    db.execute(
        """
        INSERT INTO notifications (recipient_username, title, message)
        VALUES (?, ?, ?)
        """,
        (username.strip(), title, message),
    )


def notify_role(
    db: Any,
    *,
    role: str,
    title: str,
    message: str,
) -> None:
    db.execute(
        """
        INSERT INTO notifications (recipient_role, title, message)
        VALUES (?, ?, ?)
        """,
        (role, title, message),
    )
