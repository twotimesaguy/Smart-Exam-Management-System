import unittest

from app.routers.allocation import _entries_relevant_to_prompt
from app.schemas import CourseInput, TimetableRequest, VenueInput
from app.services.timetable import generate_timetable_entries


class AllocationSchedulingTests(unittest.TestCase):
    def test_ai_match_prefers_named_course_titles_over_shared_words(self):
        entries = [
            {
                "id": index,
                "course_code": f"ENG{index}",
                "course_title": f"General Engineering Topic {index}",
                "venue": "AR1",
                "invigilator_username": "Admin",
            }
            for index in range(260)
        ]
        entries.extend(
            [
                {
                    "id": 261,
                    "course_code": "ISD301",
                    "course_title": "Irrigation System Design",
                    "venue": "AR1",
                    "invigilator_username": "Admin",
                },
                {
                    "id": 262,
                    "course_code": "GEO211",
                    "course_title": "Geotechnical Engineering",
                    "venue": "AR2",
                    "invigilator_username": "Admin",
                },
            ]
        )

        matches = _entries_relevant_to_prompt(
            entries,
            "Exchange Irrigation System Design Friday morning with "
            "Geotechnical Engineering Friday afternoon.",
        )

        self.assertEqual([261, 262], [entry["id"] for entry in matches])

    def test_room_batches_for_one_course_stay_in_one_session(self):
        request = TimetableRequest(
            title="Test",
            exam_period="2026-08-28",
            exam_dates=["2026-08-28"],
            start_times=["09:00", "13:00"],
            courses=[
                CourseInput(
                    course_code="ISD301",
                    course_title="Irrigation System Design",
                    student_level="300",
                    student_count=24,
                    duration_minutes=120,
                )
            ],
            venues=[VenueInput(name="AR1", capacity=15), VenueInput(name="AR2", capacity=10)],
            invigilators=["Invigilator A", "Invigilator B"],
        )

        entries = generate_timetable_entries(request)

        self.assertEqual(24, sum(entry.student_count for entry in entries))
        self.assertEqual(1, len({(entry.exam_date, entry.start_time) for entry in entries}))


if __name__ == "__main__":
    unittest.main()
