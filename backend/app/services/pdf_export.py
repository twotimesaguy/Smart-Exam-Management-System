from pathlib import Path
import re

from reportlab.lib.enums import TA_CENTER
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4, landscape
from reportlab.lib.styles import getSampleStyleSheet
from reportlab.platypus import Image as ReportLabImage
from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle
from PIL import Image as PillowImage
from PIL import ImageOps

from app.database import BASE_DIR


def build_students_pdf(students: list[dict]) -> Path:
    export_dir = BASE_DIR / "exports"
    export_dir.mkdir(parents=True, exist_ok=True)
    path = export_dir / "registered_students.pdf"

    data = [["Student ID", "Name", "Programme", "Level", "Registered At"]]
    for student in students:
        data.append(
            [
                student["student_id"],
                student["full_name"],
                student["programme"],
                student["level"],
                student["registered_at"],
            ]
        )

    return _build_pdf(
        path=path,
        title="Registered Students",
        data=data,
        column_widths=[72, 150, 120, 58, 120],
    )


def build_attendance_pdf(
    records: list[dict],
    *,
    course_code: str,
    exam_date: str,
    course_title: str | None = None,
) -> Path:
    export_dir = BASE_DIR / "exports"
    export_dir.mkdir(parents=True, exist_ok=True)
    suffix = "_".join(
        (_safe_filename_part(course_code), _safe_filename_part(exam_date))
    )
    path = export_dir / f"attendance_{suffix}.pdf"

    resolved_course_title = (course_title or "").strip()
    if not resolved_course_title and records:
        resolved_course_title = str(records[0].get("course_title") or "").strip()

    lecturer_names = sorted(
        {
            str(record.get("recorded_by") or "").strip()
            for record in records
            if str(record.get("recorded_by") or "").strip()
        }
    )
    lecturer_name = ", ".join(lecturer_names) or "Not available"
    title = "ATTENDANCE LIST"
    subtitle = (
        f"Course Title: {resolved_course_title or 'Not available'}<br/>"
        f"Course Code: {course_code}<br/>"
        f"Exam Date: {exam_date}<br/>"
        f"Course Lecturer: {lecturer_name}"
    )

    data = [
        [
            "Photo",
            "Student ID",
            "Name",
            "Venue",
            "Scanned At",
            "Match Confidence",
        ]
    ]
    for record in records:
        data.append(
            [
                _student_image(record.get("face_image_path")),
                record["student_id"],
                record["full_name"],
                record["venue"],
                record["recorded_at"],
                "" if record["confidence"] is None else f"{record['confidence']:.2f}",
            ]
        )

    return _build_pdf(
        path=path,
        title=title,
        subtitle=subtitle,
        data=data,
        column_widths=[80, 82, 155, 105, 128, 95],
        page_size=landscape(A4),
    )


def build_malpractice_pdf(reports: list[dict]) -> Path:
    export_dir = BASE_DIR / "exports"
    export_dir.mkdir(parents=True, exist_ok=True)
    path = export_dir / "malpractice_cases.pdf"

    data = [
        [
            "Case",
            "Student",
            "Course",
            "Venue",
            "Invigilator",
            "Status",
            "Resolution Notes",
            "Handled By",
            "Reported At",
        ]
    ]
    for report in reports:
        data.append(
            [
                str(report["id"]),
                report["student_id"],
                f"{report['course_title']} ({report['course_code']})",
                report["venue"],
                report["invigilator_name"],
                _status_label(report.get("case_status")),
                report.get("resolution_notes") or "",
                report.get("handled_by") or "",
                report["created_at"],
            ]
        )

    return _build_pdf(
        path=path,
        title="Malpractice Case Report",
        data=data,
        column_widths=[42, 70, 150, 72, 88, 70, 160, 82, 92],
        page_size=landscape(A4),
    )


def _build_pdf(
    *,
    path: Path,
    title: str,
    subtitle: str | None = None,
    data: list[list[str]],
    column_widths: list[int],
    page_size=A4,
) -> Path:
    document = SimpleDocTemplate(str(path), pagesize=page_size)
    styles = getSampleStyleSheet()
    styles["Heading2"].alignment = TA_CENTER
    if len(data) == 1:
        data.append(["No records found.", *[""] * (len(data[0]) - 1)])

    table = Table(data, colWidths=column_widths, repeatRows=1)
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#0F766E")),
                ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
                ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
                ("GRID", (0, 0), (-1, -1), 0.25, colors.grey),
                ("FONTSIZE", (0, 0), (-1, -1), 8),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("ALIGN", (0, 1), (0, -1), "CENTER"),
            ]
        )
    )
    content = [Paragraph(title, styles["Title"])]
    if subtitle:
        content.extend([Spacer(1, 4), Paragraph(subtitle, styles["Heading2"])])
    content.extend([Spacer(1, 16), table])
    document.build(content)
    return path


def _student_image(image_path: str | None) -> ReportLabImage | str:
    if not image_path:
        return ""

    path = Path(image_path)
    if not path.is_absolute():
        path = BASE_DIR.parent / path
    if not path.exists() or not path.is_file():
        return ""

    try:
        prepared_path, image_width, image_height = _prepare_student_image(path)
    except (OSError, ValueError):
        return ""
    display_width, display_height = _fit_size(
        image_width,
        image_height,
        max_width=76,
        max_height=92,
    )
    return ReportLabImage(
        str(prepared_path),
        width=display_width,
        height=display_height,
    )


def _prepare_student_image(path: Path) -> tuple[Path, int, int]:
    image = PillowImage.open(path)
    image = ImageOps.exif_transpose(image)

    if image.width > image.height:
        image = image.rotate(-90, expand=True)

    target_width = 1200
    target_height = 1500
    image.thumbnail((target_width, target_height), PillowImage.Resampling.LANCZOS)

    export_dir = BASE_DIR / "exports" / "attendance_images"
    export_dir.mkdir(parents=True, exist_ok=True)
    prepared_path = export_dir / f"{path.stem}_pdf.png"
    image.convert("RGB").save(prepared_path, optimize=True)
    return prepared_path, image.width, image.height


def _fit_size(
    width: int,
    height: int,
    *,
    max_width: int,
    max_height: int,
) -> tuple[float, float]:
    scale = min(max_width / width, max_height / height)
    return width * scale, height * scale


def _safe_filename_part(value: str) -> str:
    return re.sub(r"[^A-Za-z0-9_.-]+", "_", value.strip()).strip("_") or "all"


def _status_label(value: str | None) -> str:
    labels = {
        "pending": "Pending",
        "under_review": "Under Review",
        "resolved": "Resolved",
        "dismissed": "Dismissed",
    }
    return labels.get(value or "pending", "Pending")
