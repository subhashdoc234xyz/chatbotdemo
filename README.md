# Mori — a little clarity

Mori is a polished Flutter chat app for students: a calm, responsive conversation screen with suggested prompts and a Groq-powered assistant. The Flutter client talks to a small FastAPI service so your Groq secret stays on the server and out of the mobile app.

## Run the Flutter app

Install Flutter (already installed at `C:\Users\Subhash\development\flutter`) and an Android emulator or connect an Android phone with USB debugging enabled.

```powershell
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

`10.0.2.2` lets the Android emulator reach a server running on your computer. For a physical phone, use your computer's LAN IP in place of `10.0.2.2`. If testing the Flutter web build locally, use `http://localhost:8000`.

## Start the API locally

Create a Groq API key at [console.groq.com/keys](https://console.groq.com/keys), then set it in PowerShell. Never put the key in Dart code, a `--dart-define`, or a public Git repository.

```powershell
cd server
py -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
$env:GROQ_API_KEY = "your-groq-api-key"
uvicorn main:app --reload --port 8000
```

The API health check is at `http://localhost:8000/health`.

## Deploy the API to Render

1. Push this project to a GitHub repository.
2. In Render, choose **New + → Blueprint** and select that repository. Render reads `render.yaml` and creates `mori-chat-api`.
3. In the Render service's **Environment** settings, set `GROQ_API_KEY` to your Groq key. Keep it secret. `GROQ_MODEL` defaults to `llama-3.3-70b-versatile`.
4. Wait for deploy to finish and confirm `https://YOUR-SERVICE.onrender.com/health` returns `{"status":"ok",...}`.
5. Run Flutter using your service URL:

```powershell
flutter run --dart-define=API_BASE_URL=https://YOUR-SERVICE.onrender.com
```

The API root at `/` returns a small service status page. Render's free web services may sleep when idle, so the first request after a quiet period can take longer.

## Show it in the interview

- Open the Flutter app on the emulator or Android phone.
- Tap a suggested prompt or type a question and send it.
- Explain the flow: Flutter sends a JSON message to FastAPI, the backend reads `GROQ_API_KEY` from its environment, calls Groq, and returns the reply.
- Mention that keeping API credentials in the backend avoids shipping them in the app bundle.

## Build an Android APK

After deploying the backend, build a release APK with its URL included:

```powershell
flutter build apk --release --dart-define=API_BASE_URL=https://YOUR-SERVICE.onrender.com
```

The APK will be in `build\app\outputs\flutter-apk\app-release.apk`.
