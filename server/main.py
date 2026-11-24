from __future__ import annotations

import os

import httpx
from fastapi import FastAPI, Header, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

app = FastAPI(title="Mori Chat API", version="1.0.0")

# Mobile apps do not enforce browser CORS, while this also lets the Flutter web
# build call the same API. Restrict origins here if you publish a web client.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET", "POST"],
    allow_headers=["Content-Type", "X-Groq-Api-Key"],
)


class ChatRequest(BaseModel):
    message: str = Field(min_length=1, max_length=4000)


class ChatResponse(BaseModel):
    reply: str


SYSTEM_PROMPT = """You are Mori, a warm, thoughtful AI companion in a student wellbeing and productivity app. Listen carefully, respond with empathy, and keep replies clear and useful. Ask one gentle follow-up when it would help. For planning, break things into small doable steps. Never claim to be a therapist or replace professional care. If someone may be in immediate danger, encourage them to contact local emergency services or a trusted person right away."""


@app.get("/")
async def root():
    return {"name": "Mori Chat API", "status": "online", "chat": "/chat", "health": "/health"}


@app.get("/health")
async def health():
    return {"status": "ok", "groq_configured": bool(os.getenv("GROQ_API_KEY"))}


@app.post("/chat", response_model=ChatResponse)
async def chat(body: ChatRequest, x_groq_api_key: str | None = Header(default=None)):
    # A user may provide a personal key in the client settings. The server
    # environment key remains the default for clients that do not provide one.
    api_key = ("" if x_groq_api_key is None else x_groq_api_key.strip()) or os.getenv("GROQ_API_KEY")
    if not api_key:
        raise HTTPException(status_code=503, detail="GROQ_API_KEY is not configured on the server.")

    model = os.getenv("GROQ_MODEL", "openai/gpt-oss-20b")
    try:
        async with httpx.AsyncClient(timeout=50.0) as client:
            response = await client.post(
                "https://api.groq.com/openai/v1/chat/completions",
                headers={"Authorization": f"Bearer {api_key}"},
                json={
                    "model": model,
                    "messages": [
                        {"role": "system", "content": SYSTEM_PROMPT},
                        {"role": "user", "content": body.message},
                    ],
                    "temperature": 0.7,
                    "max_tokens": 700,
                },
            )
    except httpx.TimeoutException as exc:
        raise HTTPException(status_code=504, detail="Groq took too long to respond. Please try again.") from exc
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=502, detail="Could not connect to Groq.") from exc

    if response.is_error:
        # Groq's response body contains useful causes (invalid key, model,
        # quota), and does not contain the submitted API key. Surface a short
        # provider message so local setup errors can be diagnosed in the UI.
        try:
            error_body = response.json()
            provider_error = error_body.get("error", {})
            provider_message = provider_error.get("message") if isinstance(provider_error, dict) else None
        except (ValueError, TypeError):
            provider_message = None
        detail = (
            f"Groq error ({response.status_code}): {provider_message[:300]}"
            if isinstance(provider_message, str) and provider_message.strip()
            else f"Groq API returned status {response.status_code}. Check the API key, model, and Groq account limits."
        )
        raise HTTPException(status_code=502, detail=detail)

    try:
        payload = response.json()
        reply = payload["choices"][0]["message"]["content"]
    except (ValueError, KeyError, IndexError, TypeError) as exc:
        raise HTTPException(status_code=502, detail="Groq returned an unexpected response.") from exc
    if not isinstance(reply, str) or not reply.strip():
        raise HTTPException(status_code=502, detail="Groq returned an empty reply.")
    return ChatResponse(reply=reply.strip())
