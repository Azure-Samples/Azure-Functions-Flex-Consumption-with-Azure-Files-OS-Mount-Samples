"""Activity functions for the Durable text-analysis sample.

Activities run on individual workers and do the actual I/O.  They read
from the Azure Files OS mount path which is surfaced at a well-known
filesystem path (e.g. ``/mounts/data/``).

Three activities:
  1. ``list_text_files``  — returns paths of ``.txt`` files on the mount.
  2. ``analyse_text_file`` — computes word/line counts and character
     frequency for a single file.
  3. ``aggregate_results``  — merges per-file results into a summary.
"""

from __future__ import annotations

import json
import logging
import os
from collections import Counter
from pathlib import Path

import azure.functions as func
import azure.durable_functions as df

bp = df.Blueprint()
logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Activity 1 — List text files on the mount
# ---------------------------------------------------------------------------
@bp.activity_trigger(input_name="payload")
def list_text_files(payload: dict) -> list[str]:
    """Return absolute paths of all ``.txt`` files under *mount_path*.

    The mount path comes from the orchestrator and ultimately from the
    ``MOUNT_PATH`` app setting or the HTTP request body.
    """
    mount_path = payload.get("mount_path", "/mounts/data/")
    root = Path(mount_path)

    if not root.exists():
        logger.warning("Mount path %s does not exist — is the share mounted?", mount_path)
        return []

    # Recursively find .txt files; sort for deterministic replay.
    txt_files = sorted(str(p) for p in root.rglob("*.txt") if p.is_file())
    logger.info("Found %d text file(s) in %s", len(txt_files), mount_path)
    return txt_files


# ---------------------------------------------------------------------------
# Activity 2 — Analyse a single text file
# ---------------------------------------------------------------------------
@bp.activity_trigger(input_name="payload")
def analyse_text_file(payload: dict) -> dict:
    """Analyse a single text file and return metrics.

    Returns a dict with:
      - file_path
      - word_count
      - line_count
      - char_count
      - top_characters  (10 most common non-whitespace characters)
      - avg_word_length
    """
    file_path = payload.get("file_path", "")

    if not file_path or not os.path.isfile(file_path):
        logger.error("File not found: %s", file_path)
        return {
            "file_path": file_path,
            "error": "File not found or inaccessible",
        }

    try:
        with open(file_path, "r", encoding="utf-8", errors="replace") as fh:
            content = fh.read()
    except OSError as exc:
        logger.error("Error reading %s: %s", file_path, exc)
        return {"file_path": file_path, "error": str(exc)}

    lines = content.splitlines()
    words = content.split()
    # Character frequency — ignore whitespace for a more interesting distribution.
    char_freq = Counter(ch.lower() for ch in content if not ch.isspace())

    total_word_len = sum(len(w) for w in words)
    avg_word_length = round(total_word_len / len(words), 2) if words else 0.0

    return {
        "file_path": file_path,
        "word_count": len(words),
        "line_count": len(lines),
        "char_count": len(content),
        "avg_word_length": avg_word_length,
        # Top 10 characters as list of [char, count] pairs (JSON-safe).
        "top_characters": char_freq.most_common(10),
    }


# ---------------------------------------------------------------------------
# Activity 3 — Aggregate per-file results
# ---------------------------------------------------------------------------
@bp.activity_trigger(input_name="payload")
def aggregate_results(payload: dict) -> dict:
    """Merge per-file analysis results into a single summary.

    Returns:
      - total_files
      - total_words
      - total_lines
      - total_chars
      - overall_avg_word_length
      - overall_top_characters (top 10 across all files)
      - per_file (the individual results, passed through)
    """
    results: list[dict] = payload.get("results", [])

    total_words = 0
    total_lines = 0
    total_chars = 0
    total_word_len_sum = 0
    combined_freq: Counter = Counter()
    valid_files = 0

    for r in results:
        if "error" in r:
            continue
        valid_files += 1
        total_words += r.get("word_count", 0)
        total_lines += r.get("line_count", 0)
        total_chars += r.get("char_count", 0)
        total_word_len_sum += r.get("avg_word_length", 0) * r.get("word_count", 0)
        # Rebuild Counter from the [char, count] pairs.
        for ch, cnt in r.get("top_characters", []):
            combined_freq[ch] += cnt

    overall_avg = (
        round(total_word_len_sum / total_words, 2) if total_words else 0.0
    )

    return {
        "total_files": valid_files,
        "total_words": total_words,
        "total_lines": total_lines,
        "total_chars": total_chars,
        "overall_avg_word_length": overall_avg,
        "overall_top_characters": combined_freq.most_common(10),
        "per_file": results,
    }
