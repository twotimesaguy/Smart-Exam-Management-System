# SEMS - Intelligent Exam System

SEMS is a Flutter application with a FastAPI backend for exam allocation, student registration, biometric attendance, invigilator assignments, and malpractice reporting.

The project consists of two applications that should be started separately:

| Component | Directory | Technology |
| --- | --- | --- |
| Mobile/web client | project root | Flutter/Dart |
| API and database layer | `backend/` | Python, FastAPI, PostgreSQL |

## Prerequisites

Install the following before starting from a fresh clone:

- [Flutter](https://docs.flutter.dev/get-started/install) stable, including a Dart SDK compatible with Dart `3.11.3` or newer.
- Python 3.10 or newer.
- PostgreSQL 14 or newer, running locally (or a reachable hosted PostgreSQL database).
- Android Studio and an Android emulator for Android development. For a physical Android phone, enable Developer options and USB debugging.
- Chrome if you want to run the web version.

Verify the main tools in PowerShell:

```powershell
flutter doctor
python --version
psql --version
```

Resolve any issues reported by `flutter doctor` before continuing. macOS/iOS development additionally requires Xcode and CocoaPods.

## 1. Get the project

```powershell
git clone <YOUR-REPOSITORY-URL>
cd flutter_application_1
```

If the project was provided as a folder rather than through Git, open a PowerShell window in that folder instead.

## 2. Create the local database

Start PostgreSQL, then create a database and a user. The following example uses the default `postgres` administrator account; change the values to suit your installation.

```powershell
psql -U postgres
```

Run these commands at the PostgreSQL prompt:

```sql
CREATE USER exam_user WITH PASSWORD 'choose-a-strong-password';
CREATE DATABASE exam_system OWNER exam_user;
\q
```

The backend creates and updates its tables automatically when it starts. There are no migrations to run manually.

## 3. Set up and run the backend

From the project root, create a Python virtual environment, install the backend packages, and create its local configuration file:

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
Copy-Item .env.example .env
```

If PowerShell prevents the activation script from running, use this only for the current terminal session and try again:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

Open `backend/.env` and set `DATABASE_URL` to your database connection string:

```dotenv
DATABASE_URL="postgresql://exam_user:choose-a-strong-password@localhost:5432/exam_system"
```

`GEMINI_API_KEY` is optional. Add it only if you want AI timetable editing and voice-note transcription; it belongs in `backend/.env`, never in the Flutter app or source control. The remaining values in `.env.example` can normally be left as they are for local development.

Start the API:

```powershell
uvicorn app.main:app --reload
```

The server should report that it is running on `http://127.0.0.1:8000`. Check that it works by opening [http://127.0.0.1:8000/docs](http://127.0.0.1:8000/docs) or running this in another terminal:

```powershell
Invoke-RestMethod http://127.0.0.1:8000/health
```

Expected result:

```text
status
------
ok
```

Keep this terminal open while using the app. To stop it, press `Ctrl+C`, then run `deactivate` to leave the virtual environment.

## 4. Install Flutter dependencies

Open a second PowerShell terminal at the project root:

```powershell
cd path\to\flutter_application_1
flutter pub get
flutter devices
```

`flutter devices` lists the connected phone, running emulator, Chrome, and desktop targets that Flutter can use.

## 5. Run the client against your local backend

Choose the command that matches where the client runs. `API_BASE_URL` tells Flutter how to reach FastAPI.

### Chrome or Windows desktop

Both run on the same machine as the API, so use `127.0.0.1`:

```powershell
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

For Windows desktop, first ensure Windows desktop support is installed (`flutter doctor`), then run:

```powershell
flutter run -d windows --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

### Android emulator

The Android emulator uses `10.0.2.2` to access the computer hosting the API:

```powershell
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

### Physical Android phone on the same Wi-Fi

1. Find the computer's IPv4 address with `ipconfig` (for example, `192.168.1.20`).
2. Start the backend so it accepts connections from the network:

   ```powershell
   cd backend
   .\.venv\Scripts\Activate.ps1
   uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
   ```

3. Allow port 8000 through the computer firewall if prompted, then run Flutter using that address:

   ```powershell
   flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000
   ```

Replace `192.168.1.20` with your computer's actual LAN address. The phone must be on the same network.

## Default hosted API

When `API_BASE_URL` is omitted, the current app source uses its configured Railway API in debug builds. Passing `API_BASE_URL` explicitly is recommended for local development, release builds, and reproducible setup. A release build should always use a public HTTPS API URL.

## Build a release

First deploy the backend to a host with PostgreSQL and configure its environment variables there. Then build the client with the public HTTPS address:

```powershell
flutter build apk --release --dart-define=API_BASE_URL=https://your-api.example.com
flutter build web --release --dart-define=API_BASE_URL=https://your-api.example.com
```

The Android APK is written to `build\app\outputs\flutter-apk\app-release.apk`. The web site is written to `build\web`; upload that folder to a static host.

## Useful commands

```powershell
# Run Flutter checks and tests
flutter analyze
flutter test

# Run the backend test suite (from backend/, with .venv active).
# Install pytest first because it is not a runtime dependency.
python -m pip install pytest
python -m pytest

# Regenerate app icons after changing assets/logo.jpg
dart run flutter_launcher_icons
```

## Troubleshooting

| Problem | What to check |
| --- | --- |
| App cannot connect to the API | Confirm `http://127.0.0.1:8000/health` works and use the correct address for Chrome, emulator, or phone. |
| Backend exits on startup | Confirm `backend/.env` exists and that `DATABASE_URL` points to a running PostgreSQL database. |
| `flutter` or Android device is not found | Run `flutter doctor` and `flutter devices`; install the components Flutter reports as missing. |
| Phone cannot connect | Confirm both devices are on the same Wi-Fi, use the PC's IPv4 address rather than `localhost`, start Uvicorn with `--host 0.0.0.0`, and check the firewall. |
| AI transcription/editing is unavailable | Set a valid `GEMINI_API_KEY` in `backend/.env`, then restart the backend. |

For endpoint details and backend-specific notes, see [backend/README.md](backend/README.md).
