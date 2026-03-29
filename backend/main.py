"""Mumbli FastAPI backend — transcription orchestration, polishing, auth."""

import asyncio
import json
import logging

from dotenv import load_dotenv
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import JSONResponse

load_dotenv(dotenv_path="../.env")

from services.auth import verify_token  # noqa: E402
from services.polishing import polish_text  # noqa: E402
from services.transcription import TranscriptionSession  # noqa: E402

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("mumbli")

app = FastAPI(title="Mumbli Backend", version="0.1.0")


# ---------------------------------------------------------------------------
# REST endpoints
# ---------------------------------------------------------------------------


@app.get("/health")
async def health():
    return {"status": "ok"}


@app.post("/auth/verify")
async def auth_verify(token: str | None = None):
    """Verify a Supabase JWT and return user info.

    Accepts token in Authorization header (Bearer <token>) or body.
    """
    # This is a simple utility endpoint; the real auth happens on WebSocket connect.
    if not token:
        return JSONResponse(status_code=401, content={"error": "Token required"})
    try:
        payload = await verify_token(token)
        return {"user_id": payload.get("sub"), "email": payload.get("email")}
    except Exception as exc:
        return JSONResponse(status_code=401, content={"error": str(exc)})


# ---------------------------------------------------------------------------
# WebSocket endpoint — streaming transcription + polishing
# ---------------------------------------------------------------------------


async def _send_json(ws: WebSocket, data: dict) -> None:
    await ws.send_text(json.dumps(data))


@app.websocket("/ws/transcribe")
async def ws_transcribe(ws: WebSocket):
    await ws.accept()

    # ── Step 1: Authentication ──────────────────────────────────────────
    try:
        raw = await asyncio.wait_for(ws.receive_text(), timeout=10)
        auth_msg = json.loads(raw)
        if auth_msg.get("type") != "auth" or not auth_msg.get("token"):
            await _send_json(ws, {"type": "error", "message": "First message must be auth"})
            await ws.close(code=4001, reason="Auth required")
            return

        user_payload = await verify_token(auth_msg["token"])
        user_id = user_payload.get("sub", "unknown")
        logger.info("WS authenticated: user=%s", user_id)
    except asyncio.TimeoutError:
        await _send_json(ws, {"type": "error", "message": "Auth timeout"})
        await ws.close(code=4001, reason="Auth timeout")
        return
    except Exception as exc:
        await _send_json(ws, {"type": "error", "message": f"Auth failed: {exc}"})
        await ws.close(code=4001, reason="Auth failed")
        return

    # ── Step 2: Wait for start signal, then stream audio ────────────────
    session: TranscriptionSession | None = None
    receive_task: asyncio.Task | None = None

    try:
        while True:
            message = await ws.receive()

            # Text frame
            if "text" in message:
                data = json.loads(message["text"])
                msg_type = data.get("type")

                if msg_type == "start":
                    if session is not None:
                        await session.close()
                        if receive_task:
                            receive_task.cancel()

                    session = TranscriptionSession()
                    await session.start()
                    # Start background task to accumulate transcription
                    receive_task = asyncio.create_task(session.receive_partials())
                    await _send_json(ws, {"type": "listening"})
                    logger.info("Transcription session started for user=%s", user_id)

                elif msg_type == "stop":
                    if session is None:
                        await _send_json(ws, {"type": "error", "message": "No active session"})
                        continue

                    # Cancel the receive_partials task — stop() will drain remaining
                    if receive_task:
                        receive_task.cancel()
                        try:
                            await receive_task
                        except asyncio.CancelledError:
                            pass

                    raw_text = await session.stop()
                    session = None
                    receive_task = None
                    logger.info("Raw transcription: %s", raw_text[:200] if raw_text else "(empty)")

                    # Polish
                    try:
                        polished = await polish_text(raw_text)
                    except Exception as exc:
                        logger.error("Polishing failed: %s", exc)
                        polished = raw_text  # fallback to raw

                    await _send_json(ws, {"type": "final", "text": polished})
                    logger.info("Sent polished text for user=%s", user_id)

            # Binary frame — audio chunk
            elif "bytes" in message:
                if session is not None:
                    await session.send_audio(message["bytes"])

    except WebSocketDisconnect:
        logger.info("WS disconnected: user=%s", user_id)
    except Exception as exc:
        logger.error("WS error: %s", exc)
        try:
            await _send_json(ws, {"type": "error", "message": "Internal server error"})
        except Exception:
            pass
    finally:
        if receive_task:
            receive_task.cancel()
        if session:
            await session.close()
