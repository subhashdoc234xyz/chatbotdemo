# Mori — local interview demo

Mori is a Flutter chat app with a small FastAPI service that calls Groq. Both the website and API run on your computer. There is no hosting deployment configuration in this project.

## Run the local API

Open PowerShell in `C:\Users\Subhash\projects\chatbot\server` and install the dependencies once:

```powershell
py -m pip install -r requirements.txt
```

Start the API:

```powershell
py -m uvicorn main:app --reload --port 8000
```

Keep this terminal open. The health check is <http://localhost:8000/health>.

## Run the website locally

Open a second PowerShell window in `C:\Users\Subhash\projects\chatbot`:

```powershell
C:\src\flutter\bin\flutter.bat pub get
C:\src\flutter\bin\flutter.bat run -d web-server --web-port 8080 --dart-define=API_BASE_URL=http://localhost:8000
```

Open <http://localhost:8080>. To pick up code changes, stop the Flutter command with `Ctrl+C` and run it again. If the browser still shows an old version, hard refresh with `Ctrl+Shift+R`.

## Set up Groq

In Mori, open **Settings**, paste your Groq API key, and click **Save**. The browser stores the key locally and sends it to the API on `localhost:8000` when you chat. The health endpoint's `groq_configured` field only reports whether a key is set in the API process environment; it does not check the browser-saved key.

Never commit an API key to the repository. If you prefer an environment key, set `$env:GROQ_API_KEY` in the API terminal before starting Uvicorn.
