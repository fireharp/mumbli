#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11.9"
# dependencies = [
#     "httpx>=0.28.1",
#     "python-dotenv>=1.2.2",
#     "rich>=14.3.3",
# ]
# ///
"""
Interfaze, Groq, ElevenLabs, and Deepgram STT benchmark for Mumbli recordings.

Compares Interfaze speech-to-text modes against the app's current Groq Whisper
variant, ElevenLabs Scribe, and Deepgram Nova-3, then optionally asks an
audio-aware OpenAI judge to compare transcripts against the original WAV.

Usage:
    uv run benchmarks/interfaze_groq_bench.py --last 50 --judge audio
    uv run benchmarks/interfaze_groq_bench.py --file recording.wav --judge none
    uv run benchmarks/interfaze_groq_bench.py --from-json benchmarks/results/raw.json
"""

from __future__ import annotations

import argparse
import asyncio
import base64
import json
import math
import os
import random
import re
import secrets
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Any

import httpx
from dotenv import load_dotenv
from rich.console import Console
from rich.table import Table

import audio_io

console = Console()

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
DEFAULT_RECORDINGS_DIR = Path.home() / "Library/Application Support/Mumbli/recordings"
DEFAULT_RESULTS_DIR = SCRIPT_DIR / "results"
DEFAULT_REPORTS_DIR = REPO_ROOT / "reports"

INTERFAZE_MODEL = "interfaze-beta"
GROQ_MODEL = "whisper-large-v3-turbo"
ELEVENLABS_MODEL = "scribe_v1"
DEEPGRAM_MODEL = "nova-3"

PROVIDER_INTERFAZE = "Interfaze STT"
PROVIDER_INTERFAZE_RUN_TASK = "Interfaze Run Task"
PROVIDER_GROQ = "Groq Whisper"
PROVIDER_ELEVENLABS = "ElevenLabs Scribe"
PROVIDER_DEEPGRAM = "Deepgram Nova-3"
PROVIDERS = [
    PROVIDER_INTERFAZE,
    PROVIDER_INTERFAZE_RUN_TASK,
    PROVIDER_GROQ,
    PROVIDER_ELEVENLABS,
    PROVIDER_DEEPGRAM,
]

MAX_INTERFAZE_BASE64_CHARS = 20 * 1024 * 1024


def load_env() -> None:
    """Load local keys from both repo root and benchmarks env files."""
    load_dotenv(REPO_ROOT / ".env", override=False)
    load_dotenv(SCRIPT_DIR / ".env", override=False)


load_env()

INTERFAZE_KEY = os.getenv("INTERFAZE_API_KEY", "")
GROQ_KEY = os.getenv("GROQ_API_KEY", "")
ELEVENLABS_KEY = os.getenv("ELEVENLABS_API_KEY", "")
DEEPGRAM_KEY = os.getenv("DEEPGRAM_API_KEY", "")
OPENAI_KEY = os.getenv("OPENAI_API_KEY", "")
OPENAI_AUDIO_JUDGE_MODEL = os.getenv("OPENAI_AUDIO_JUDGE_MODEL", "gpt-audio")
OPENAI_TEXT_JUDGE_MODEL = os.getenv("OPENAI_TEXT_JUDGE_MODEL", "gpt-5.4-nano")


def wav_audio_duration(wav_data: bytes) -> float:
    """Calculate duration for 16-bit 16kHz mono WAV files saved by Mumbli."""
    return audio_io.wav_audio_duration_from_bytes(wav_data)


def encode_wav_data_url(wav_data: bytes) -> str:
    """Base64-inline WAV bytes as a data URL.

    Callers must pass already-decoded WAV bytes (see audio_io.load_as_wav_bytes) —
    a raw .caf/.m4a byte stream base64-inlined and labeled audio/wav would be
    broken for the judge model.
    """
    encoded = base64.b64encode(wav_data).decode("ascii")
    if len(encoded) > MAX_INTERFAZE_BASE64_CHARS:
        raise ValueError(
            f"base64 payload is {len(encoded):,} chars, above Interfaze 20 MB base64 limit"
        )
    return f"data:audio/wav;base64,{encoded}"


def read_text_if_exists(path: Path) -> str | None:
    try:
        return path.read_text(encoding="utf-8").strip()
    except FileNotFoundError:
        return None


def first_json_object(text: str) -> Any | None:
    """Parse JSON from a model response, including fenced JSON snippets."""
    cleaned = text.strip()
    if cleaned.startswith("```"):
        cleaned = re.sub(r"^```(?:json)?\s*", "", cleaned)
        cleaned = re.sub(r"\s*```$", "", cleaned).strip()

    try:
        return json.loads(cleaned)
    except json.JSONDecodeError:
        pass

    decoder = json.JSONDecoder()
    for match in re.finditer(r"\{", cleaned):
        try:
            parsed, _ = decoder.raw_decode(cleaned[match.start() :])
            return parsed
        except json.JSONDecodeError:
            continue
    return None


def find_text_field(value: Any) -> str | None:
    """Find a transcription string in common Interfaze response shapes."""
    if isinstance(value, str):
        parsed = first_json_object(value)
        if parsed is not None:
            found = find_text_field(parsed)
            if found:
                return found
        stripped = value.strip()
        return stripped or None

    if isinstance(value, dict):
        result = value.get("result")
        if isinstance(result, dict):
            text = result.get("text")
            if isinstance(text, str) and text.strip():
                return text.strip()

        text = value.get("text")
        if isinstance(text, str) and text.strip():
            return text.strip()

        for key in ("object", "precontext", "choices", "message", "content"):
            if key in value:
                found = find_text_field(value[key])
                if found:
                    return found

        for nested in value.values():
            found = find_text_field(nested)
            if found:
                return found

    if isinstance(value, list):
        for item in value:
            found = find_text_field(item)
            if found:
                return found

    return None


def provider_model(provider: str) -> str:
    if provider == PROVIDER_INTERFAZE:
        return INTERFAZE_MODEL
    if provider == PROVIDER_INTERFAZE_RUN_TASK:
        return f"{INTERFAZE_MODEL} <task>speech_to_text</task> no schema"
    if provider == PROVIDER_GROQ:
        return GROQ_MODEL
    if provider == PROVIDER_ELEVENLABS:
        return ELEVENLABS_MODEL
    if provider == PROVIDER_DEEPGRAM:
        return DEEPGRAM_MODEL
    return "unknown"


async def stt_interfaze(
    client: httpx.AsyncClient, wav_data: bytes, filename: str
) -> tuple[str, float, dict[str, Any]]:
    if not INTERFAZE_KEY:
        return "[no key]", -1.0, {"error": "INTERFAZE_API_KEY missing"}

    file_data = encode_wav_data_url(wav_data)
    payload: dict[str, Any] = {
        "model": INTERFAZE_MODEL,
        "messages": [
            {"role": "system", "content": "<task>speech_to_text</task>"},
            {
                "role": "user",
                "content": [
                    {
                        "type": "file",
                        "file": {
                            "filename": filename,
                            "file_data": file_data,
                        },
                    },
                    {"type": "text", "text": "Transcribe this audio file."},
                ],
            },
        ],
        "response_format": {"type": "json_object"},
    }

    start = time.perf_counter()
    raw: dict[str, Any] | None = None
    last_error = ""
    for include_response_format in (True, False):
        request_payload = dict(payload)
        if not include_response_format:
            request_payload.pop("response_format", None)

        resp = await client.post(
            "https://api.interfaze.ai/v1/chat/completions",
            headers={
                "Authorization": f"Bearer {INTERFAZE_KEY}",
                "Content-Type": "application/json",
            },
            json=request_payload,
            timeout=180,
        )
        if resp.status_code >= 400:
            last_error = resp.text[:500]
            if include_response_format and resp.status_code in {400, 422}:
                continue
            resp.raise_for_status()
        raw = resp.json()
        break

    elapsed = (time.perf_counter() - start) * 1000
    if raw is None:
        raise RuntimeError(f"Interfaze error: {last_error}")

    message = raw.get("choices", [{}])[0].get("message", {})
    text = find_text_field(message.get("content")) or find_text_field(raw)
    if not text:
        raise RuntimeError(f"Interfaze response did not contain transcript: {str(raw)[:500]}")

    return text, elapsed, {"response_id": raw.get("id")}


async def stt_interfaze_run_task(
    client: httpx.AsyncClient, wav_data: bytes, filename: str
) -> tuple[str, float, dict[str, Any]]:
    if not INTERFAZE_KEY:
        return "[no key]", -1.0, {"error": "INTERFAZE_API_KEY missing"}

    file_data = encode_wav_data_url(wav_data)
    payload: dict[str, Any] = {
        "model": INTERFAZE_MODEL,
        "messages": [
            {"role": "system", "content": "<task>speech_to_text</task>"},
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": "Transcribe this audio file."},
                    {
                        "type": "file",
                        "file": {
                            "filename": filename,
                            "file_data": file_data,
                        },
                    },
                ],
            },
        ],
    }

    start = time.perf_counter()
    resp = await client.post(
        "https://api.interfaze.ai/v1/chat/completions",
        headers={
            "Authorization": f"Bearer {INTERFAZE_KEY}",
            "Content-Type": "application/json",
        },
        json=payload,
        timeout=180,
    )
    elapsed = (time.perf_counter() - start) * 1000
    resp.raise_for_status()
    raw = resp.json()

    message = raw.get("choices", [{}])[0].get("message", {})
    text = find_text_field(message.get("content")) or find_text_field(raw)
    if not text:
        raise RuntimeError(f"Interfaze response did not contain transcript: {str(raw)[:500]}")

    return text, elapsed, {"response_id": raw.get("id"), "request_mode": "run_task_no_schema"}


async def stt_groq(
    client: httpx.AsyncClient, wav_data: bytes, filename: str
) -> tuple[str, float, dict[str, Any]]:
    if not GROQ_KEY:
        return "[no key]", -1.0, {"error": "GROQ_API_KEY missing"}

    start = time.perf_counter()
    resp = await client.post(
        "https://api.groq.com/openai/v1/audio/transcriptions",
        headers={"Authorization": f"Bearer {GROQ_KEY}"},
        files={"file": (filename, wav_data, "audio/wav")},
        data={"model": GROQ_MODEL},
        timeout=120,
    )
    elapsed = (time.perf_counter() - start) * 1000
    resp.raise_for_status()
    data = resp.json()
    return data.get("text", ""), elapsed, {"response_id": data.get("id")}


async def stt_elevenlabs(
    client: httpx.AsyncClient, wav_data: bytes, filename: str
) -> tuple[str, float, dict[str, Any]]:
    if not ELEVENLABS_KEY:
        return "[no key]", -1.0, {"error": "ELEVENLABS_API_KEY missing"}

    start = time.perf_counter()
    resp = await client.post(
        "https://api.elevenlabs.io/v1/speech-to-text",
        headers={"xi-api-key": ELEVENLABS_KEY},
        files={"file": (filename, wav_data, "audio/wav")},
        data={"model_id": ELEVENLABS_MODEL},
        timeout=120,
    )
    elapsed = (time.perf_counter() - start) * 1000
    resp.raise_for_status()
    data = resp.json()
    return data.get("text", ""), elapsed, {"response_id": data.get("id")}


async def stt_deepgram(
    client: httpx.AsyncClient, wav_data: bytes, filename: str
) -> tuple[str, float, dict[str, Any]]:
    if not DEEPGRAM_KEY:
        return "[no key]", -1.0, {"error": "DEEPGRAM_API_KEY missing"}

    start = time.perf_counter()
    resp = await client.post(
        f"https://api.deepgram.com/v1/listen?model={DEEPGRAM_MODEL}&smart_format=true",
        headers={
            "Authorization": f"Token {DEEPGRAM_KEY}",
            "Content-Type": "audio/wav",
        },
        content=wav_data,
        timeout=120,
    )
    elapsed = (time.perf_counter() - start) * 1000
    resp.raise_for_status()
    data = resp.json()
    channels = data.get("results", {}).get("channels", [])
    alternatives = channels[0].get("alternatives", []) if channels else []
    text = alternatives[0].get("transcript", "") if alternatives else ""
    metadata = data.get("metadata", {})
    return text, elapsed, {"response_id": metadata.get("request_id")}


async def run_provider(
    client: httpx.AsyncClient,
    provider: str,
    wav_data: bytes,
    filename: str,
    iterations: int,
) -> dict[str, Any]:
    funcs = {
        PROVIDER_INTERFAZE: stt_interfaze,
        PROVIDER_INTERFAZE_RUN_TASK: stt_interfaze_run_task,
        PROVIDER_GROQ: stt_groq,
        PROVIDER_ELEVENLABS: stt_elevenlabs,
        PROVIDER_DEEPGRAM: stt_deepgram,
    }
    func = funcs[provider]
    attempts: list[dict[str, Any]] = []
    latest_text = ""

    for iteration in range(iterations):
        try:
            text, latency_ms, meta = await func(client, wav_data, filename)
            if latency_ms >= 0:
                latest_text = text
            attempts.append(
                {
                    "iteration": iteration + 1,
                    "latency_ms": round(latency_ms, 1),
                    "text": text,
                    "error": meta.get("error"),
                    "meta": {k: v for k, v in meta.items() if k != "error"},
                }
            )
        except Exception as exc:
            attempts.append(
                {
                    "iteration": iteration + 1,
                    "latency_ms": -1.0,
                    "text": "",
                    "error": str(exc),
                    "meta": {},
                }
            )
            break

    successful = [a for a in attempts if a["latency_ms"] >= 0 and not a.get("error")]
    latencies = [a["latency_ms"] for a in successful]
    avg_ms = sum(latencies) / len(latencies) if latencies else -1.0
    return {
        "provider": provider,
        "model": provider_model(provider),
        "runs": len(successful),
        "avg_ms": round(avg_ms, 1),
        "text": latest_text,
        "attempts": attempts,
    }


def anonymized_assignment(seed: str, filename: str) -> dict[str, str]:
    rng = random.Random(f"{seed}:{filename}")
    providers = PROVIDERS[:]
    rng.shuffle(providers)
    labels = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    return {labels[i]: provider for i, provider in enumerate(providers)}


def judge_prompt(
    transcripts_by_label: dict[str, str],
    historical_text: str | None,
    mode: str,
) -> str:
    reference_note = ""
    if historical_text:
        reference_note = (
            "\nHistorical app transcript, for context only. It may be biased toward the app's "
            "current Groq engine and is not authoritative ground truth:\n"
            f"{historical_text}\n"
        )

    if mode == "audio":
        intro = "Listen to the attached WAV. Compare each transcript against the audio."
    else:
        intro = (
            "Compare each transcript against the historical app transcript. "
            "The reference may be biased, so only mark material differences that are clear."
        )

    transcript_blocks = "\n\n".join(
        f"Transcript {label}:\n{text}" for label, text in transcripts_by_label.items()
    )
    label_options = "|".join([*transcripts_by_label.keys(), "tie"])
    scores_shape = ", ".join(f'"{label}": 0' for label in transcripts_by_label)
    list_shape = ", ".join(f'"{label}": []' for label in transcripts_by_label)
    change_shape = ", ".join(f'"{label}": "none"' for label in transcripts_by_label)

    return f"""{intro}

{transcript_blocks}
{reference_note}
Return strict JSON only with this shape:
{{
  "winner": "{label_options}",
  "scores": {{{scores_shape}}},
  "confidence": 0.0,
  "missing_words": {{{list_shape}}},
  "extra_words": {{{list_shape}}},
  "changed_words": {{{list_shape}}},
  "material_meaning_changes": {{{change_shape}}},
  "notes": "short explanation"
}}

Scoring guidance: 10 means the transcript matches the speech/reference with only punctuation differences.
Focus on dictated words, proper nouns, numbers, negations, inserted content, and omitted content."""


def normalize_judgment(raw: Any, assignment: dict[str, str], mode: str) -> dict[str, Any]:
    if not isinstance(raw, dict):
        raw = {}

    winner_label = str(raw.get("winner", "tie")).strip().upper()
    valid_labels = set(assignment.keys())
    if winner_label not in valid_labels | {"TIE"}:
        winner_label = "TIE"

    raw_scores = raw.get("scores")
    if not isinstance(raw_scores, dict):
        raw_scores = {
            label: raw.get(f"{label.lower()}_score") for label in assignment
        }
    provider_scores = {
        provider: coerce_float(raw_scores.get(label), 0.0)
        for label, provider in assignment.items()
    }
    confidence = min(max(coerce_float(raw.get("confidence"), 0.0), 0.0), 1.0)

    winner_provider = "tie" if winner_label == "TIE" else assignment[winner_label]
    return {
        "judge_mode": mode,
        "winner_label": winner_label.lower(),
        "winner_provider": winner_provider,
        "provider_scores": provider_scores,
        "confidence": confidence,
        "missing_words": remap_label_dict(raw.get("missing_words"), assignment),
        "extra_words": remap_label_dict(raw.get("extra_words"), assignment),
        "changed_words": remap_label_dict(raw.get("changed_words"), assignment),
        "material_meaning_changes": remap_label_dict(
            raw.get("material_meaning_changes"), assignment
        ),
        "notes": str(raw.get("notes", "")).strip(),
        "labels": assignment,
        "raw": raw,
    }


def coerce_float(value: Any, default: float) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def remap_label_dict(value: Any, assignment: dict[str, str]) -> dict[str, Any]:
    if not isinstance(value, dict):
        return {provider: [] for provider in PROVIDERS}
    return {provider: value.get(label, []) for label, provider in assignment.items()}


async def judge_audio(
    client: httpx.AsyncClient,
    wav_data: bytes,
    assignment: dict[str, str],
    provider_results: dict[str, dict[str, Any]],
    historical_text: str | None,
) -> dict[str, Any]:
    if not OPENAI_KEY:
        raise RuntimeError("OPENAI_API_KEY missing")

    prompt = judge_prompt(
        {
            label: provider_results[provider]["text"]
            for label, provider in assignment.items()
        },
        historical_text,
        mode="audio",
    )
    encoded_wav = base64.b64encode(wav_data).decode("ascii")
    payload = {
        "model": OPENAI_AUDIO_JUDGE_MODEL,
        "modalities": ["text"],
        "messages": [
            {
                "role": "system",
                "content": "You are an expert transcription quality judge. Output JSON only.",
            },
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": prompt},
                    {
                        "type": "input_audio",
                        "input_audio": {"data": encoded_wav, "format": "wav"},
                    },
                ],
            },
        ],
        "temperature": 0,
        "max_completion_tokens": 1500,
    }
    resp = await client.post(
        "https://api.openai.com/v1/chat/completions",
        headers={
            "Authorization": f"Bearer {OPENAI_KEY}",
            "Content-Type": "application/json",
        },
        json=payload,
        timeout=180,
    )
    resp.raise_for_status()
    data = resp.json()
    content = data["choices"][0]["message"].get("content", "")
    parsed = first_json_object(content)
    if parsed is None:
        raise RuntimeError(f"Audio judge returned non-JSON content: {content[:300]}")
    return normalize_judgment(parsed, assignment, "audio")


async def judge_text_reference(
    client: httpx.AsyncClient,
    assignment: dict[str, str],
    provider_results: dict[str, dict[str, Any]],
    historical_text: str | None,
    mode: str,
) -> dict[str, Any]:
    if not OPENAI_KEY:
        raise RuntimeError("OPENAI_API_KEY missing")
    if not historical_text:
        raise RuntimeError("historical transcript missing")

    prompt = judge_prompt(
        {
            label: provider_results[provider]["text"]
            for label, provider in assignment.items()
        },
        historical_text,
        mode="text_reference",
    )
    resp = await client.post(
        "https://api.openai.com/v1/chat/completions",
        headers={
            "Authorization": f"Bearer {OPENAI_KEY}",
            "Content-Type": "application/json",
        },
        json={
            "model": OPENAI_TEXT_JUDGE_MODEL,
            "messages": [
                {
                    "role": "system",
                    "content": "You are an expert transcription quality judge. Output JSON only.",
                },
                {"role": "user", "content": prompt},
            ],
            "temperature": 0,
            "response_format": {"type": "json_object"},
            "max_completion_tokens": 1500,
        },
        timeout=60,
    )
    resp.raise_for_status()
    data = resp.json()
    content = data["choices"][0]["message"].get("content", "")
    parsed = first_json_object(content)
    if parsed is None:
        raise RuntimeError(f"Text judge returned non-JSON content: {content[:300]}")
    return normalize_judgment(parsed, assignment, mode)


async def judge_transcripts(
    client: httpx.AsyncClient,
    judge_mode: str,
    wav_data: bytes,
    assignment: dict[str, str],
    provider_results: dict[str, dict[str, Any]],
    historical_text: str | None,
) -> dict[str, Any] | None:
    if judge_mode == "none":
        return None

    missing = [p for p in PROVIDERS if not provider_results[p].get("text")]
    if missing:
        return {"judge_mode": "skipped", "error": f"missing transcript(s): {', '.join(missing)}"}

    if judge_mode == "audio":
        try:
            return await judge_audio(
                client, wav_data, assignment, provider_results, historical_text
            )
        except Exception as exc:
            try:
                fallback = await judge_text_reference(
                    client,
                    assignment,
                    provider_results,
                    historical_text,
                    mode="text_reference_fallback",
                )
                fallback["audio_judge_error"] = str(exc)
                return fallback
            except Exception as fallback_exc:
                return {
                    "judge_mode": "failed",
                    "audio_judge_error": str(exc),
                    "fallback_error": str(fallback_exc),
                }

    try:
        return await judge_text_reference(
            client,
            assignment,
            provider_results,
            historical_text,
            mode="text_reference",
        )
    except Exception as exc:
        return {"judge_mode": "failed", "error": str(exc)}


async def benchmark_file(
    client: httpx.AsyncClient,
    wav_path: Path,
    iterations: int,
    judge_mode: str,
    run_seed: str,
) -> dict[str, Any]:
    wav_data = audio_io.load_as_wav_bytes(wav_path)
    duration = wav_audio_duration(wav_data)
    historical_text = read_text_if_exists(wav_path.with_suffix(".txt"))

    # Providers receive plain WAV bytes regardless of the on-disk container, so
    # give them a filename with a matching .wav extension.
    upload_filename = wav_path.with_suffix(".wav").name

    console.print(f"\n[bold]{wav_path.name}[/bold] ({duration:.1f}s)")
    provider_entries = await asyncio.gather(
        *[
            run_provider(client, provider, wav_data, upload_filename, iterations)
            for provider in PROVIDERS
        ]
    )
    provider_results = {entry["provider"]: entry for entry in provider_entries}
    for provider in PROVIDERS:
        entry = provider_results[provider]
        latency = f"{entry['avg_ms']:.0f}ms" if entry["avg_ms"] >= 0 else "error"
        chars = len(entry.get("text") or "")
        console.print(f"  {provider}: {latency}, {chars} chars")

    assignment = anonymized_assignment(run_seed, wav_path.name)
    judgment = await judge_transcripts(
        client,
        judge_mode,
        wav_data,
        assignment,
        provider_results,
        historical_text,
    )
    if judgment:
        winner = judgment.get("winner_provider", judgment.get("judge_mode", "unknown"))
        console.print(f"  Judge: {judgment.get('judge_mode')} winner={winner}")

    return {
        "file": wav_path.name,
        "path": str(wav_path),
        "audio_duration_s": round(duration, 1),
        "audio_bytes": len(wav_data),
        "historical_transcript": historical_text,
        "historical_transcript_chars": len(historical_text or ""),
        "providers": provider_results,
        "judge": judgment,
    }


async def add_missing_providers(
    client: httpx.AsyncClient,
    result: dict[str, Any],
    iterations: int,
) -> dict[str, Any]:
    wav_path = Path(result["path"]).expanduser()
    if not wav_path.exists():
        # The background WAV->Opus migration may have renamed this recording
        # (e.g. .wav -> .caf) since the source JSON was written.
        sibling = audio_io.find_sibling_recording(wav_path)
        if sibling is not None:
            wav_path = sibling
    wav_data = audio_io.load_as_wav_bytes(wav_path)
    upload_filename = wav_path.with_suffix(".wav").name
    provider_results = result.setdefault("providers", {})

    console.print(f"\n[bold]{result['file']}[/bold] ({result['audio_duration_s']:.1f}s)")
    for provider in PROVIDERS:
        existing = provider_results.get(provider)
        if existing and existing.get("avg_ms", -1) >= 0 and existing.get("text"):
            console.print(f"  {provider}: reused, {len(existing.get('text') or '')} chars")
            continue

        entry = await run_provider(client, provider, wav_data, upload_filename, iterations)
        provider_results[provider] = entry
        latency = f"{entry['avg_ms']:.0f}ms" if entry["avg_ms"] >= 0 else "error"
        console.print(f"  {provider}: {latency}, {len(entry.get('text') or '')} chars")

    return result


async def rejudge_result(
    client: httpx.AsyncClient,
    result: dict[str, Any],
    judge_mode: str,
    run_seed: str,
) -> dict[str, Any]:
    if judge_mode == "none":
        result["judge"] = None
        return result

    wav_path = Path(result["path"]).expanduser()
    if not wav_path.exists():
        sibling = audio_io.find_sibling_recording(wav_path)
        if sibling is not None:
            wav_path = sibling
    wav_data = audio_io.load_as_wav_bytes(wav_path)
    assignment = anonymized_assignment(run_seed, result["file"])
    judgment = await judge_transcripts(
        client,
        judge_mode,
        wav_data,
        assignment,
        result["providers"],
        result.get("historical_transcript"),
    )
    result["judge"] = judgment
    if judgment:
        winner = judgment.get("winner_provider", judgment.get("judge_mode", "unknown"))
        console.print(f"  Judge: {judgment.get('judge_mode')} winner={winner}")
    return result


def select_wav_files(args: argparse.Namespace) -> list[Path]:
    if args.file:
        files = [args.file.expanduser()]
    else:
        directory = (args.dir or DEFAULT_RECORDINGS_DIR).expanduser()
        files = audio_io.list_recordings(directory)
        if args.last and args.last > 0:
            files = files[-args.last :]
    return [p for p in files if p.exists()]


def percentile(values: list[float], pct: float) -> float:
    if not values:
        return -1.0
    ordered = sorted(values)
    index = (len(ordered) - 1) * pct
    lower = math.floor(index)
    upper = math.ceil(index)
    if lower == upper:
        return ordered[int(index)]
    weight = index - lower
    return ordered[lower] * (1 - weight) + ordered[upper] * weight


def summarize(results: list[dict[str, Any]]) -> dict[str, Any]:
    provider_summary: dict[str, dict[str, Any]] = {}
    for provider in PROVIDERS:
        latencies = [
            r["providers"][provider]["avg_ms"]
            for r in results
            if r["providers"][provider]["avg_ms"] >= 0
        ]
        provider_summary[provider] = {
            "model": provider_model(provider),
            "successes": len(latencies),
            "success_rate": round(len(latencies) / len(results), 3) if results else 0.0,
            "median_ms": round(percentile(latencies, 0.5), 1),
            "p95_ms": round(percentile(latencies, 0.95), 1),
            "min_ms": round(min(latencies), 1) if latencies else -1.0,
            "max_ms": round(max(latencies), 1) if latencies else -1.0,
        }

    win_counts = {provider: 0 for provider in PROVIDERS}
    win_counts.update({"tie": 0, "skipped": 0})
    judge_modes: dict[str, int] = {}
    for result in results:
        judge = result.get("judge") or {}
        mode = judge.get("judge_mode", "none")
        judge_modes[mode] = judge_modes.get(mode, 0) + 1
        winner = judge.get("winner_provider")
        if winner in win_counts:
            win_counts[winner] += 1
        elif mode == "none":
            continue
        else:
            win_counts["skipped"] += 1

    durations = [r["audio_duration_s"] for r in results]
    return {
        "files": len(results),
        "total_audio_duration_s": round(sum(durations), 1),
        "min_audio_duration_s": round(min(durations), 1) if durations else 0.0,
        "max_audio_duration_s": round(max(durations), 1) if durations else 0.0,
        "avg_audio_duration_s": round(sum(durations) / len(durations), 1) if durations else 0.0,
        "providers": provider_summary,
        "judge_win_counts": win_counts,
        "judge_modes": judge_modes,
    }


def divergence_score(result: dict[str, Any]) -> float:
    judge = result.get("judge") or {}
    scores = judge.get("provider_scores") or {}
    if len(scores) < 2:
        return -1.0
    vals = [coerce_float(v, 0.0) for v in scores.values()]
    return max(vals) - min(vals)


def markdown_table(headers: list[str], rows: list[list[str]]) -> str:
    lines = [
        "| " + " | ".join(headers) + " |",
        "| " + " | ".join("---" for _ in headers) + " |",
    ]
    for row in rows:
        lines.append("| " + " | ".join(cell.replace("\n", " ") for cell in row) + " |")
    return "\n".join(lines)


def truncate(text: Any, limit: int = 90) -> str:
    value = str(text or "").strip().replace("\n", " ")
    if len(value) <= limit:
        return value
    return value[: limit - 3] + "..."


def write_report(
    results: list[dict[str, Any]],
    summary: dict[str, Any],
    json_path: Path,
    reports_dir: Path,
    judge_mode: str,
) -> Path:
    reports_dir.mkdir(parents=True, exist_ok=True)
    report_path = reports_dir / f"stt-provider-benchmark-{datetime.now().date()}.md"

    provider_rows = []
    for provider in PROVIDERS:
        data = summary["providers"][provider]
        provider_rows.append(
            [
                provider,
                data["model"],
                f"{data['successes']}/{summary['files']}",
                f"{data['median_ms']:.0f}",
                f"{data['p95_ms']:.0f}",
                f"{data['min_ms']:.0f}",
                f"{data['max_ms']:.0f}",
            ]
        )

    win_counts = summary["judge_win_counts"]
    win_rows = [[f"{provider} wins", str(win_counts[provider])] for provider in PROVIDERS]
    win_rows.extend(
        [
            ["Ties", str(win_counts["tie"])],
            ["Skipped/failed", str(win_counts["skipped"])],
        ]
    )

    worst_rows = []
    score_headers = [provider.replace(" STT", "").replace(" Whisper", "").replace(" Scribe", "") for provider in PROVIDERS]
    for result in sorted(results, key=divergence_score, reverse=True)[:10]:
        judge = result.get("judge") or {}
        scores = judge.get("provider_scores") or {}
        changes = judge.get("material_meaning_changes") or {}
        material_changes = [
            changes.get(provider)
            for provider in PROVIDERS
            if changes.get(provider) and changes.get(provider) != "none"
        ]
        worst_rows.append(
            [
                result["file"],
                f"{result['audio_duration_s']:.1f}",
                str(judge.get("winner_provider", "")),
                *[f"{coerce_float(scores.get(provider), 0):.1f}" for provider in PROVIDERS],
                truncate("; ".join(str(change) for change in material_changes) or "none", 100),
            ]
        )

    report = f"""# STT Provider Benchmark

Generated: {datetime.now().isoformat(timespec="seconds")}

## Summary

- Files: {summary["files"]}
- Total audio: {summary["total_audio_duration_s"]:.1f}s
- Audio range: {summary["min_audio_duration_s"]:.1f}s to {summary["max_audio_duration_s"]:.1f}s
- Judge requested: `{judge_mode}`
- Judge modes observed: `{summary["judge_modes"]}`
- Raw JSON: `{json_path}`

Saved `.txt` files are included as historical app transcripts only. They should not be treated as unbiased ground truth.

## Latency

{markdown_table(["Provider", "Model", "Success", "Median ms", "p95 ms", "Min ms", "Max ms"], provider_rows)}

## Judge Wins

{markdown_table(["Outcome", "Count"], win_rows)}

## Largest Judged Divergences

{markdown_table(["File", "Audio s", "Winner", *score_headers, "Material change"], worst_rows)}
"""

    report_path.write_text(report, encoding="utf-8")
    return report_path


def write_result_files(
    payload: dict[str, Any],
    output_dir: Path,
    prefix: str,
    reports_dir: Path,
    judge_mode: str,
) -> tuple[Path, Path, Path]:
    output_dir.mkdir(parents=True, exist_ok=True)
    timestamp = payload["timestamp"]
    json_path = output_dir / f"{prefix}_{timestamp}.json"
    raw_path = output_dir / "raw.json"
    json_text = json.dumps(payload, indent=2)
    json_path.write_text(json_text, encoding="utf-8")
    raw_path.write_text(json_text, encoding="utf-8")
    report_path = write_report(payload["results"], payload["summary"], json_path, reports_dir, judge_mode)
    return json_path, raw_path, report_path


def print_summary(summary: dict[str, Any]) -> None:
    table = Table(title="Latency Summary")
    table.add_column("Provider", style="cyan")
    table.add_column("Success", justify="right")
    table.add_column("Median ms", justify="right")
    table.add_column("p95 ms", justify="right")
    table.add_column("Min ms", justify="right")
    table.add_column("Max ms", justify="right")

    for provider in PROVIDERS:
        data = summary["providers"][provider]
        table.add_row(
            provider,
            f"{data['successes']}/{summary['files']}",
            f"{data['median_ms']:.0f}",
            f"{data['p95_ms']:.0f}",
            f"{data['min_ms']:.0f}",
            f"{data['max_ms']:.0f}",
        )
    console.print(table)

    wins = summary["judge_win_counts"]
    console.print(
        "[bold]Judge wins:[/bold] "
        +
        ", ".join(f"{provider}={wins[provider]}" for provider in PROVIDERS)
        + f", tie={wins['tie']}, skipped={wins['skipped']}"
    )


async def run_from_json(args: argparse.Namespace) -> int:
    source_path = args.from_json.expanduser()
    source = json.loads(source_path.read_text(encoding="utf-8"))
    results = source.get("results", [])
    if not results:
        console.print(f"[red]No results found in {source_path}[/red]")
        return 1

    console.print("[bold]API Keys:[/bold]")
    for name, key in [
        ("Interfaze", INTERFAZE_KEY),
        ("Groq", GROQ_KEY),
        ("ElevenLabs", ELEVENLABS_KEY),
        ("Deepgram", DEEPGRAM_KEY),
        ("OpenAI", OPENAI_KEY),
    ]:
        status = "[green]configured[/green]" if key else "[red]missing[/red]"
        console.print(f"  {name}: {status}")

    run_seed = source.get("run_seed") or secrets.token_hex(8)
    console.print(
        f"\nReusing {len(results)} result(s) from {source_path}; adding missing providers and judge={args.judge}"
    )

    async with httpx.AsyncClient() as client:
        merged_results: list[dict[str, Any]] = []
        for result in results:
            result = await add_missing_providers(client, result, args.iterations)
            result = await rejudge_result(client, result, args.judge, run_seed)
            merged_results.append(result)

    timestamp = datetime.now().strftime("%Y-%m-%d_%H%M%S")
    payload = {
        "timestamp": timestamp,
        "source_json": str(source_path),
        "run_seed": run_seed,
        "judge_requested": args.judge,
        "recordings": [r["path"] for r in merged_results],
        "summary": summarize(merged_results),
        "results": merged_results,
    }
    json_path, raw_path, report_path = write_result_files(
        payload,
        args.output.expanduser(),
        "stt_providers",
        DEFAULT_REPORTS_DIR,
        args.judge,
    )

    print_summary(payload["summary"])
    console.print(f"\n[green]JSON saved:[/green] {json_path}")
    console.print(f"[green]Raw JSON saved:[/green] {raw_path}")
    console.print(f"[green]Report saved:[/green] {report_path}")
    return 0


async def run(args: argparse.Namespace) -> int:
    if args.from_json:
        return await run_from_json(args)

    wav_files = select_wav_files(args)
    if not wav_files:
        console.print("[red]No WAV files found.[/red]")
        return 1

    console.print("[bold]API Keys:[/bold]")
    for name, key in [
        ("Interfaze", INTERFAZE_KEY),
        ("Groq", GROQ_KEY),
        ("ElevenLabs", ELEVENLABS_KEY),
        ("Deepgram", DEEPGRAM_KEY),
        ("OpenAI", OPENAI_KEY),
    ]:
        status = "[green]configured[/green]" if key else "[red]missing[/red]"
        console.print(f"  {name}: {status}")

    console.print(
        f"\nBenchmarking {len(wav_files)} file(s), iterations={args.iterations}, judge={args.judge}"
    )

    run_seed = secrets.token_hex(8)
    results: list[dict[str, Any]] = []
    async with httpx.AsyncClient() as client:
        for wav_path in wav_files:
            result = await benchmark_file(
                client, wav_path, args.iterations, args.judge, run_seed
            )
            results.append(result)

    summary = summarize(results)
    timestamp = datetime.now().strftime("%Y-%m-%d_%H%M%S")
    payload = {
        "timestamp": timestamp,
        "run_seed": run_seed,
        "judge_requested": args.judge,
        "recordings": [str(p) for p in wav_files],
        "summary": summary,
        "results": results,
    }
    json_path, raw_path, report_path = write_result_files(
        payload,
        args.output.expanduser(),
        "stt_providers",
        DEFAULT_REPORTS_DIR,
        args.judge,
    )

    print_summary(summary)
    console.print(f"\n[green]JSON saved:[/green] {json_path}")
    console.print(f"[green]Raw JSON saved:[/green] {raw_path}")
    console.print(f"[green]Report saved:[/green] {report_path}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="STT provider benchmark")
    parser.add_argument(
        "--from-json",
        type=Path,
        help="Reuse an existing benchmark JSON, add missing providers, and rejudge",
    )
    parser.add_argument("--file", type=Path, help="Single WAV file to benchmark")
    parser.add_argument(
        "--dir",
        type=Path,
        default=DEFAULT_RECORDINGS_DIR,
        help="Directory of WAV files to benchmark",
    )
    parser.add_argument(
        "--last",
        type=int,
        default=50,
        help="Use the newest N WAV files by timestamped filename. Use 0 for all files.",
    )
    parser.add_argument("--iterations", type=int, default=1, help="Runs per provider per file")
    parser.add_argument(
        "--judge",
        choices=["audio", "text-reference", "none"],
        default="audio",
        help="Quality judging mode",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_RESULTS_DIR,
        help="Output directory for benchmark JSON",
    )
    return parser


def main() -> None:
    args = build_parser().parse_args()
    if args.iterations < 1:
        console.print("[red]--iterations must be >= 1[/red]")
        sys.exit(1)
    try:
        raise SystemExit(asyncio.run(run(args)))
    except KeyboardInterrupt:
        console.print("\n[yellow]Interrupted[/yellow]")
        raise SystemExit(130)


if __name__ == "__main__":
    main()
