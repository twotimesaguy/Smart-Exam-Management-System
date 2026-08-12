from pathlib import Path
from datetime import datetime

from openpyxl import Workbook
from openpyxl.styles import Alignment, Font, PatternFill


def build_timetable_workbook(timetable: dict, entries: list[dict]) -> Path:
    export_dir = Path(__file__).resolve().parents[2] / "exports"
    export_dir.mkdir(parents=True, exist_ok=True)
    path = export_dir / f"timetable_{timetable['id']}.xlsx"

    workbook = Workbook()
    sheet = workbook.active
    sheet.title = "Exam Timetable"

    sheet.append([timetable["title"]])
    sheet.append([f"Exam Period: {timetable['exam_period']}"])
    sheet.append([f"Duration: {_duration_label(entries)}"])
    sheet.append([])

    for row in range(1, 4):
        sheet.merge_cells(start_row=row, start_column=1, end_row=row, end_column=8)
        cell = sheet.cell(row=row, column=1)
        cell.alignment = Alignment(horizontal="center", vertical="center")

    sheet["A1"].font = Font(bold=True, size=16)
    sheet["A2"].font = Font(bold=True, size=12)
    sheet["A3"].font = Font(bold=True, size=12)

    headers = [
        "Course Code",
        "Course Title",
        "Date",
        "Start",
        "End",
        "Venue",
        "Level",
        "Invigilator",
    ]
    sheet.append(headers)

    header_fill = PatternFill("solid", fgColor="0F766E")
    for cell in sheet[5]:
        cell.font = Font(color="FFFFFF", bold=True)
        cell.fill = header_fill
        cell.alignment = Alignment(horizontal="center", vertical="center")

    for entry in entries:
        sheet.append(
            [
                entry["course_code"],
                entry["course_title"],
                entry["exam_date"],
                entry["start_time"],
                entry["end_time"],
                entry["venue"],
                entry["student_level"],
                entry["invigilator_username"],
            ]
        )

    for row in sheet.iter_rows(min_row=6, max_row=sheet.max_row):
        for cell in row:
            cell.alignment = Alignment(horizontal="center", vertical="center")
        row[1].alignment = Alignment(horizontal="left", vertical="center")

    widths = [16, 34, 14, 12, 12, 22, 12, 22]
    for index, width in enumerate(widths, start=1):
        sheet.column_dimensions[chr(64 + index)].width = width

    workbook.save(path)
    return path


def _duration_label(entries: list[dict]) -> str:
    durations = {
        _duration_minutes(entry["start_time"], entry["end_time"])
        for entry in entries
        if entry.get("start_time") and entry.get("end_time")
    }
    if len(durations) != 1:
        return "Varies"

    minutes = durations.pop()
    hours = minutes // 60
    remaining_minutes = minutes % 60
    if hours and remaining_minutes:
        return f"{hours} hours {remaining_minutes} minutes"
    if hours:
        return f"{hours} hours"
    return f"{remaining_minutes} minutes"


def _duration_minutes(start_time: str, end_time: str) -> int:
    start = datetime.strptime(str(start_time)[:5], "%H:%M")
    end = datetime.strptime(str(end_time)[:5], "%H:%M")
    return int((end - start).total_seconds() // 60)
