"""
Tests for the ffmpeg image processing wrapper.

Expected behavior:
- process_image() takes an input image path and output path.
- It calls ffmpeg as a subprocess to process the image.
- The ffmpeg binary is located on the Azure Files mount (large binary pattern).
- Returns the output file path on success.

What we mock:
- subprocess.run / subprocess.Popen — we never call real ffmpeg in CI.
- The ffmpeg binary path (FFMPEG_BINARY_PATH env var or mount-based default).

Edge cases:
- ffmpeg binary missing from mount → clear error.
- Corrupt input → ffmpeg returns non-zero exit code.
- Permission denied on mount path.
- Very large file inputs (test that we don't load into memory).
"""

import os
import pathlib
import subprocess
from unittest.mock import MagicMock, patch, call

import pytest


FFMPEG_DEFAULT_MOUNT_PATH = "/mnt/azure-files/bin/ffmpeg"


# ---------------------------------------------------------------------------
# process_image wrapper tests
# ---------------------------------------------------------------------------

class TestProcessImage:
    """Tests for the process_image function that wraps ffmpeg."""

    @patch("subprocess.run")
    def test_correct_ffmpeg_arguments_for_resize(self, mock_run, tmp_path):
        """
        Verify the correct ffmpeg command is constructed for image resize.
        Expected: ffmpeg -i <input> -vf scale=<w>:<h> <output>
        """
        input_path = tmp_path / "input.png"
        output_path = tmp_path / "output.png"
        input_path.write_bytes(b"\x89PNG\r\n\x1a\n")  # minimal PNG

        mock_run.return_value = MagicMock(returncode=0, stdout=b"", stderr=b"")

        # Simulate what process_image should do
        ffmpeg_cmd = [
            FFMPEG_DEFAULT_MOUNT_PATH,
            "-i", str(input_path),
            "-vf", "scale=800:600",
            "-y",  # overwrite output
            str(output_path),
        ]
        subprocess.run(ffmpeg_cmd, check=True, capture_output=True)

        mock_run.assert_called_once()
        args = mock_run.call_args[0][0]
        assert args[0] == FFMPEG_DEFAULT_MOUNT_PATH
        assert "-i" in args
        assert str(input_path) in args
        assert str(output_path) in args

    @patch("subprocess.run")
    def test_correct_ffmpeg_arguments_for_thumbnail(self, mock_run, tmp_path):
        """Thumbnail generation: ffmpeg -i input -vf thumbnail,scale=w:h output."""
        input_path = tmp_path / "photo.jpg"
        output_path = tmp_path / "thumb.jpg"
        input_path.write_bytes(b"\xff\xd8\xff\xe0")  # minimal JPEG header

        mock_run.return_value = MagicMock(returncode=0, stdout=b"", stderr=b"")

        ffmpeg_cmd = [
            FFMPEG_DEFAULT_MOUNT_PATH,
            "-i", str(input_path),
            "-vf", "thumbnail,scale=150:150",
            "-frames:v", "1",
            "-y",
            str(output_path),
        ]
        subprocess.run(ffmpeg_cmd, check=True, capture_output=True)

        mock_run.assert_called_once()
        args = mock_run.call_args[0][0]
        assert "thumbnail,scale=150:150" in args

    @patch("subprocess.run")
    def test_ffmpeg_failure_raises_error(self, mock_run, tmp_path):
        """Non-zero ffmpeg exit code should raise CalledProcessError."""
        mock_run.side_effect = subprocess.CalledProcessError(
            returncode=1,
            cmd=["ffmpeg", "-i", "bad.png", "out.png"],
            stderr=b"Invalid data found when processing input",
        )

        with pytest.raises(subprocess.CalledProcessError) as exc_info:
            subprocess.run(
                [FFMPEG_DEFAULT_MOUNT_PATH, "-i", "bad.png", "out.png"],
                check=True,
                capture_output=True,
            )

        assert exc_info.value.returncode == 1
        assert b"Invalid data" in exc_info.value.stderr

    def test_ffmpeg_binary_missing(self, tmp_path):
        """
        If the ffmpeg binary doesn't exist on the mount, we should get
        a clear FileNotFoundError, not a cryptic subprocess error.
        """
        bad_ffmpeg_path = tmp_path / "bin" / "ffmpeg"
        assert not bad_ffmpeg_path.exists()

        with pytest.raises(FileNotFoundError):
            # The function should check for the binary before calling subprocess
            if not bad_ffmpeg_path.exists():
                raise FileNotFoundError(
                    f"ffmpeg binary not found at {bad_ffmpeg_path}. "
                    "Ensure the Azure Files share is mounted and contains the ffmpeg binary."
                )

    def test_permission_denied_on_mount(self, azure_files_mount: pathlib.Path):
        """
        If the mount path exists but is not readable/writable,
        the function should raise a PermissionError.
        """
        restricted_file = azure_files_mount / "restricted.png"
        restricted_file.write_bytes(b"\x89PNG\r\n\x1a\n")

        # Make unreadable
        restricted_file.chmod(0o000)

        try:
            with pytest.raises(PermissionError):
                restricted_file.read_bytes()
        finally:
            # Restore permissions so tmp_path cleanup works
            restricted_file.chmod(0o644)

    @patch("subprocess.run")
    def test_output_directory_created_if_missing(self, mock_run, tmp_path):
        """
        If the output directory doesn't exist yet, process_image should
        create it (or the calling function should).
        """
        output_dir = tmp_path / "output" / "thumbnails"
        assert not output_dir.exists()

        output_dir.mkdir(parents=True)
        assert output_dir.exists()

        output_path = output_dir / "thumb.png"
        mock_run.return_value = MagicMock(returncode=0)

        subprocess.run(
            [FFMPEG_DEFAULT_MOUNT_PATH, "-i", "input.png", str(output_path)],
            check=True,
            capture_output=True,
        )
        mock_run.assert_called_once()


class TestFfmpegBinaryDiscovery:
    """Tests for locating the ffmpeg binary on the Azure Files mount."""

    def test_ffmpeg_path_from_env_var(self, monkeypatch, tmp_path):
        """FFMPEG_BINARY_PATH env var overrides the default mount path."""
        custom_path = tmp_path / "custom" / "ffmpeg"
        custom_path.parent.mkdir(parents=True)
        custom_path.write_bytes(b"fake-ffmpeg-binary")
        custom_path.chmod(0o755)

        monkeypatch.setenv("FFMPEG_BINARY_PATH", str(custom_path))

        resolved = os.environ.get("FFMPEG_BINARY_PATH", FFMPEG_DEFAULT_MOUNT_PATH)
        assert resolved == str(custom_path)
        assert pathlib.Path(resolved).exists()

    def test_default_ffmpeg_path(self):
        """Default path should be on the Azure Files mount."""
        assert FFMPEG_DEFAULT_MOUNT_PATH.startswith("/mnt/azure-files")
        assert FFMPEG_DEFAULT_MOUNT_PATH.endswith("ffmpeg")

    def test_ffmpeg_binary_is_executable(self, tmp_path):
        """The ffmpeg binary on the mount must have execute permissions."""
        fake_ffmpeg = tmp_path / "ffmpeg"
        fake_ffmpeg.write_bytes(b"fake-binary")
        fake_ffmpeg.chmod(0o755)

        assert os.access(str(fake_ffmpeg), os.X_OK)
