#!/usr/bin/env python3
"""
Shared audio I/O helpers for the Mumbli benchmark harness.

Mumbli's recordings directory can now contain a mix of container formats:
  - .wav  — legacy uncompressed 16kHz mono PCM16 (44-byte RIFF header)
  - .caf  — new default, Opus-compressed
  - .m4a  — AAC fallback tier for machines without Opus encoding

Every recording still has a same-base-name .txt sidecar with its ground-truth
transcript; that pairing is unaffected by the audio container format.

These helpers let the rest of the benchmark scripts keep working with plain
WAV bytes (what every STT provider expects) regardless of which container a
given recording is stored in, by shelling out to macOS's bundled `afconvert`
tool to decode .caf/.m4a to WAV on demand. No third-party audio library is
required — everything here is Python stdlib plus the OS-provided afconvert.
"""

from __future__ import annotations

import subprocess
import tempfile
from pathlib import Path

RECORDING_EXTENSIONS = (".wav", ".caf", ".m4a")


def list_recordings(directory: Path) -> list[Path]:
    """Return all recording files (.wav, .caf, .m4a) in a directory, sorted by name."""
    directory = Path(directory)
    files: list[Path] = []
    for ext in RECORDING_EXTENSIONS:
        files.extend(directory.glob(f"*{ext}"))
    return sorted(files, key=lambda p: p.name)


def load_as_wav_bytes(path: Path) -> bytes:
    """
    Return 16kHz mono PCM16 WAV bytes for a recording, regardless of its
    on-disk container.

    - .wav files are read and returned as-is.
    - .caf / .m4a files are decoded via `afconvert` into a temporary WAV
      file, which is read and then cleaned up.
    """
    path = Path(path)
    suffix = path.suffix.lower()

    if suffix == ".wav":
        return path.read_bytes()

    if suffix in (".caf", ".m4a"):
        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
            tmp_path = Path(tmp.name)
        try:
            proc = subprocess.run(
                [
                    "afconvert",
                    "-f", "WAVE",
                    "-d", "LEI16@16000",
                    "-c", "1",
                    str(path),
                    str(tmp_path),
                ],
                capture_output=True,
                text=True,
            )
            if proc.returncode != 0:
                raise RuntimeError(
                    f"afconvert failed (exit {proc.returncode}) decoding {path}: "
                    f"{proc.stderr.strip()}"
                )
            return tmp_path.read_bytes()
        finally:
            tmp_path.unlink(missing_ok=True)

    raise ValueError(f"Unsupported recording extension {suffix!r} for {path}")


def wav_audio_duration_from_bytes(wav_bytes: bytes) -> float:
    """Calculate audio duration from WAV bytes (assumes 16-bit 16kHz mono)."""
    if len(wav_bytes) <= 44:
        return 0.0
    return max(0.0, (len(wav_bytes) - 44) / (16000 * 2))


def find_sibling_recording(base: Path) -> Path | None:
    """
    Given a base path (with any/no extension, e.g. a .txt sidecar path),
    return the first existing .wav/.caf/.m4a sibling sharing the same stem,
    or None if none exists.
    """
    for ext in RECORDING_EXTENSIONS:
        candidate = base.with_suffix(ext)
        if candidate.exists():
            return candidate
    return None
