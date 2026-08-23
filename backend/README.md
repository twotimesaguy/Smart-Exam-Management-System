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

The API uses PostgreSQL. On Railway, add a PostgreSQL service and reference its
automatically supplied `DATABASE_URL` in this API service. The schema and its
initial allocation data are created automatically at startup.

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
- `POST /malpractice/transcriptions`
- `GET /malpractice/reports`
- `GET /assignments/{invigilator_username}`

The facial recognition service currently has a deterministic fallback so the
API can run immediately. Install `insightface` and `onnxruntime` when you are
ready to use real face embeddings.

## Voice-note transcription

The app records the voice note first, then sends it to the backend for
transcription. Set `GEMINI_API_KEY` in the Railway API service (not the Flutter
app) and redeploy. Recordings are saved as speech-friendly WAV files; short
notes up to 10 MB are supported. The original audio is still attached to the
malpractice report even when transcription fails.

## PostgreSQL setup

Create `backend/.env` from `.env.example` and set a PostgreSQL connection URL
when running locally:

```text
DATABASE_URL="postgresql://postgres:password@localhost:5432/exam_system"
```

For Railway, create a PostgreSQL database, then add its `DATABASE_URL` as a
variable/reference on the backend service. Do not set `DATABASE_PATH`; SQLite
is no longer used.

Timetable generation runs locally in FastAPI. It extracts the lecturer, venue,
and course records from the uploaded Excel, CSV, Word, or text-based PDF files,
then applies the selected dates, time slots, venue capacity, no-clash, and
rest-day constraints before saving the timetable. No Gemini API key is required.
