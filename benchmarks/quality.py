#!/usr/bin/env python3
"""
Mumbli Quality Benchmark — LLM-as-Judge

Compares transcription quality across STT providers using the baseline
(ElevenLabs Scribe) as ground truth. Uses GPT to judge whether alternative
providers preserve meaning, capture nuances, and avoid word changes.

Usage:
    uv run quality.py                           # run on all recordings
    uv run quality.py --file recording.wav      # single file
    uv run quality.py --results results/2026-04-01_141012.json  # use existing benchmark results
"""

import argparse
import asyncio
import json
import os
import sys
import time
from datetime import datetime
from pathlib import Path

import httpx
from dotenv import load_dotenv
from rich.console import Console
from rich.table import Table

console = Console()
load_dotenv()

OPENAI_KEY = os.getenv("OPENAI_API_KEY", "")
ELEVENLABS_KEY = os.getenv("ELEVENLABS_API_KEY", "")
GROQ_KEY = os.getenv("GROQ_API_KEY", "")

DEFAULT_RECORDINGS_DIR = Path.home() / "Library/Application Support/Mumbli/recordings"

# ---------------------------------------------------------------------------
# STT Providers (same as bench.py)
# ---------------------------------------------------------------------------


async def stt_elevenlabs(client: httpx.AsyncClient, wav_data: bytes) -> str:
    if not ELEVENLABS_KEY:
        return ""
    resp = await client.post(
        "https://api.elevenlabs.io/v1/speech-to-text",
        headers={"xi-api-key": ELEVENLABS_KEY},
        files={"file": ("audio.wav", wav_data, "audio/wav")},
        data={"model_id": "scribe_v1"},
        timeout=60,
    )
    resp.raise_for_status()
    return resp.json()["text"]


async def stt_groq(client: httpx.AsyncClient, wav_data: bytes) -> str:
    if not GROQ_KEY:
        return ""
    resp = await client.post(
        "https://api.groq.com/openai/v1/audio/transcriptions",
        headers={"Authorization": f"Bearer {GROQ_KEY}"},
        files={"file": ("audio.wav", wav_data, "audio/wav")},
        data={"model": "whisper-large-v3-turbo"},
        timeout=60,
    )
    resp.raise_for_status()
    return resp.json()["text"]


async def stt_openai(client: httpx.AsyncClient, wav_data: bytes) -> str:
    if not OPENAI_KEY:
        return ""
    resp = await client.post(
        "https://api.openai.com/v1/audio/transcriptions",
        headers={"Authorization": f"Bearer {OPENAI_KEY}"},
        files={"file": ("audio.wav", wav_data, "audio/wav")},
        data={"model": "whisper-1"},
        timeout=60,
    )
    resp.raise_for_status()
    return resp.json()["text"]


# ---------------------------------------------------------------------------
# LLM-as-Judge
# ---------------------------------------------------------------------------

JUDGE_PROMPT = """You are a transcription quality judge. Compare a candidate transcription against the baseline (ground truth) transcription of the same audio.

Evaluate on these criteria:
1. **Meaning preservation** (0-10): Does the candidate preserve the exact meaning? Any changed/missing words that alter intent?
2. **Word accuracy** (0-10): How closely do the words match? Minor punctuation differences are OK.
3. **Nuance capture** (0-10): Does it capture filler words, self-corrections, emotional cues, and speaker intent the same way?
4. **Overall quality** (0-10): Overall transcription quality compared to baseline.

Respond in this exact JSON format:
{
    "meaning_score": <0-10>,
    "word_accuracy": <0-10>,
    "nuance_score": <0-10>,
    "overall_score": <0-10>,
    "changed_words": ["list of words that differ meaningfully"],
    "missing_content": "brief description of any missing content, or 'none'",
    "meaning_changes": "brief description of any meaning changes, or 'none'",
    "notes": "any other observations"
}"""


async def judge_transcription(
    client: httpx.AsyncClient, baseline: str, candidate: str, provider_name: str
) -> dict:
    """Use GPT to judge transcription quality."""
    if not OPENAI_KEY:
        return {"error": "no OpenAI key"}

    resp = await client.post(
        "https://api.openai.com/v1/chat/completions",
        headers={
            "Authorization": f"Bearer {OPENAI_KEY}",
            "Content-Type": "application/json",
        },
        json={
            "model": "gpt-5.4-nano",
            "messages": [
                {"role": "system", "content": JUDGE_PROMPT},
                {"role": "user", "content": f"**Baseline (ElevenLabs Scribe v1):**\n{baseline}\n\n**Candidate ({provider_name}):**\n{candidate}"},
            ],
            "temperature": 0,
            "response_format": {"type": "json_object"},
            "max_completion_tokens": 1024,
        },
        timeout=30,
    )
    resp.raise_for_status()
    content = resp.json()["choices"][0]["message"]["content"]
    try:
        return json.loads(content)
    except json.JSONDecodeError:
        return {"error": f"Failed to parse judge response: {content[:200]}"}


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


async def run_quality_benchmark(wav_files: list[Path]) -> list[dict]:
    results = []

    async with httpx.AsyncClient() as client:
        for wav_path in wav_files:
            wav_data = wav_path.read_bytes()
            duration = (len(wav_data) - 44) / (16000 * 2)
            console.print(f"\n[bold]Quality: {wav_path.name}[/bold] ({duration:.1f}s)")

            # Check for existing baseline transcription
            txt_path = wav_path.with_suffix(".txt")
            if txt_path.exists():
                baseline = txt_path.read_text().strip()
                console.print(f"  Using saved baseline ({len(baseline)} chars)")
            else:
                console.print("  Transcribing baseline (ElevenLabs)...")
                try:
                    baseline = await stt_elevenlabs(client, wav_data)
                except Exception as e:
                    console.print(f"  [red]Baseline error: {e}[/red]")
                    continue

            if not baseline:
                console.print("  [yellow]Empty baseline, skipping[/yellow]")
                continue

            # Transcribe with other providers
            providers = {}
            for name, func in [("Groq Whisper", stt_groq), ("OpenAI Whisper", stt_openai)]:
                try:
                    text = await func(client, wav_data)
                    if text:
                        providers[name] = text
                        console.print(f"  {name}: {len(text)} chars")
                except Exception as e:
                    console.print(f"  [red]{name} error: {e}[/red]")

            # Judge each provider
            for name, candidate in providers.items():
                console.print(f"  Judging {name}...")
                try:
                    judgment = await judge_transcription(client, baseline, candidate, name)
                    results.append({
                        "file": wav_path.name,
                        "audio_duration_s": round(duration, 1),
                        "provider": name,
                        "baseline_text": baseline[:200],
                        "candidate_text": candidate[:200],
                        "judgment": judgment,
                    })
                except Exception as e:
                    console.print(f"  [red]Judge error for {name}: {e}[/red]")

            # Small delay to avoid rate limits
            await asyncio.sleep(0.5)

    return results


def print_quality_table(results: list[dict]):
    table = Table(title="Transcription Quality (LLM-as-Judge, vs ElevenLabs baseline)")
    table.add_column("File", style="dim", max_width=25)
    table.add_column("Provider", style="cyan")
    table.add_column("Meaning", justify="right")
    table.add_column("Words", justify="right")
    table.add_column("Nuance", justify="right")
    table.add_column("Overall", justify="right", style="bold magenta")
    table.add_column("Meaning Changes", max_width=40)

    for r in results:
        j = r.get("judgment", {})
        if "error" in j:
            table.add_row(r["file"][:25], r["provider"], "err", "err", "err", "err", j["error"][:40])
            continue
        table.add_row(
            r["file"][:25],
            r["provider"],
            str(j.get("meaning_score", "?")),
            str(j.get("word_accuracy", "?")),
            str(j.get("nuance_score", "?")),
            str(j.get("overall_score", "?")),
            j.get("meaning_changes", "?")[:40],
        )

    console.print(table)

    # Print averages
    for provider in set(r["provider"] for r in results):
        scores = [r["judgment"] for r in results if r["provider"] == provider and "error" not in r.get("judgment", {})]
        if scores:
            avg_meaning = sum(s.get("meaning_score", 0) for s in scores) / len(scores)
            avg_words = sum(s.get("word_accuracy", 0) for s in scores) / len(scores)
            avg_nuance = sum(s.get("nuance_score", 0) for s in scores) / len(scores)
            avg_overall = sum(s.get("overall_score", 0) for s in scores) / len(scores)
            console.print(f"\n[bold]{provider} averages[/bold]: meaning={avg_meaning:.1f} words={avg_words:.1f} nuance={avg_nuance:.1f} overall={avg_overall:.1f}")


def main():
    parser = argparse.ArgumentParser(description="Mumbli Quality Benchmark")
    parser.add_argument("--file", type=Path, help="Single WAV file")
    parser.add_argument("--dir", type=Path, help="Directory of WAV files")
    parser.add_argument("--max-files", type=int, default=10, help="Max files to process")
    parser.add_argument("--output", type=Path, default=Path(__file__).parent / "results", help="Output dir")
    args = parser.parse_args()

    wav_files: list[Path] = []
    if args.file:
        wav_files = [args.file]
    elif args.dir:
        wav_files = sorted(args.dir.glob("*.wav"))
    else:
        if DEFAULT_RECORDINGS_DIR.exists():
            wav_files = sorted(DEFAULT_RECORDINGS_DIR.glob("*.wav"))

    # Filter to files that have a baseline .txt (ground truth)
    wav_with_baseline = [f for f in wav_files if f.with_suffix(".txt").exists()]
    if wav_with_baseline:
        console.print(f"[bold]Found {len(wav_with_baseline)} recordings with baseline transcriptions[/bold]")
        wav_files = wav_with_baseline[:args.max_files]
    else:
        wav_files = wav_files[:args.max_files]

    if not wav_files:
        console.print("[red]No WAV files found.[/red]")
        sys.exit(1)

    console.print(f"Processing {len(wav_files)} files...")

    results = asyncio.run(run_quality_benchmark(wav_files))
    print_quality_table(results)

    # Save
    args.output.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.now().strftime("%Y-%m-%d_%H%M%S")
    out_file = args.output / f"quality_{timestamp}.json"
    out_file.write_text(json.dumps(results, indent=2))
    console.print(f"\n[green]Results saved to {out_file}[/green]")


if __name__ == "__main__":
    main()
