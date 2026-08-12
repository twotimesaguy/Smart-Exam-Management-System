import os
import sqlite3
from contextlib import contextmanager
from datetime import date
from pathlib import Path
from typing import Iterator

from dotenv import load_dotenv

load_dotenv(Path(__file__).resolve().parents[1] / ".env")

BASE_DIR = Path(__file__).resolve().parents[1]
configured_database_path = Path(
    os.getenv("DATABASE_PATH", BASE_DIR / "data" / "exam_system.db")
)
DATABASE_PATH = (
    configured_database_path
    if configured_database_path.is_absolute()
    else BASE_DIR / configured_database_path
)


@contextmanager
def get_connection() -> Iterator[sqlite3.Connection]:
    DATABASE_PATH.parent.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(DATABASE_PATH)
    connection.row_factory = sqlite3.Row
    connection.execute("PRAGMA foreign_keys = ON")
    try:
        yield connection
        connection.commit()
    except Exception:
        connection.rollback()
        raise
    finally:
        connection.close()


def init_db() -> None:
    with get_connection() as db:
        db.executescript(
            """
            CREATE TABLE IF NOT EXISTS users (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                username TEXT NOT NULL UNIQUE,
                password_hash TEXT NOT NULL,
                role TEXT NOT NULL CHECK(role IN ('admin', 'invigilator', 'disciplinary_officer')),
                profile_image_path TEXT,
                created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
            );

            CREATE TABLE IF NOT EXISTS students (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                student_id TEXT NOT NULL UNIQUE,
                full_name TEXT NOT NULL,
                programme TEXT NOT NULL,
                level TEXT NOT NULL,
                face_image_path TEXT,
                face_embedding TEXT,
                registered_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
            );

            CREATE TABLE IF NOT EXISTS timetables (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                title TEXT NOT NULL,
                exam_period TEXT NOT NULL,
                generated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
            );

            CREATE TABLE IF NOT EXISTS timetable_entries (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timetable_id INTEGER NOT NULL REFERENCES timetables(id) ON DELETE CASCADE,
                course_code TEXT NOT NULL,
                course_title TEXT NOT NULL,
                exam_date TEXT NOT NULL,
                start_time TEXT NOT NULL,
                end_time TEXT NOT NULL,
                venue TEXT NOT NULL,
                student_level TEXT NOT NULL,
                student_count INTEGER NOT NULL CHECK(student_count > 0),
                invigilator_username TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS assignments (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timetable_entry_id INTEGER NOT NULL REFERENCES timetable_entries(id) ON DELETE CASCADE,
                invigilator_username TEXT NOT NULL,
                status TEXT NOT NULL DEFAULT 'pending'
                    CHECK(status IN ('pending', 'accepted', 'in_progress', 'completed'))
            );

            CREATE TABLE IF NOT EXISTS allocation_courses (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                course_code TEXT NOT NULL UNIQUE,
                course_title TEXT NOT NULL,
                student_level TEXT NOT NULL,
                student_count INTEGER NOT NULL CHECK(student_count > 0),
                duration_minutes INTEGER NOT NULL CHECK(duration_minutes > 0)
            );

            CREATE TABLE IF NOT EXISTS allocation_venues (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL UNIQUE,
                capacity INTEGER NOT NULL CHECK(capacity > 0)
            );

            CREATE TABLE IF NOT EXISTS allocation_invigilators (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                username TEXT NOT NULL UNIQUE
            );

            CREATE TABLE IF NOT EXISTS allocation_settings (
                id INTEGER PRIMARY KEY CHECK(id = 1),
                title TEXT NOT NULL,
                exam_period TEXT NOT NULL,
                exam_start_date TEXT NOT NULL,
                exam_end_date TEXT NOT NULL,
                start_times TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS attendance_records (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                student_id TEXT NOT NULL,
                full_name TEXT NOT NULL,
                course_title TEXT NOT NULL DEFAULT '',
                course_code TEXT NOT NULL,
                venue TEXT NOT NULL,
                recorded_by TEXT NOT NULL,
                confidence REAL,
                recorded_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
            );

            CREATE TABLE IF NOT EXISTS malpractice_reports (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                student_id TEXT NOT NULL,
                student_level TEXT NOT NULL,
                course_title TEXT NOT NULL,
                course_code TEXT NOT NULL,
                venue TEXT NOT NULL,
                invigilator_name TEXT NOT NULL,
                incident_description TEXT NOT NULL,
                student_statement TEXT NOT NULL,
                student_face_image_path TEXT,
                foreign_material_image_path TEXT,
                forwarded_status TEXT NOT NULL DEFAULT 'pending',
                forwarded_error TEXT,
                case_status TEXT NOT NULL DEFAULT 'pending'
                    CHECK(case_status IN ('pending', 'under_review', 'resolved', 'dismissed')),
                resolution_notes TEXT NOT NULL DEFAULT '',
                handled_by TEXT,
                handled_at TEXT,
                created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
            );

            CREATE TABLE IF NOT EXISTS notifications (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                recipient_username TEXT,
                recipient_role TEXT CHECK(
                    recipient_role IN ('admin', 'invigilator', 'disciplinary_officer')
                ),
                title TEXT NOT NULL,
                message TEXT NOT NULL,
                is_read INTEGER NOT NULL DEFAULT 0 CHECK(is_read IN (0, 1)),
                created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                CHECK(recipient_username IS NOT NULL OR recipient_role IS NOT NULL)
            );

            CREATE INDEX IF NOT EXISTS idx_attendance_course_code
                ON attendance_records(course_code);
            CREATE INDEX IF NOT EXISTS idx_assignments_invigilator
                ON assignments(invigilator_username);
            CREATE INDEX IF NOT EXISTS idx_notifications_recipient_username
                ON notifications(recipient_username);
            CREATE INDEX IF NOT EXISTS idx_notifications_recipient_role
                ON notifications(recipient_role);
            """
        )
        _add_column_if_missing(db, "users", "profile_image_path", "TEXT")
        _ensure_user_roles_include_disciplinary_officer(db)
        _add_column_if_missing(
            db, "attendance_records", "course_title", "TEXT NOT NULL DEFAULT ''"
        )
        _add_column_if_missing(
            db,
            "malpractice_reports",
            "case_status",
            "TEXT NOT NULL DEFAULT 'pending'",
        )
        _add_column_if_missing(
            db,
            "malpractice_reports",
            "resolution_notes",
            "TEXT NOT NULL DEFAULT ''",
        )
        _add_column_if_missing(db, "malpractice_reports", "handled_by", "TEXT")
        _add_column_if_missing(db, "malpractice_reports", "handled_at", "TEXT")
        _seed_allocation_setup(db)
        _sync_invigilator_users_to_allocation_pool(db)
        clear_expired_timetables(db)


def _add_column_if_missing(
    db: sqlite3.Connection,
    table_name: str,
    column_name: str,
    column_definition: str,
) -> None:
    columns = {
        row["name"]
        for row in db.execute(f"PRAGMA table_info({table_name})").fetchall()
    }
    if column_name not in columns:
        db.execute(
            f"ALTER TABLE {table_name} ADD COLUMN {column_name} {column_definition}"
        )


def _ensure_user_roles_include_disciplinary_officer(db: sqlite3.Connection) -> None:
    table_sql = db.execute(
        "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'users'"
    ).fetchone()["sql"]
    if "disciplinary_officer" in table_sql:
        return

    db.executescript(
        """
        CREATE TABLE users_new (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT NOT NULL UNIQUE,
            password_hash TEXT NOT NULL,
            role TEXT NOT NULL CHECK(role IN ('admin', 'invigilator', 'disciplinary_officer')),
            profile_image_path TEXT,
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        );

        INSERT INTO users_new
            (id, username, password_hash, role, profile_image_path, created_at)
        SELECT id, username, password_hash, role, profile_image_path, created_at
        FROM users;

        DROP TABLE users;
        ALTER TABLE users_new RENAME TO users;
        """
    )


def _seed_allocation_setup(db: sqlite3.Connection) -> None:
    course_count = db.execute("SELECT COUNT(*) AS count FROM allocation_courses").fetchone()[
        "count"
    ]
    if course_count == 0:
        db.executemany(
            """
            INSERT INTO allocation_courses
                (course_code, course_title, student_level, student_count, duration_minutes)
            VALUES (?, ?, ?, ?, ?)
            """,
            [
                ("COS 102", "Communication Skills", "100", 120, 150),
                ("CS107", "Discrete Maths", "100", 120, 150),
                ("CS105", "Intro to Programming", "100", 120, 150),
                ("FR101", "French", "100", 120, 150),
                ("AFS 109", "African Studies", "100", 120, 150),
            ],
        )

    venue_count = db.execute("SELECT COUNT(*) AS count FROM allocation_venues").fetchone()[
        "count"
    ]
    if venue_count == 0:
        db.executemany(
            "INSERT INTO allocation_venues (name, capacity) VALUES (?, ?)",
            [
                ("V11", 300),
                ("V23", 300),
                ("Basement", 300),
                ("Octagon Main Lab", 300),
                ("Wing Lab", 300),
            ],
        )

    invigilator_count = db.execute(
        "SELECT COUNT(*) AS count FROM allocation_invigilators"
    ).fetchone()["count"]
    if invigilator_count == 0:
        db.executemany(
            "INSERT INTO allocation_invigilators (username) VALUES (?)",
            [
                ("Dr. Appiah",),
                ("Mr. Victor Gbedawo",),
                ("Mr. Robert Agboyi",),
                ("Dr. Anthony Sackey",),
                ("Mr. Carlos Ankora",),
                ("Mr. Bill Frimpong",),
                ("Mr. Adolf",),
            ],
        )

    settings_count = db.execute(
        "SELECT COUNT(*) AS count FROM allocation_settings"
    ).fetchone()["count"]
    if settings_count == 0:
        db.execute(
            """
            INSERT INTO allocation_settings
                (id, title, exam_period, exam_start_date, exam_end_date, start_times)
            VALUES (1, ?, ?, ?, ?, ?)
            """,
            (
                "End of Semester Exams",
                "August 15 - September 20, 2026",
                "2026-08-15",
                "2026-09-20",
                "09:00,13:00",
            ),
        )
    else:
        db.execute(
            """
            UPDATE allocation_settings
            SET title = ?, exam_period = ?, exam_start_date = ?, exam_end_date = ?, start_times = ?
            WHERE id = 1
            """,
            (
                "End of Semester Exams",
                "August 15 - September 20, 2026",
                "2026-08-15",
                "2026-09-20",
                "09:00,13:00",
            ),
        )


def _sync_invigilator_users_to_allocation_pool(db: sqlite3.Connection) -> None:
    db.execute(
        """
        INSERT OR IGNORE INTO allocation_invigilators (username)
        SELECT username
        FROM users
        WHERE role = 'invigilator'
        """
    )


def clear_expired_timetables(db: sqlite3.Connection | None = None) -> None:
    if db is None:
        with get_connection() as connection:
            clear_expired_timetables(connection)
        return

    settings = db.execute(
        "SELECT exam_end_date FROM allocation_settings WHERE id = 1"
    ).fetchone()
    if settings is None:
        return

    exam_end_date = date.fromisoformat(settings["exam_end_date"])
    if date.today() > exam_end_date:
        db.execute("DELETE FROM timetables")
