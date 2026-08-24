import csv
import re
from datetime import datetime, timedelta
from random import SystemRandom

from app.schemas import CourseInput, TimetableEntryOut, TimetableRequest, VenueInput
_exam_day_start = "07:00"
_exam_day_end = "19:00"


def generate_wizard_timetable_entries(
    *,
    title: str,
    start_date: str,
    end_date: str,
    semester: str,
    time_slots: str,
    lecturers: str,
    venues: str,
    courses: str,
    programmes: str,
    course_lecturers: str,
    max_session_duration_minutes: int,
) -> list[TimetableEntryOut]:
    allowed_dates = _date_range(start_date, end_date)
    allowed_times = [item.strip() for item in time_slots.split(",") if item.strip()]
    if not allowed_dates:
        raise ValueError("Select a valid start and end date.")
    if not allowed_times:
        raise ValueError("Enter at least one time slot.")
    if not 30 <= max_session_duration_minutes <= 120:
        raise ValueError("An exam session must be between 30 and 120 minutes long.")

    request = _wizard_timetable_request(
        title=title,
        start_date=start_date,
        end_date=end_date,
        allowed_dates=allowed_dates,
        allowed_times=allowed_times,
        semester=semester,
        lecturers=lecturers,
        venues=venues,
        courses=courses,
        programmes=programmes,
        course_lecturers=course_lecturers,
        max_session_duration_minutes=max_session_duration_minutes,
    )
    scheduling_error: ValueError | None = None
    try:
        return generate_timetable_entries(request)
    except ValueError as caught_error:
        if "No conflict-free slot remains" not in str(caught_error):
            raise
        scheduling_error = caught_error

    # Use the administrator's selected sessions first. If the supplied data is
    # larger than those sessions can hold, safely add equally sized sessions in
    # the same exam-day window instead of abandoning the timetable.
    expanded_times = _expanded_time_slots(
        request.start_times, max_session_duration_minutes
    )
    if expanded_times == request.start_times:
        raise scheduling_error
    return generate_timetable_entries(
        request.model_copy(update={"start_times": expanded_times})
    )


def generate_timetable_entries(request: TimetableRequest) -> list[TimetableEntryOut]:
    if not request.exam_dates:
        raise ValueError("At least one exam date is required.")
    if not request.start_times:
        raise ValueError("At least one start time is required.")
    if not request.venues:
        raise ValueError("At least one venue is required.")
    if not request.invigilators:
        raise ValueError("At least one invigilator is required.")

    if not request.courses:
        raise ValueError("At least one course is required.")
    entries = _generate_local_timetable_entries(request)
    _validate_generated_entries(request, entries)
    return entries


def _date_range(start_date: str, end_date: str) -> list[str]:
    start = datetime.strptime(start_date, "%Y-%m-%d").date()
    end = datetime.strptime(end_date, "%Y-%m-%d").date()
    if end < start:
        return []
    dates = []
    current = start
    while current <= end:
        dates.append(current.isoformat())
        current += timedelta(days=1)
    return dates


def _expanded_time_slots(
    selected_times: list[str], max_session_duration_minutes: int
) -> list[str]:
    day_start = datetime.strptime(_exam_day_start, "%H:%M")
    day_end = datetime.strptime(_exam_day_end, "%H:%M")
    session_length = timedelta(minutes=max_session_duration_minutes)
    generated = []
    current = day_start
    while current + session_length <= day_end:
        generated.append(current.strftime("%H:%M"))
        current += session_length
    return sorted(set(selected_times).union(generated))


def _wizard_timetable_request(
    *,
    title: str,
    start_date: str,
    end_date: str,
    allowed_dates: list[str],
    allowed_times: list[str],
    semester: str,
    lecturers: str,
    venues: str,
    courses: str,
    programmes: str,
    course_lecturers: str,
    max_session_duration_minutes: int,
) -> TimetableRequest:
    parsed_course_lecturers = _parse_course_lecturers(course_lecturers)
    programme_catalogue = _parse_programme_catalogue(programmes)
    parsed_courses = _parse_courses(
        courses,
        semester,
        max_session_duration_minutes,
        _parse_programme_groups(course_lecturers, programme_catalogue),
    )
    parsed_venues = _parse_venues(venues)
    parsed_lecturers = _parse_lecturers(lecturers)
    for lecturer in parsed_course_lecturers.values():
        if lecturer.lower() not in {item.lower() for item in parsed_lecturers}:
            parsed_lecturers.append(lecturer)
    if not parsed_courses:
        raise ValueError("No courses could be read. Include a course code and title for each course.")
    if not parsed_venues:
        raise ValueError("No venues could be read. Include a venue name and capacity for each venue.")
    if not parsed_lecturers:
        raise ValueError("No lecturers could be read. Include one lecturer or invigilator per row.")

    return TimetableRequest(
        title=title,
        exam_period=f"{start_date} to {end_date}",
        exam_dates=allowed_dates,
        start_times=allowed_times,
        courses=parsed_courses,
        venues=parsed_venues,
        invigilators=parsed_lecturers,
        course_lecturers=parsed_course_lecturers,
    )


def _source_rows(text: str) -> list[list[str]]:
    rows = []
    for line in text.splitlines():
        value = line.strip()
        if not value or value.lower().startswith(("file:", "sheet:", "category:")):
            continue
        if "|" in value:
            cells = value.split("|")
        elif "\t" in value:
            cells = value.split("\t")
        elif "," in value:
            cells = next(csv.reader([value]))
        else:
            cells = [value]
        # Preserve empty cells so a value remains under the header it was
        # uploaded with. This is especially important for Excel rows that
        # contain optional leading columns such as an ID or serial number.
        rows.append([cell.strip() for cell in cells])
    return rows


def _normalise_label(value: str) -> str:
    return re.sub(r"[^a-z0-9]", "", value.lower())


def _column_index(headers: list[str], aliases: tuple[str, ...]) -> int | None:
    for index, header in enumerate(headers):
        normalised = _normalise_label(header)
        if any(alias in normalised for alias in aliases):
            return index
    return None


def _cell(cells: list[str], index: int | None) -> str:
    return cells[index].strip() if index is not None and index < len(cells) else ""


def _positive_number(value: str, default: int) -> int:
    match = re.search(r"\d[\d,]*", value)
    if match is None:
        return default
    return max(1, int(match.group().replace(",", "")))


def _course_code(value: str) -> str:
    match = re.search(r"\b([A-Za-z]{2,10}\s*-?\s*\d{2,5}[A-Za-z]?)\b", value)
    return re.sub(r"\s+", "", match.group(1)).upper() if match else ""


def _parse_courses(
    text: str,
    semester: str,
    default_duration: int,
    programme_groups: dict[str, str],
) -> list[CourseInput]:
    rows = _source_rows(text)
    header: list[str] | None = None
    records: list[CourseInput] = []
    seen_codes: set[str] = set()
    for cells in rows:
        if header is None and _column_index(
            cells, ("coursecode", "courseid", "code")
        ) is not None:
            header = cells
            continue
        code_index = _column_index(header or [], ("coursecode", "courseid", "code"))
        title_index = _column_index(header or [], ("coursetitle", "coursename", "title"))
        level_index = _column_index(header or [], ("studentlevel", "level", "year"))
        count_index = _column_index(header or [], ("studentcount", "numberofstudents", "enrol", "enroll", "students"))
        duration_index = _column_index(header or [], ("duration", "minutes"))
        source_code = _cell(cells, code_index)
        code = _course_code(source_code) or source_code.strip().upper()
        if not code:
            code = _course_code(" ".join(cells))
        if not code or code in seen_codes:
            continue
        title = _cell(cells, title_index)
        if not title:
            title = cells[1] if len(cells) > 1 else code
        level = programme_groups.get(code) or _cell(cells, level_index) or next(
            (cell for cell in cells if "level" in cell.lower() or "year" in cell.lower()),
            "",
        )
        if not level:
            level = _inferred_course_group(code) or semester
        count = _positive_number(_cell(cells, count_index), 1)
        if count_index is None and len(cells) > 3:
            count = _positive_number(cells[3], 1)
        duration = _positive_number(_cell(cells, duration_index), default_duration)
        duration = min(max(duration, 30), default_duration)
        records.append(
            CourseInput(
                course_code=code,
                course_title=title,
                student_level=level or semester,
                student_count=count,
                duration_minutes=duration,
            )
        )
        seen_codes.add(code)
    return records


def _exact_column_index(headers: list[str], labels: tuple[str, ...]) -> int | None:
    for index, header in enumerate(headers):
        if _normalise_label(header) in labels:
            return index
    return None


def _parse_programme_catalogue(text: str) -> dict[str, str]:
    """Read programme codes and display names from the programme export."""
    rows = _source_rows(text)
    header: list[str] | None = None
    programmes: dict[str, str] = {}
    for cells in rows:
        if header is None and (
            _exact_column_index(cells, ("programmecode", "programcode")) is not None
            and _exact_column_index(cells, ("programmename", "programname")) is not None
        ):
            header = cells
            continue
        code_index = _exact_column_index(header or [], ("programmecode", "programcode"))
        name_index = _exact_column_index(header or [], ("programmename", "programname"))
        code = _cell(cells, code_index)
        name = _cell(cells, name_index)
        if code and name:
            programmes[code.upper()] = name
    return programmes


def _parse_programme_groups(
    text: str, programme_catalogue: dict[str, str]
) -> dict[str, str]:
    """Read course-to-programme links from the course-lecturer export."""
    rows = _source_rows(text)
    header: list[str] | None = None
    groups: dict[str, str] = {}
    for cells in rows:
        if header is None and _exact_column_index(
            cells, ("coursecode", "courseid")
        ) is not None:
            header = cells
            continue
        course_index = _exact_column_index(header or [], ("coursecode", "courseid"))
        programme_code_index = _exact_column_index(
            header or [], ("programmecode", "programcode")
        )
        programme_name_index = _exact_column_index(
            header or [], ("programmename", "programname")
        )
        level_index = _exact_column_index(
            header or [], ("studentlevel", "level", "year")
        )
        code = _course_code(_cell(cells, course_index) or (cells[0] if cells else ""))
        programme_code = _cell(cells, programme_code_index)
        programme_name = _cell(cells, programme_name_index)
        if header is None and len(cells) > 1:
            programme_name = programme_name or cells[1]
        level = _cell(cells, level_index)
        if header is None and not level and len(cells) > 2:
            level = cells[2]
        programme = (
            programme_catalogue.get(programme_code.upper())
            or programme_name
            or programme_code
        )
        if code and programme:
            groups[code] = " ".join(value for value in (programme, level) if value)
    return groups


def _parse_course_lecturers(text: str) -> dict[str, str]:
    """Read optional course-to-lecturer rows for fixed course allocations."""
    rows = _source_rows(text)
    header: list[str] | None = None
    assignments: dict[str, str] = {}
    for cells in rows:
        if header is None and (
            _exact_column_index(cells, ("coursecode", "courseid")) is not None
            or _exact_column_index(
                cells, ("lecturer", "lecturername", "invigilator", "staffname")
            )
            is not None
        ):
            header = cells
            continue
        code_index = _exact_column_index(header or [], ("coursecode", "courseid"))
        lecturer_index = _exact_column_index(
            header or [], ("lecturer", "lecturername", "invigilator", "staffname")
        )
        code = _course_code(_cell(cells, code_index) or (cells[0] if cells else ""))
        lecturer = _cell(cells, lecturer_index)
        if not lecturer and lecturer_index is None and len(cells) > 1:
            lecturer = cells[1]
        if code and lecturer:
            assignments[code] = lecturer
    return assignments


def _inferred_course_group(course_code: str) -> str:
    """Derive a clash group for catalogue exports that omit programme/level."""
    match = re.fullmatch(r"([A-Z]+)(\d{3,4})[A-Z]?", course_code.upper())
    if match is None:
        # A catalogue code without a numeric level is independent of the other
        # courses, so do not put every such record into one artificial group.
        return course_code
    programme, number = match.groups()
    numeric_level = int(number)
    level = (numeric_level // 100) * 100
    return f"{programme} Level {level}"


def _parse_venues(text: str) -> list[VenueInput]:
    rows = _source_rows(text)
    header: list[str] | None = None
    venues: list[VenueInput] = []
    seen_names: set[str] = set()
    for cells in rows:
        if header is None and (
            _column_index(cells, ("venuename", "venue", "hall", "room", "location"))
            is not None
            or _column_index(cells, ("capacity", "students", "seats")) is not None
        ):
            header = cells
            continue
        name_index = _column_index(header or [], ("venuename", "venue", "hall", "room", "location"))
        capacity_index = _column_index(header or [], ("capacity", "students", "seats"))
        name = _cell(cells, name_index) or (cells[0] if cells else "")
        if not name or name.lower() in seen_names:
            continue
        capacity = _positive_number(_cell(cells, capacity_index), 1)
        if capacity_index is None and len(cells) > 1:
            capacity = _positive_number(cells[1], 1)
        venues.append(VenueInput(name=name, capacity=capacity))
        seen_names.add(name.lower())
    return venues


def _parse_lecturers(text: str) -> list[str]:
    rows = _source_rows(text)
    header: list[str] | None = None
    lecturers: list[str] = []
    seen: set[str] = set()
    for cells in rows:
        if header is None and _column_index(
            cells, ("lecturer", "invigilator", "username", "fullname", "staffname")
        ) is not None:
            header = cells
            continue
        name_index = _column_index(header or [], ("lecturer", "invigilator", "username", "fullname", "staffname", "name"))
        name = _cell(cells, name_index) or (cells[0] if cells else "")
        if not name or name.lower() in seen:
            continue
        lecturers.append(name)
        seen.add(name.lower())
    return lecturers


def _generate_local_timetable_entries(
    request: TimetableRequest,
) -> list[TimetableEntryOut]:
    venues = sorted(
        request.venues, key=lambda venue: _effective_capacity(venue), reverse=True
    )
    slots = [
        (exam_date, start_time, venue)
        for exam_date in request.exam_dates
        for start_time in request.start_times
        for venue in venues
    ]
    # The wizard supplies every date in the selected exam period.  Without
    # randomising the slots, the scheduler always chooses the first date and
    # fills it before looking at the rest of the range.
    SystemRandom().shuffle(slots)
    used_slots: set[tuple[str, str, str]] = set()
    entries: list[TimetableEntryOut] = []
    invigilator_dates: dict[str, set[str]] = {
        invigilator.lower(): set() for invigilator in request.invigilators
    }
    invigilator_slots: set[tuple[str, str, str]] = set()
    level_dates: dict[str, set[str]] = {}
    level_slot_courses: dict[tuple[str, str, str], str] = {}

    for course in (
        sorted(request.courses, key=lambda item: item.student_count, reverse=True)
    ):
        remaining_students = course.student_count
        eligible_invigilators = [
            request.course_lecturers[course.course_code]
        ] if course.course_code in request.course_lecturers else request.invigilators
        while remaining_students > 0:
            slot = _next_available_slot(
                course.course_code,
                course.student_level,
                course.duration_minutes,
                slots,
                used_slots,
                level_dates,
                level_slot_courses,
                eligible_invigilators,
                invigilator_dates,
                invigilator_slots,
            )
            if slot is None:
                raise ValueError(
                    "No conflict-free slot remains for all supplied courses in the selected "
                    "exam period. Add dates, time slots, venue capacity, or invigilators."
                )

            exam_date, start_time, venue = slot
            invigilator = _next_available_invigilator(
                eligible_invigilators,
                exam_date,
                start_time,
                invigilator_dates,
                invigilator_slots,
            )
            if invigilator is None:
                raise ValueError(
                    "No invigilator is available without consecutive-day assignments."
                )

            used_slots.add((exam_date, start_time, venue.name))
            invigilator_dates.setdefault(invigilator.lower(), set()).add(exam_date)
            invigilator_slots.add((invigilator.lower(), exam_date, start_time))
            level_dates.setdefault(course.student_level.lower(), set()).add(exam_date)
            level_slot_courses[
                (course.student_level.lower(), exam_date, start_time)
            ] = course.course_code
            batch_count = min(remaining_students, _effective_capacity(venue))
            remaining_students -= batch_count
            entries.append(
                TimetableEntryOut(
                    id=0,
                    course_code=course.course_code,
                    course_title=course.course_title,
                    exam_date=exam_date,
                    start_time=start_time,
                    end_time=_end_time(start_time, course.duration_minutes),
                    venue=venue.name,
                    student_level=course.student_level,
                    student_count=batch_count,
                    invigilator_username=invigilator,
                )
            )

    return sorted(entries, key=lambda entry: (entry.exam_date, entry.start_time, entry.venue))


def _next_available_slot(
    course_code: str,
    student_level: str,
    duration_minutes: int,
    slots: list[tuple[str, str, VenueInput]],
    used_slots: set[tuple[str, str, str]],
    level_dates: dict[str, set[str]],
    level_slot_courses: dict[tuple[str, str, str], str],
    invigilators: list[str],
    invigilator_dates: dict[str, set[str]],
    invigilator_slots: set[tuple[str, str, str]],
) -> tuple[str, str, VenueInput] | None:
    for exam_date, start_time, venue in slots:
        slot_key = (exam_date, start_time, venue.name)
        if slot_key in used_slots:
            continue
        level_slot_key = (student_level.lower(), exam_date, start_time)
        existing_course = level_slot_courses.get(level_slot_key)
        if existing_course is not None and existing_course != course_code:
            continue
        if not _fits_exam_window(start_time, duration_minutes):
            continue
        if not any(
            _is_invigilator_available(
                invigilator,
                exam_date,
                start_time,
                invigilator_dates,
                invigilator_slots,
            )
            for invigilator in invigilators
        ):
            continue
        return exam_date, start_time, venue
    return None


def _end_time(start_time: str, duration_minutes: int) -> str:
    start = datetime.strptime(start_time, "%H:%M")
    return (start + timedelta(minutes=duration_minutes)).strftime("%H:%M")


def _effective_capacity(venue: VenueInput) -> int:
    # The capacity recorded in the uploaded venue data is the capacity the school
    # has approved for examinations. Do not silently halve it: doing so creates
    # artificial batches and can make an otherwise valid timetable impossible.
    return venue.capacity


def _fits_exam_window(start_time: str, duration_minutes: int) -> bool:
    start = datetime.strptime(start_time, "%H:%M")
    end = start + timedelta(minutes=duration_minutes)
    day_start = datetime.strptime(_exam_day_start, "%H:%M")
    day_end = datetime.strptime(_exam_day_end, "%H:%M")
    return day_start <= start and end <= day_end


def _validate_exam_window(entry: TimetableEntryOut) -> None:
    try:
        start = datetime.strptime(entry.start_time[:5], "%H:%M")
        end = datetime.strptime(entry.end_time[:5], "%H:%M")
        day_start = datetime.strptime(_exam_day_start, "%H:%M")
        day_end = datetime.strptime(_exam_day_end, "%H:%M")
    except ValueError as error:
        raise ValueError("The generated timetable contains an invalid exam time.") from error

    if start < day_start or end > day_end or end <= start:
        raise ValueError(
            f"The generated timetable schedules {entry.course_code} outside the 7am to 7pm exam day."
        )


def validate_live_timetable_entries(
    entries: list[TimetableEntryOut],
    *,
    venues: list[VenueInput],
    invigilators: list[str],
) -> None:
    """Validate an edited timetable against the same live scheduling rules.

    Unlike generation, AI edits may propose arbitrary start times.  Therefore
    this validator checks overlapping time ranges, not just matching slots.
    Batches of the *same* course and student group may run concurrently in
    different venues, which is how the existing scheduler splits large courses.
    """
    venues_by_name = {venue.name.lower(): venue for venue in venues}
    invigilators_by_name = {name.lower() for name in invigilators}

    for entry in entries:
        try:
            datetime.strptime(entry.exam_date[:10], "%Y-%m-%d")
        except ValueError as error:
            raise ValueError(
                f"{entry.course_code} has an invalid exam date: {entry.exam_date}."
            ) from error
        _validate_exam_window(entry)
        venue = venues_by_name.get(entry.venue.lower())
        if venue is None:
            raise ValueError(f"{entry.venue} is not a known venue with a recorded capacity.")
        if entry.student_count > _effective_capacity(venue):
            raise ValueError(
                f"{entry.course_code} exceeds the recorded capacity for {venue.name}."
            )
        if entry.invigilator_username.lower() not in invigilators_by_name:
            raise ValueError(
                f"{entry.invigilator_username} is not a known invigilator."
            )

    for index, entry in enumerate(entries):
        for other in entries[index + 1 :]:
            if entry.exam_date != other.exam_date or not _times_overlap(entry, other):
                continue
            if entry.venue.lower() == other.venue.lower():
                raise ValueError(
                    f"{entry.venue} is double-booked on {entry.exam_date}."
                )
            if entry.invigilator_username.lower() == other.invigilator_username.lower():
                raise ValueError(
                    f"{entry.invigilator_username} is double-booked on {entry.exam_date}."
                )
            same_student_group = entry.student_level.lower() == other.student_level.lower()
            if same_student_group and entry.course_code != other.course_code:
                raise ValueError(
                    f"{entry.student_level} has overlapping exams ({entry.course_code} and {other.course_code}) on {entry.exam_date}."
                )


def _times_overlap(first: TimetableEntryOut, second: TimetableEntryOut) -> bool:
    first_start = datetime.strptime(first.start_time[:5], "%H:%M")
    first_end = datetime.strptime(first.end_time[:5], "%H:%M")
    second_start = datetime.strptime(second.start_time[:5], "%H:%M")
    second_end = datetime.strptime(second.end_time[:5], "%H:%M")
    return first_start < second_end and second_start < first_end


def _next_available_invigilator(
    invigilators: list[str],
    exam_date: str,
    start_time: str,
    invigilator_dates: dict[str, set[str]],
    invigilator_slots: set[tuple[str, str, str]],
) -> str | None:
    ranked_invigilators = sorted(
        invigilators,
        key=lambda invigilator: len(invigilator_dates.get(invigilator.lower(), set())),
    )
    for invigilator in ranked_invigilators:
        if _is_invigilator_available(
            invigilator, exam_date, start_time, invigilator_dates, invigilator_slots
        ):
            return invigilator
    return None


def _is_invigilator_available(
    invigilator: str,
    exam_date: str,
    start_time: str,
    invigilator_dates: dict[str, set[str]],
    invigilator_slots: set[tuple[str, str, str]],
) -> bool:
    name = invigilator.lower()
    return (
        (name, exam_date, start_time) not in invigilator_slots
    )


def _has_consecutive_date(existing_dates: set[str], candidate_date: str) -> bool:
    candidate = datetime.strptime(candidate_date, "%Y-%m-%d").date()
    for existing_date in existing_dates:
        existing = datetime.strptime(existing_date, "%Y-%m-%d").date()
        if abs((candidate - existing).days) == 1:
            return True
    return False


def _validate_no_consecutive_dates(
    dates_by_owner: dict[str, set[str]],
    message: str,
) -> None:
    for owner, dates in dates_by_owner.items():
        sorted_dates = sorted(datetime.strptime(item, "%Y-%m-%d").date() for item in dates)
        for previous, current in zip(sorted_dates, sorted_dates[1:]):
            if (current - previous).days == 1:
                raise ValueError(f"{message}: {owner}.")


def _validate_no_slot_clash(
    slots: dict[tuple[str, str, str], str],
    slot_key: tuple[str, str, str],
    course_code: str,
    message: str,
    *,
    allow_same_course: bool = False,
) -> None:
    existing_course = slots.get(slot_key)
    if existing_course is None:
        slots[slot_key] = course_code
        return
    if allow_same_course and existing_course == course_code:
        return
    raise ValueError(f"{message} on {slot_key[1]} at {slot_key[2]}.")


def _validate_generated_entries(
    request: TimetableRequest,
    entries: list[TimetableEntryOut],
) -> None:
    expected_course_codes = {course.course_code for course in request.courses}
    generated_course_codes = {entry.course_code for entry in entries}
    if generated_course_codes != expected_course_codes:
        raise ValueError("Generated courses do not match the supplied courses.")

    courses_by_code = {course.course_code: course for course in request.courses}
    generated_counts: dict[str, int] = {course.course_code: 0 for course in request.courses}
    allowed_dates = set(request.exam_dates)
    allowed_times = set(request.start_times)
    venues_by_name = {venue.name: venue for venue in request.venues}
    allowed_invigilators = set(request.invigilators)
    venues_by_slot: dict[tuple[str, str], set[str]] = {}
    invigilators_by_slot: dict[tuple[str, str, str], str] = {}
    student_groups_by_slot: dict[tuple[str, str, str], str] = {}
    invigilator_dates: dict[str, set[str]] = {}
    level_dates: dict[str, set[str]] = {}

    for entry in entries:
        if entry.exam_date not in allowed_dates:
            raise ValueError(f"The generated timetable contains an unsupported exam date: {entry.exam_date}.")
        if entry.start_time not in allowed_times:
            raise ValueError(f"The generated timetable contains an unsupported start time: {entry.start_time}.")
        if entry.venue not in venues_by_name:
            raise ValueError(f"The generated timetable contains an unknown venue: {entry.venue}.")
        if entry.invigilator_username not in allowed_invigilators:
            raise ValueError(
                f"The generated timetable contains an unknown invigilator: {entry.invigilator_username}."
            )
        _validate_exam_window(entry)

        course = courses_by_code[entry.course_code]
        if entry.student_level != course.student_level:
            raise ValueError(f"The generated timetable changed the student level for {entry.course_code}.")
        if entry.student_count > _effective_capacity(venues_by_name[entry.venue]):
            raise ValueError(
                f"The generated timetable exceeded the supplied capacity for {entry.venue}."
            )
        generated_counts[entry.course_code] += entry.student_count

        slot = (entry.exam_date, entry.start_time)
        used_venues = venues_by_slot.setdefault(slot, set())
        if entry.venue in used_venues:
            raise ValueError(
                f"The generated timetable double-booked {entry.venue} on {entry.exam_date} at {entry.start_time}."
            )
        used_venues.add(entry.venue)
        _validate_no_slot_clash(
            invigilators_by_slot,
            (entry.invigilator_username.lower(), entry.exam_date, entry.start_time),
            entry.course_code,
            f"The generated timetable double-booked invigilator {entry.invigilator_username}",
        )
        _validate_no_slot_clash(
            student_groups_by_slot,
            (entry.student_level.lower(), entry.exam_date, entry.start_time),
            entry.course_code,
            f"The generated timetable has a student group clash for {entry.student_level}",
            allow_same_course=True,
        )
        invigilator_dates.setdefault(entry.invigilator_username.lower(), set()).add(
            entry.exam_date
        )
        level_dates.setdefault(entry.student_level.lower(), set()).add(entry.exam_date)

    expected_counts = {
        course.course_code: course.student_count for course in request.courses
    }
    if generated_counts != expected_counts:
        raise ValueError("Generated batch counts do not match the supplied course sizes.")
