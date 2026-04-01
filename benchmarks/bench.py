#!/usr/bin/env python3
"""
Mumbli Performance Benchmark Harness

Tests STT and polishing APIs with saved WAV recordings to find the fastest combination.
Also benchmarks optimization techniques: chunked parallel STT, regex filler removal,
and combined pipeline simulations.

Usage:
    uv run bench.py --file recording.wav                    # benchmark all providers
    uv run bench.py --dir ~/Library/Application\ Support/Mumbli/recordings/
    uv run bench.py --file recording.wav --stt-only         # skip polishing
    uv run bench.py --file recording.wav --polish-only --text "some text"
    uv run bench.py --file recording.wav --iterations 3     # average over N runs
"""

import argparse
import asyncio
import json
import os
import re
import sys
import time
from datetime import datetime
from pathlib import Path

import httpx
from dotenv import load_dotenv
from rich.console import Console
from rich.table import Table

console = Console()

# ---------------------------------------------------------------------------
# API Keys
# ---------------------------------------------------------------------------

load_dotenv()

ELEVENLABS_KEY = os.getenv("ELEVENLABS_API_KEY", "")
OPENAI_KEY = os.getenv("OPENAI_API_KEY", "")
GROQ_KEY = os.getenv("GROQ_API_KEY", "")
DEEPGRAM_KEY = os.getenv("DEEPGRAM_API_KEY", "")

# ---------------------------------------------------------------------------
# WAV Utilities
# ---------------------------------------------------------------------------


def wav_audio_duration(wav_data: bytes) -> float:
    """Calculate audio duration from WAV data (assumes 16-bit 16kHz mono)."""
    return (len(wav_data) - 44) / (16000 * 2)


def split_wav_chunks(wav_data: bytes, chunk_sec: float = 10.0, overlap_sec: float = 2.0) -> list[bytes]:
    """Split WAV data into overlapping chunks, each with a proper WAV header."""
    pcm = wav_data[44:]  # strip header
    bytes_per_sec = 16000 * 2  # 16kHz 16-bit mono
    chunk_bytes = int(chunk_sec * bytes_per_sec)
    overlap_bytes = int(overlap_sec * bytes_per_sec)
    stride = chunk_bytes - overlap_bytes

    chunks = []
    offset = 0
    while offset < len(pcm):
        end = min(offset + chunk_bytes, len(pcm))
        chunk_pcm = pcm[offset:end]
        # Add WAV header
        chunks.append(_make_wav(chunk_pcm))
        offset += stride
        if end >= len(pcm):
            break

    return chunks


def _make_wav(pcm: bytes, sample_rate: int = 16000, channels: int = 1, bits: int = 16) -> bytes:
    """Create a WAV file from raw PCM data."""
    import struct
    byte_rate = sample_rate * channels * (bits // 8)
    block_align = channels * (bits // 8)
    data_size = len(pcm)
    header = struct.pack(
        '<4sI4s4sIHHIIHH4sI',
        b'RIFF', 36 + data_size, b'WAVE',
        b'fmt ', 16, 1, channels, sample_rate, byte_rate, block_align, bits,
        b'data', data_size,
    )
    return header + pcm


# ---------------------------------------------------------------------------
# STT Providers
# ---------------------------------------------------------------------------


async def stt_elevenlabs(client: httpx.AsyncClient, wav_data: bytes) -> tuple[str, float]:
    """ElevenLabs Scribe v1. Returns (text, latency_ms)."""
    if not ELEVENLABS_KEY:
        return "[no key]", -1
    start = time.perf_counter()
    resp = await client.post(
        "https://api.elevenlabs.io/v1/speech-to-text",
        headers={"xi-api-key": ELEVENLABS_KEY},
        files={"file": ("audio.wav", wav_data, "audio/wav")},
        data={"model_id": "scribe_v1"},
        timeout=60,
    )
    elapsed = (time.perf_counter() - start) * 1000
    resp.raise_for_status()
    return resp.json()["text"], elapsed


async def stt_groq_whisper(client: httpx.AsyncClient, wav_data: bytes) -> tuple[str, float]:
    """Groq Whisper large-v3-turbo."""
    if not GROQ_KEY:
        return "[no key]", -1
    start = time.perf_counter()
    resp = await client.post(
        "https://api.groq.com/openai/v1/audio/transcriptions",
        headers={"Authorization": f"Bearer {GROQ_KEY}"},
        files={"file": ("audio.wav", wav_data, "audio/wav")},
        data={"model": "whisper-large-v3-turbo"},
        timeout=60,
    )
    elapsed = (time.perf_counter() - start) * 1000
    resp.raise_for_status()
    return resp.json()["text"], elapsed


async def stt_openai_whisper(client: httpx.AsyncClient, wav_data: bytes) -> tuple[str, float]:
    """OpenAI Whisper-1."""
    if not OPENAI_KEY:
        return "[no key]", -1
    start = time.perf_counter()
    resp = await client.post(
        "https://api.openai.com/v1/audio/transcriptions",
        headers={"Authorization": f"Bearer {OPENAI_KEY}"},
        files={"file": ("audio.wav", wav_data, "audio/wav")},
        data={"model": "whisper-1"},
        timeout=60,
    )
    elapsed = (time.perf_counter() - start) * 1000
    resp.raise_for_status()
    return resp.json()["text"], elapsed


async def stt_deepgram(client: httpx.AsyncClient, wav_data: bytes) -> tuple[str, float]:
    """Deepgram Nova-2."""
    if not DEEPGRAM_KEY:
        return "[no key]", -1
    start = time.perf_counter()
    resp = await client.post(
        "https://api.deepgram.com/v1/listen?model=nova-2&smart_format=true",
        headers={
            "Authorization": f"Token {DEEPGRAM_KEY}",
            "Content-Type": "audio/wav",
        },
        content=wav_data,
        timeout=60,
    )
    elapsed = (time.perf_counter() - start) * 1000
    resp.raise_for_status()
    data = resp.json()
    text = data["results"]["channels"][0]["alternatives"][0]["transcript"]
    return text, elapsed


STT_PROVIDERS = {
    "ElevenLabs Scribe": stt_elevenlabs,
    "Groq Whisper": stt_groq_whisper,
    "OpenAI Whisper": stt_openai_whisper,
    "Deepgram Nova-2": stt_deepgram,
}

# ---------------------------------------------------------------------------
# Chunked Parallel STT
# ---------------------------------------------------------------------------


def _stitch_transcripts(texts: list[str]) -> str:
    """Stitch overlapping chunk transcriptions using word-level overlap detection."""
    if not texts:
        return ""
    result = texts[0]
    for i in range(1, len(texts)):
        prev_words = result.split()
        next_words = texts[i].split()
        if not prev_words or not next_words:
            result = (result + " " + texts[i]).strip()
            continue

        # Look for longest common run between tail of prev and head of next
        search_window = min(15, len(prev_words), len(next_words))
        best_len = 0
        best_prev_start = len(prev_words)

        for p_start in range(len(prev_words) - search_window, len(prev_words)):
            for n_start in range(search_window):
                run = 0
                while (p_start + run < len(prev_words)
                       and n_start + run < len(next_words)
                       and prev_words[p_start + run].lower().strip(".,!?;:") ==
                           next_words[n_start + run].lower().strip(".,!?;:")):
                    run += 1
                if run >= 2 and run > best_len:
                    best_len = run
                    best_prev_start = p_start

        if best_len >= 2:
            # Merge: keep prev up to overlap, skip overlap in next
            merged_prev = " ".join(prev_words[:best_prev_start + best_len])
            # Find where in next_words the overlap ends
            for n_start in range(search_window):
                run = 0
                while (best_prev_start + run < len(prev_words)
                       and n_start + run < len(next_words)
                       and prev_words[best_prev_start + run].lower().strip(".,!?;:") ==
                           next_words[n_start + run].lower().strip(".,!?;:")):
                    run += 1
                if run == best_len:
                    remaining = next_words[n_start + best_len:]
                    result = merged_prev + (" " + " ".join(remaining) if remaining else "")
                    break
            else:
                result = result + " " + texts[i]
        else:
            # No overlap found, concatenate
            result = result + " " + texts[i]

    return result.strip()


async def stt_chunked_parallel(
    client: httpx.AsyncClient,
    wav_data: bytes,
    stt_func,
    chunk_sec: float = 10.0,
    overlap_sec: float = 2.0,
) -> tuple[str, float]:
    """Split audio into overlapping chunks, transcribe in parallel, stitch results."""
    chunks = split_wav_chunks(wav_data, chunk_sec, overlap_sec)
    if len(chunks) <= 1:
        return await stt_func(client, wav_data)

    start = time.perf_counter()
    tasks = [stt_func(client, chunk) for chunk in chunks]
    results = await asyncio.gather(*tasks, return_exceptions=True)
    elapsed = (time.perf_counter() - start) * 1000

    texts = []
    for r in results:
        if isinstance(r, Exception):
            texts.append("")
        else:
            texts.append(r[0])

    stitched = _stitch_transcripts(texts)
    return stitched, elapsed


# ---------------------------------------------------------------------------
# Polishing Providers
# ---------------------------------------------------------------------------

POLISH_PROMPT = (
    "Clean up this dictated text minimally: remove filler words (um, uh, like, you know), "
    "fix typos, and add punctuation. Keep the content and wording exactly as spoken otherwise. "
    "Output only the cleaned text, nothing else."
)

POLISH_PROMPT_SHORT = "Remove filler words, fix punctuation. Output only cleaned text."


async def polish_openai(
    client: httpx.AsyncClient, text: str, model: str = "gpt-5.4-nano"
) -> tuple[str, float]:
    """OpenAI chat completions polishing."""
    if not OPENAI_KEY:
        return "[no key]", -1
    start = time.perf_counter()
    resp = await client.post(
        "https://api.openai.com/v1/chat/completions",
        headers={
            "Authorization": f"Bearer {OPENAI_KEY}",
            "Content-Type": "application/json",
        },
        json={
            "model": model,
            "messages": [
                {"role": "system", "content": POLISH_PROMPT},
                {"role": "user", "content": text},
            ],
            "temperature": 0.3,
            "max_completion_tokens": 2048,
        },
        timeout=30,
    )
    elapsed = (time.perf_counter() - start) * 1000
    resp.raise_for_status()
    return resp.json()["choices"][0]["message"]["content"], elapsed


async def polish_openai_short_prompt(
    client: httpx.AsyncClient, text: str, model: str = "gpt-5.4-nano"
) -> tuple[str, float]:
    """OpenAI with minimal prompt (fewer input tokens)."""
    if not OPENAI_KEY:
        return "[no key]", -1
    start = time.perf_counter()
    resp = await client.post(
        "https://api.openai.com/v1/chat/completions",
        headers={
            "Authorization": f"Bearer {OPENAI_KEY}",
            "Content-Type": "application/json",
        },
        json={
            "model": model,
            "messages": [
                {"role": "system", "content": POLISH_PROMPT_SHORT},
                {"role": "user", "content": text},
            ],
            "temperature": 0,
            "max_completion_tokens": 512,
        },
        timeout=30,
    )
    elapsed = (time.perf_counter() - start) * 1000
    resp.raise_for_status()
    return resp.json()["choices"][0]["message"]["content"], elapsed


async def polish_groq(
    client: httpx.AsyncClient, text: str, model: str = "llama-3.3-70b-versatile"
) -> tuple[str, float]:
    """Groq LLM polishing (OpenAI-compatible)."""
    if not GROQ_KEY:
        return "[no key]", -1
    start = time.perf_counter()
    resp = await client.post(
        "https://api.groq.com/openai/v1/chat/completions",
        headers={
            "Authorization": f"Bearer {GROQ_KEY}",
            "Content-Type": "application/json",
        },
        json={
            "model": model,
            "messages": [
                {"role": "system", "content": POLISH_PROMPT},
                {"role": "user", "content": text},
            ],
            "temperature": 0.3,
            "max_tokens": 2048,
        },
        timeout=30,
    )
    elapsed = (time.perf_counter() - start) * 1000
    resp.raise_for_status()
    return resp.json()["choices"][0]["message"]["content"], elapsed


def polish_regex(text: str) -> tuple[str, float]:
    """Regex-based filler word removal. No API call — instant."""
    start = time.perf_counter()
    cleaned = text
    # Remove filler words (case-insensitive, word-boundary aware)
    fillers = [
        r'\b[Uu]m\b[,.]?\s*',
        r'\b[Uu]h\b[,.]?\s*',
        r'\b[Ll]ike\b,\s*',
        r'\b[Yy]ou know\b[,.]?\s*',
        r'\b[Ii] mean\b,\s*',
        r'\b[Bb]asically\b,\s*',
        r'\b[Aa]ctually\b,\s*',
        r'\b[Ss]o\b,\s+(?=[a-z])',
        r'\b[Rr]ight\b[,?]\s*(?=[a-z])',
        r'\b[Hh]mm\b[,.]?\s*',
        r'\b[Bb]lah\b(?:,?\s*\bblah\b)*[,.]?\s*',
    ]
    for pattern in fillers:
        cleaned = re.sub(pattern, '', cleaned)
    # Collapse multiple spaces, fix spacing around punctuation
    cleaned = re.sub(r'\s{2,}', ' ', cleaned)
    cleaned = re.sub(r'\s+([.,!?;:])', r'\1', cleaned)
    # Capitalize after sentence-ending punctuation
    cleaned = re.sub(r'([.!?]\s+)(\w)', lambda m: m.group(1) + m.group(2).upper(), cleaned)
    # Capitalize first character
    cleaned = cleaned.strip()
    if cleaned:
        cleaned = cleaned[0].upper() + cleaned[1:]
    elapsed = (time.perf_counter() - start) * 1000
    return cleaned, elapsed


POLISH_CONFIGS = {
    "OpenAI gpt-5.4-nano": lambda c, t: polish_openai(c, t, "gpt-5.4-nano"),
    "OpenAI gpt-5.4-mini": lambda c, t: polish_openai(c, t, "gpt-5.4-mini"),
    "OpenAI nano (short prompt)": lambda c, t: polish_openai_short_prompt(c, t, "gpt-5.4-nano"),
    "Groq llama-3.3-70b": lambda c, t: polish_groq(c, t, "llama-3.3-70b-versatile"),
    "Groq llama-3.1-8b": lambda c, t: polish_groq(c, t, "llama-3.1-8b-instant"),
    "Regex (no API)": lambda c, t: asyncio.coroutine(lambda: polish_regex(t))() if False else polish_regex(t),
}

# ---------------------------------------------------------------------------
# Benchmark Runners
# ---------------------------------------------------------------------------


async def benchmark_stt(wav_files: list[Path], iterations: int) -> list[dict]:
    results = []
    async with httpx.AsyncClient() as client:
        for wav_path in wav_files:
            wav_data = wav_path.read_bytes()
            audio_duration = wav_audio_duration(wav_data)
            console.print(f"\n[bold]STT Benchmark: {wav_path.name}[/bold] ({audio_duration:.1f}s audio)")

            for name, func in STT_PROVIDERS.items():
                latencies = []
                text = ""
                for i in range(iterations):
                    try:
                        text, latency = await func(client, wav_data)
                        if latency >= 0:
                            latencies.append(latency)
                    except Exception as e:
                        console.print(f"  [red]{name} error: {e}[/red]")
                        text = f"[error: {e}]"
                        break

                avg = sum(latencies) / len(latencies) if latencies else -1
                results.append({
                    "file": wav_path.name,
                    "provider": name,
                    "avg_ms": round(avg, 1),
                    "runs": len(latencies),
                    "text": text,
                    "audio_duration_s": round(audio_duration, 1),
                })

            # Chunked parallel benchmarks (only for longer audio)
            if audio_duration > 12:
                for stt_name, stt_func in STT_PROVIDERS.items():
                    # Skip providers without keys
                    test_text, test_lat = await stt_func(client, _make_wav(b'\x00' * 3200))  # tiny silence
                    if test_lat < 0:
                        continue

                    latencies = []
                    text = ""
                    label = f"{stt_name} (chunked 10s)"
                    for i in range(iterations):
                        try:
                            text, latency = await stt_chunked_parallel(
                                client, wav_data, stt_func, chunk_sec=10.0, overlap_sec=2.0
                            )
                            latencies.append(latency)
                        except Exception as e:
                            console.print(f"  [red]{label} error: {e}[/red]")
                            text = f"[error: {e}]"
                            break

                    avg = sum(latencies) / len(latencies) if latencies else -1
                    results.append({
                        "file": wav_path.name,
                        "provider": label,
                        "avg_ms": round(avg, 1),
                        "runs": len(latencies),
                        "text": text,
                        "audio_duration_s": round(audio_duration, 1),
                    })

    return results


async def benchmark_polish(text: str, iterations: int) -> list[dict]:
    results = []
    async with httpx.AsyncClient() as client:
        for name, func in POLISH_CONFIGS.items():
            latencies = []
            polished = ""
            for i in range(iterations):
                try:
                    result = func(client, text)
                    # Handle both sync (regex) and async (API) results
                    if asyncio.iscoroutine(result):
                        polished, latency = await result
                    else:
                        polished, latency = result
                    if latency >= 0:
                        latencies.append(latency)
                except Exception as e:
                    console.print(f"  [red]{name} error: {e}[/red]")
                    polished = f"[error: {e}]"
                    break

            avg = sum(latencies) / len(latencies) if latencies else -1
            results.append({
                "provider": name,
                "avg_ms": round(avg, 4) if name.startswith("Regex") else round(avg, 1),
                "runs": len(latencies),
                "polished_text": polished,
            })

    return results


async def benchmark_pipelines(
    wav_files: list[Path], stt_results: list[dict], polish_results: list[dict]
) -> list[dict]:
    """Simulate end-to-end pipelines by combining best STT + polish results."""
    combos = []

    # Get unique providers that worked
    stt_by_file: dict[str, dict[str, float]] = {}
    stt_texts: dict[str, dict[str, str]] = {}
    for r in stt_results:
        if r["avg_ms"] < 0:
            continue
        stt_by_file.setdefault(r["file"], {})[r["provider"]] = r["avg_ms"]
        stt_texts.setdefault(r["file"], {})[r["provider"]] = r["text"]

    polish_times = {r["provider"]: r["avg_ms"] for r in polish_results if r["avg_ms"] >= 0}

    for file_name, stt_providers in stt_by_file.items():
        for stt_name, stt_ms in stt_providers.items():
            for polish_name, polish_ms in polish_times.items():
                combos.append({
                    "file": file_name,
                    "stt": stt_name,
                    "polish": polish_name,
                    "stt_ms": stt_ms,
                    "polish_ms": polish_ms,
                    "total_ms": round(stt_ms + polish_ms, 1),
                })

    return combos


# ---------------------------------------------------------------------------
# Display
# ---------------------------------------------------------------------------


def print_stt_table(results: list[dict]):
    table = Table(title="STT Benchmark Results")
    table.add_column("Provider", style="cyan")
    table.add_column("Avg Latency (ms)", justify="right", style="magenta")
    table.add_column("Audio (s)", justify="right")
    table.add_column("Runs", justify="right")
    table.add_column("Transcription", max_width=60)

    for r in sorted(results, key=lambda x: (x["file"], x["avg_ms"] if x["avg_ms"] >= 0 else 99999)):
        latency_str = f"{r['avg_ms']:.0f}" if r["avg_ms"] >= 0 else "N/A"
        table.add_row(
            r["provider"],
            latency_str,
            str(r["audio_duration_s"]),
            str(r["runs"]),
            r["text"][:60],
        )

    console.print(table)


def print_polish_table(results: list[dict]):
    table = Table(title="Polishing Benchmark Results")
    table.add_column("Provider / Model", style="cyan")
    table.add_column("Avg Latency (ms)", justify="right", style="magenta")
    table.add_column("Runs", justify="right")
    table.add_column("Output", max_width=60)

    for r in sorted(results, key=lambda x: x["avg_ms"] if x["avg_ms"] >= 0 else 99999):
        latency_str = f"{r['avg_ms']}" if r["avg_ms"] >= 0 else "N/A"
        table.add_row(
            r["provider"],
            latency_str,
            str(r["runs"]),
            r["polished_text"][:60],
        )

    console.print(table)


def print_pipeline_table(combos: list[dict]):
    if not combos:
        return
    table = Table(title="End-to-End Pipeline Combinations (STT + Polish)")
    table.add_column("File", style="dim")
    table.add_column("STT Provider", style="cyan")
    table.add_column("Polish Provider", style="cyan")
    table.add_column("STT (ms)", justify="right")
    table.add_column("Polish (ms)", justify="right")
    table.add_column("Total (ms)", justify="right", style="bold magenta")

    for c in sorted(combos, key=lambda x: x["total_ms"])[:15]:  # top 15
        table.add_row(
            c["file"],
            c["stt"],
            c["polish"],
            f"{c['stt_ms']:.0f}",
            f"{c['polish_ms']:.0f}" if c["polish_ms"] >= 1 else f"{c['polish_ms']:.4f}",
            f"{c['total_ms']:.0f}" if c["total_ms"] >= 1 else f"{c['total_ms']:.4f}",
        )

    console.print(table)


def save_results(
    stt_results: list[dict],
    polish_results: list[dict],
    pipeline_combos: list[dict],
    output_dir: Path,
):
    output_dir.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.now().strftime("%Y-%m-%d_%H%M%S")
    output_file = output_dir / f"{timestamp}.json"
    data = {
        "timestamp": timestamp,
        "stt": stt_results,
        "polish": polish_results,
        "pipelines": sorted(pipeline_combos, key=lambda x: x["total_ms"])[:20] if pipeline_combos else [],
    }
    output_file.write_text(json.dumps(data, indent=2))
    console.print(f"\n[green]Results saved to {output_file}[/green]")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

DEFAULT_RECORDINGS_DIR = Path.home() / "Library/Application Support/Mumbli/recordings"


def main():
    parser = argparse.ArgumentParser(description="Mumbli Performance Benchmark")
    parser.add_argument("--file", type=Path, help="Single WAV file to benchmark")
    parser.add_argument("--dir", type=Path, help="Directory of WAV files to benchmark")
    parser.add_argument("--stt-only", action="store_true", help="Only benchmark STT providers")
    parser.add_argument("--polish-only", action="store_true", help="Only benchmark polishing")
    parser.add_argument("--text", type=str, help="Input text for polish-only mode")
    parser.add_argument("--iterations", type=int, default=1, help="Number of iterations per config")
    parser.add_argument(
        "--output", type=Path, default=Path(__file__).parent / "results",
        help="Output directory for results JSON",
    )
    args = parser.parse_args()

    # Resolve WAV files
    wav_files: list[Path] = []
    if args.file:
        wav_files = [args.file]
    elif args.dir:
        wav_files = sorted(args.dir.glob("*.wav"))
    elif not args.polish_only:
        if DEFAULT_RECORDINGS_DIR.exists():
            wav_files = sorted(DEFAULT_RECORDINGS_DIR.glob("*.wav"))

    if not wav_files and not args.polish_only:
        console.print("[red]No WAV files found. Use --file, --dir, or enable 'Save recordings' in Mumbli Settings.[/red]")
        sys.exit(1)

    # Show available keys
    console.print("\n[bold]API Keys:[/bold]")
    for name, key in [
        ("ElevenLabs", ELEVENLABS_KEY),
        ("OpenAI", OPENAI_KEY),
        ("Groq", GROQ_KEY),
        ("Deepgram", DEEPGRAM_KEY),
    ]:
        status = "[green]configured[/green]" if key else "[red]missing[/red]"
        console.print(f"  {name}: {status}")

    stt_results: list[dict] = []
    polish_results: list[dict] = []
    pipeline_combos: list[dict] = []

    if not args.polish_only:
        stt_results = asyncio.run(benchmark_stt(wav_files, args.iterations))
        print_stt_table(stt_results)

    if not args.stt_only:
        # Get text to polish
        polish_text = args.text
        if not polish_text and stt_results:
            for r in stt_results:
                if r["avg_ms"] >= 0 and not r["text"].startswith("["):
                    polish_text = r["text"]
                    break
        if not polish_text and wav_files:
            txt_path = wav_files[0].with_suffix(".txt")
            if txt_path.exists():
                polish_text = txt_path.read_text().strip()

        if polish_text:
            console.print(f"\n[bold]Polishing Benchmark[/bold] (input: {polish_text[:80]}...)")
            polish_results = asyncio.run(benchmark_polish(polish_text, args.iterations))
            print_polish_table(polish_results)
        else:
            console.print("[yellow]No text available for polishing benchmark.[/yellow]")

    # Combined pipeline analysis
    if stt_results and polish_results:
        pipeline_combos = asyncio.run(benchmark_pipelines(wav_files, stt_results, polish_results))
        print_pipeline_table(pipeline_combos)

    if stt_results or polish_results:
        save_results(stt_results, polish_results, pipeline_combos, args.output)


if __name__ == "__main__":
    main()
