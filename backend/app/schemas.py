from typing import Any, Literal

from pydantic import BaseModel, Field, field_validator


class UserCreate(BaseModel):
    username: str = Field(min_length=2)
    password: str = Field(min_length=4)
    role: str = Field(pattern="^(admin|invigilator|disciplinary_officer)$")

    @field_validator("username")
    @classmethod
    def username_must_include_a_letter(cls, value: str) -> str:
        if not any(character.isalpha() for character in value):
            raise ValueError("Username must include at least one letter.")
        return value


class UserLogin(BaseModel):
    username: str
    password: str


class UserOut(BaseModel):
    id: int
    username: str
    role: str
    profile_image_path: str | None = None


class AuthResponse(BaseModel):
    user: UserOut
    token: str


class StudentOut(BaseModel):
    student_id: str
    full_name: str
    programme: str
    level: str
    registered_at: str


class CourseInput(BaseModel):
    course_code: str
    course_title: str
    student_level: str
    student_count: int = Field(ge=1)
    duration_minutes: int = Field(default=120, ge=30)


class VenueInput(BaseModel):
    name: str
    capacity: int = Field(ge=1)


class TimetableRequest(BaseModel):
    title: str
    exam_period: str
    exam_dates: list[str]
    start_times: list[str] = ["09:00", "13:00"]
    courses: list[CourseInput]
    venues: list[VenueInput]
    invigilators: list[str]
    course_lecturers: dict[str, str] = Field(default_factory=dict)


class TimetableEntryOut(BaseModel):
    id: int
    course_code: str
    course_title: str
    exam_date: str
    start_time: str
    end_time: str
    venue: str
    student_level: str
    student_count: int
    invigilator_username: str


class TimetableOut(BaseModel):
    id: int
    title: str
    exam_period: str
    entries: list[TimetableEntryOut]
    version: int = 1
    last_updated: str = ""


class AiTimetableEditRequest(BaseModel):
    prompt: str = Field(min_length=3, max_length=4000)


class AiTimetableChange(BaseModel):
    """A proposed change only; the server remains responsible for all writes."""

    operation: Literal["update", "create"] = "update"
    exam_id: int | None = None
    field: str | None = None
    old: Any | None = None
    new: Any | None = None
    values: dict[str, Any] = Field(default_factory=dict)


class AiTimetableEditResult(BaseModel):
    applied: list[dict[str, Any]] = Field(default_factory=list)
    rejected: list[dict[str, Any]] = Field(default_factory=list)
    unresolved: list[str] = Field(default_factory=list)
    version: int | None = None
    last_updated: str | None = None


class AttendanceCreate(BaseModel):
    student_id: str
    course_title: str
    course_code: str
    venue: str
    recorded_by: str
    confidence: float | None = None


class AttendanceOut(BaseModel):
    id: int
    student_id: str
    full_name: str
    course_title: str
    course_code: str
    venue: str
    recorded_by: str
    confidence: float | None
    exam_date: str
    recorded_at: str


class RecognizedStudentOut(BaseModel):
    student_id: str
    full_name: str
    programme: str
    level: str
    confidence: float
    exam_scheduled_today: bool
    message: str
    course_title: str | None = None
    course_code: str | None = None
    venue: str | None = None
    exam_date: str | None = None
    start_time: str | None = None
    end_time: str | None = None


class AssignmentStatusUpdate(BaseModel):
    status: str = Field(pattern="^(pending|accepted|in_progress|completed)$")


class MalpracticeCreate(BaseModel):
    student_id: str
    student_level: str
    course_title: str
    course_code: str
    venue: str
    invigilator_name: str
    chief_invigilator_name: str
    chief_invigilator_approved: bool
    incident_description: str
    student_statement: str


class MalpracticeStatusUpdate(BaseModel):
    case_status: str = Field(pattern="^(pending|under_review|resolved|dismissed)$")
    resolution_notes: str = ""
    handled_by: str = Field(min_length=1)
