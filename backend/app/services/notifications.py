import sqlite3


def notify_user(
    db: sqlite3.Connection,
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
    db: sqlite3.Connection,
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
