"""Helper module — wraps ffmpeg subprocess calls for image processing.

The ffmpeg binary is expected to live on an Azure Files OS mount (e.g.
``/mounts/tools/ffmpeg``).  This keeps the function app deployment
package small while still giving access to a ~100 MB binary.

All processing is done via stdin/stdout pipes to avoid temporary files
on the (limited) local disk of a Flex Consumption instance.
"""

from __future__ import annotations

import logging
import os
import subprocess
from typing import Optional

logger = logging.getLogger(__name__)

# Supported output formats — add more as needed.
SUPPORTED_FORMATS = {"png", "jpg", "jpeg", "webp", "bmp", "tiff"}


def _validate_ffmpeg(ffmpeg_path: str) -> None:
    """Raise ``FileNotFoundError`` if the ffmpeg binary is missing or not
    executable."""
    if not os.path.isfile(ffmpeg_path):
        raise FileNotFoundError(
            f"ffmpeg binary not found at '{ffmpeg_path}'. "
            "Ensure the Azure Files share is mounted and the binary is uploaded."
        )
    if not os.access(ffmpeg_path, os.X_OK):
        raise PermissionError(
            f"ffmpeg binary at '{ffmpeg_path}' is not executable. "
            "Run 'chmod +x' on the binary in the Azure Files share."
        )


def process_with_ffmpeg(
    image_bytes: bytes,
    *,
    ffmpeg_path: str = "/mounts/tools/ffmpeg",
    output_width: int = 800,
    output_format: str = "png",
    quality: Optional[int] = None,
    timeout_seconds: int = 30,
) -> bytes:
    """Resize and convert an image using the mounted ffmpeg binary.

    Parameters
    ----------
    image_bytes:
        Raw bytes of the source image.
    ffmpeg_path:
        Absolute path to the ffmpeg binary on the OS mount.
    output_width:
        Target width in pixels.  Height is scaled proportionally (``-1``
        tells ffmpeg to keep aspect ratio).
    output_format:
        Output container format (e.g. ``png``, ``jpg``, ``webp``).
    quality:
        Optional quality setting (``-q:v``).  Lower is better for JPEG
        (2–31).  Omitted if ``None``.
    timeout_seconds:
        Maximum wall-clock time before the subprocess is killed.

    Returns
    -------
    bytes
        The processed image.

    Raises
    ------
    FileNotFoundError
        If the ffmpeg binary is missing.
    PermissionError
        If the ffmpeg binary is not executable.
    RuntimeError
        If ffmpeg returns a non-zero exit code.
    subprocess.TimeoutExpired
        If processing exceeds *timeout_seconds*.
    """
    _validate_ffmpeg(ffmpeg_path)

    fmt = output_format.lower().strip(".")
    if fmt not in SUPPORTED_FORMATS:
        raise ValueError(
            f"Unsupported output format '{fmt}'. Choose from: {SUPPORTED_FORMATS}"
        )

    # Build the ffmpeg command.
    # -i pipe:0        → read input from stdin
    # -vf scale=W:-1   → resize width, keep aspect ratio
    # -f image2pipe     → write to stdout as raw image frames
    # -vcodec <codec>   → encode to the requested format
    cmd = [
        ffmpeg_path,
        "-hide_banner",
        "-loglevel", "error",
        "-i", "pipe:0",
        "-vf", f"scale={output_width}:-1",
    ]

    # Map output format to ffmpeg codec names.
    codec_map = {
        "png": "png",
        "jpg": "mjpeg",
        "jpeg": "mjpeg",
        "webp": "libwebp",
        "bmp": "bmp",
        "tiff": "tiff",
    }
    cmd += ["-vcodec", codec_map.get(fmt, fmt)]

    if quality is not None:
        cmd += ["-q:v", str(quality)]

    # ``-f image2pipe`` tells ffmpeg to output a single image to stdout.
    cmd += ["-f", "image2pipe", "pipe:1"]

    logger.debug("Running ffmpeg: %s", " ".join(cmd))

    result = subprocess.run(
        cmd,
        input=image_bytes,
        capture_output=True,
        timeout=timeout_seconds,
    )

    if result.returncode != 0:
        stderr = result.stderr.decode("utf-8", errors="replace").strip()
        raise RuntimeError(
            f"ffmpeg exited with code {result.returncode}: {stderr}"
        )

    output = result.stdout
    if not output:
        raise RuntimeError("ffmpeg produced empty output — check input image validity.")

    return output


def get_image_info(
    image_bytes: bytes,
    *,
    ffmpeg_path: str = "/mounts/tools/ffmpeg",
    timeout_seconds: int = 10,
) -> dict:
    """Probe basic image metadata using ffprobe (sibling of ffmpeg).

    Falls back gracefully if ffprobe is not available.
    """
    # ffprobe is typically alongside ffmpeg on the mount.
    ffprobe_path = os.path.join(os.path.dirname(ffmpeg_path), "ffprobe")
    if not os.path.isfile(ffprobe_path):
        return {"error": "ffprobe not found"}

    cmd = [
        ffprobe_path,
        "-hide_banner",
        "-loglevel", "error",
        "-print_format", "json",
        "-show_format",
        "-show_streams",
        "-i", "pipe:0",
    ]

    try:
        result = subprocess.run(
            cmd,
            input=image_bytes,
            capture_output=True,
            timeout=timeout_seconds,
        )
        if result.returncode != 0:
            return {"error": result.stderr.decode("utf-8", errors="replace").strip()}

        import json
        return json.loads(result.stdout)
    except Exception as exc:
        return {"error": str(exc)}
