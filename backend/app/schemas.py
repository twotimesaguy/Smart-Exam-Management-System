from pydantic import BaseModel, Field


class UserCreate(BaseModel):
    username: str = Field(min_length=2)
    password: str = Field(min_length=4)
    role: str = Field(pattern="^(admin|invigilator|disciplinary_officer)$")


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
    recorded_at: str


class RecognizedStudentOut(BaseModel):
    student_id: str
    full_name: str
    programme: str
    level: str
    confidence: float
    course_title: str
    course_code: str
    venue: str
    exam_date: str
    start_time: str
    end_time: str


class AssignmentStatusUpdate(BaseModel):
    status: str = Field(pattern="^(pending|accepted|in_progress|completed)$")


class MalpracticeCreate(BaseModel):
    student_id: str
    student_level: str
    course_title: str
    course_code: str
    venue: str
    invigilator_name: str
    incident_description: str
    student_statement: str


class MalpracticeStatusUpdate(BaseModel):
    case_status: str = Field(pattern="^(pending|under_review|resolved|dismissed)$")
    resolution_notes: str = ""
    handled_by: str = Field(min_length=1)
