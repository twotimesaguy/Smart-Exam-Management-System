# Intelligent Exam System Backend

FastAPI backend for authentication, student registration, examination allocation,
biometric attendance, assignments, and malpractice reports.

## Run locally

```powershell
cd backend
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
uvicorn app.main:app --reload
```

By default, the API uses SQLite at `backend/data/exam_system.db`.

API docs will be available at:

```text
http://127.0.0.1:8000/docs
```

For Android emulator Flutter calls, use:

```text
http://10.0.2.2:8000
```

For a real phone that should work without your PC being on, deploy this backend
to a public host and build the Flutter app with the hosted API URL:

```powershell
flutter build apk --release --dart-define=API_BASE_URL=https://your-api-url
```

## Key endpoints

- `POST /auth/signup`
- `POST /auth/login`
- `POST /students`
- `GET /students`
- `POST /allocation/generate`
- `GET /allocation/timetable/{timetable_id}/excel`
- `POST /attendance/record`
- `GET /attendance/export/pdf`
- `POST /malpractice/reports`
- `GET /malpractice/reports`
- `GET /assignments/{invigilator_username}`

The facial recognition service currently has a deterministic fallback so the
API can run immediately. Install `insightface` and `onnxruntime` when you are
ready to use real face embeddings.

## SQLite setup

Create `backend/.env` from `.env.example` if you want to customize the database
file location:

```text
DATABASE_PATH="data/exam_system.db"
```

Timetable generation runs locally in FastAPI. It extracts the lecturer, venue,
and course records from the uploaded Excel, CSV, Word, or text-based PDF files,
then applies the selected dates, time slots, venue capacity, no-clash, and
rest-day constraints before saving the timetable. No Gemini API key is required.
