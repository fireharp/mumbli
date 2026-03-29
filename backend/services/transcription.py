"""ElevenLabs STT streaming service.

Receives audio chunks, streams to ElevenLabs via WebSocket, accumulates transcription.
"""

import json
import os

import websockets


ELEVENLABS_STT_WS = "wss://api.elevenlabs.io/v1/speech-to-text/ws"


class TranscriptionSession:
    """A single streaming transcription session with ElevenLabs."""

    def __init__(self) -> None:
        self._ws: websockets.ClientConnection | None = None
        self._accumulated_text: str = ""

    async def start(self) -> None:
        """Open WebSocket connection to ElevenLabs STT."""
        api_key = os.environ["ELEVENLABS_API_KEY"]
        url = f"{ELEVENLABS_STT_WS}?model_id=scribe_v1&language_code=auto"

        self._ws = await websockets.connect(
            url,
            additional_headers={"xi-api-key": api_key},
        )

        # Send initial config
        init_message = {
            "type": "config",
            "encoding": "pcm_16000",
            "sample_rate": 16000,
        }
        await self._ws.send(json.dumps(init_message))

    async def send_audio(self, chunk: bytes) -> None:
        """Send an audio chunk to ElevenLabs."""
        if self._ws is None:
            return
        # Send audio as a binary-encoded base64 chunk per ElevenLabs protocol
        import base64

        audio_message = {
            "type": "audio",
            "audio": base64.b64encode(chunk).decode("ascii"),
        }
        await self._ws.send(json.dumps(audio_message))

    async def stop(self) -> str:
        """Signal end of audio, collect final transcription, close connection."""
        if self._ws is None:
            return self._accumulated_text

        # Send EOS signal
        eos_message = {"type": "flush"}
        await self._ws.send(json.dumps(eos_message))

        # Collect all remaining transcription messages
        try:
            async for raw in self._ws:
                msg = json.loads(raw)
                msg_type = msg.get("type", "")

                if msg_type == "transcription":
                    text = msg.get("text", "")
                    if text:
                        if self._accumulated_text:
                            self._accumulated_text += " "
                        self._accumulated_text += text
                elif msg_type == "done":
                    break
        except websockets.exceptions.ConnectionClosed:
            pass
        finally:
            await self.close()

        return self._accumulated_text

    async def receive_partials(self) -> None:
        """Receive and accumulate partial/final transcription results.

        Call this concurrently while sending audio to accumulate text.
        """
        if self._ws is None:
            return

        try:
            async for raw in self._ws:
                msg = json.loads(raw)
                msg_type = msg.get("type", "")

                if msg_type == "transcription":
                    text = msg.get("text", "")
                    if text:
                        if self._accumulated_text:
                            self._accumulated_text += " "
                        self._accumulated_text += text
                elif msg_type == "done":
                    break
        except websockets.exceptions.ConnectionClosed:
            pass

    async def close(self) -> None:
        """Close the WebSocket connection."""
        if self._ws is not None:
            try:
                await self._ws.close()
            except Exception:
                pass
            self._ws = None

    @property
    def accumulated_text(self) -> str:
        return self._accumulated_text
