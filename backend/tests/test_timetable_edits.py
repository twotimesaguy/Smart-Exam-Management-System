import unittest

from app.schemas import AiTimetableChange, TimetableEntryOut, VenueInput
from app.services.timetable import validate_live_timetable_entries
from app.services.timetable_edits import plan_ai_timetable_edits


def _entry(
    entry_id: int,
    *,
    course_code: str,
    start_time: str,
    end_time: str,
    venue: str = "AR18",
) -> dict:
    return {
        "id": entry_id,
        "course_code": course_code,
        "course_title": course_code,
        "exam_date": "2026-08-16",
        "start_time": start_time,
        "end_time": end_time,
        "venue": venue,
        "student_level": f"Level {entry_id}",
        "student_count": 1,
        "invigilator_username": f"Invigilator {entry_id}",
    }


class TimetableEditValidationTests(unittest.TestCase):
    def test_model_supplied_old_value_is_not_a_concurrency_token(self):
        entries = [_entry(19363, course_code="MKT205", start_time="12:00", end_time="14:00")]
        final_entries, applied, rejected = plan_ai_timetable_edits(
            changes=[
                AiTimetableChange(
                    exam_id=19363,
                    field="venue",
                    old="a value the model reformatted incorrectly",
                    new="AR19",
                )
            ],
            entries=entries,
            venues=[VenueInput(name="AR18", capacity=10), VenueInput(name="AR19", capacity=10)],
            invigilators=["Invigilator 19363"],
            course_catalogue={},
        )

        self.assertEqual([], rejected)
        self.assertEqual(1, len(applied))
        self.assertEqual("AR19", final_entries[0]["venue"])

    def test_ar18_schedule_on_august_16_is_not_a_conflict(self):
        entries = [
            _entry(19382, course_code="AED218", start_time="07:00", end_time="09:00"),
            _entry(19363, course_code="MKT205", start_time="12:00", end_time="14:00"),
        ]

        validate_live_timetable_entries(
            [TimetableEntryOut(**entry) for entry in entries],
            venues=[VenueInput(name="AR18", capacity=10)],
            invigilators=["Invigilator 19382", "Invigilator 19363"],
        )

    def test_ar18_overlapping_times_are_rejected(self):
        entries = [
            _entry(19382, course_code="AED218", start_time="07:00", end_time="09:00"),
            _entry(19363, course_code="MKT205", start_time="08:00", end_time="10:00"),
        ]

        with self.assertRaisesRegex(ValueError, "AR18 is double-booked"):
            validate_live_timetable_entries(
                [TimetableEntryOut(**entry) for entry in entries],
                venues=[VenueInput(name="AR18", capacity=10)],
                invigilators=["Invigilator 19382", "Invigilator 19363"],
            )


if __name__ == "__main__":
    unittest.main()
