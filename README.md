# SEMS Flutter App

Flutter client for the Intelligent Exam System backend.

## API server setup

Login and signup call the FastAPI backend. A phone on mobile data cannot reach
`http://10.0.2.2:8000` or `http://127.0.0.1:8000`; those are local development
addresses only.

For an app that works without your PC being on, deploy the FastAPI backend to a
hosting provider and use its public HTTPS URL when running or building Flutter:

```powershell
flutter run --dart-define=API_BASE_URL=https://your-api-url
```

```powershell
flutter build apk --release --dart-define=API_BASE_URL=https://your-api-url
```

## Web version

The Flutter web target is enabled in this project. To run it locally in Chrome:

```powershell
flutter run -d chrome
```

For a public web version, deploy the FastAPI backend first and build the web
client with the hosted backend URL:

```powershell
flutter build web --release --dart-define=API_BASE_URL=https://your-api-url
```

Upload the generated `build/web` folder to a static web host such as Firebase
Hosting, Netlify, Vercel, GitHub Pages, or your school server.

For local Android emulator testing, the app still falls back to:

```text
http://10.0.2.2:8000
```

For local Windows/web testing, the app falls back to:

```text
http://127.0.0.1:8000
```

For a real Android phone on the same Wi-Fi as your PC, start the backend with a
network host and pass your PC's LAN IP to Flutter:

```powershell
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
flutter run --dart-define=API_BASE_URL=http://YOUR_PC_IP:8000
```

In release builds, `API_BASE_URL` is required so the installed app does not point
at an emulator-only address.
