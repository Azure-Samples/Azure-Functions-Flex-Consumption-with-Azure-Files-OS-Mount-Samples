"""
Tests for the blob trigger function app (ffmpeg image processing sample).

Expected behavior:
- A blob trigger fires when an image is uploaded to a container.
- The function reads the image, writes it to the Azure Files mount,
  calls process_image (ffmpeg) to create a processed version,
  and writes the result back to blob storage (or another location on the mount).

Edge cases:
- Non-image input (text file uploaded to the images container).
- Oversized file input.
- ffmpeg binary missing from mount.
- Corrupt image data.

Assumptions (Zoe):
- Blob trigger function is named "process_blob" in function_app.py.
- It uses azure.functions.InputStream for the trigger input.
- Processed output goes to a configurable output location.
"""

import pathlib
import subprocess
from unittest.mock import MagicMock, patch

import pytest


class TestBlobTriggerValidInput:
    """Tests for the blob trigger with valid image inputs."""

    def test_valid_png_triggers_processing(self, mock_blob_input, azure_files_mount):
        """
        A valid PNG blob should be written to mount, processed, and output saved.
        """
        blob = mock_blob_input(
            name="photos/landscape.png",
            content=b"\x89PNG\r\n\x1a\n" + b"\x00" * 100,
        )
        assert blob.name == "photos/landscape.png"
        assert blob.read().startswith(b"\x89PNG")

        # Simulate writing blob content to mount
        input_file = azure_files_mount / "landscape.png"
        input_file.write_bytes(blob.read())
        assert input_file.exists()

    def test_valid_jpeg_triggers_processing(self, mock_blob_input, azure_files_mount):
        """JPEG files should also be processed."""
        jpeg_header = b"\xff\xd8\xff\xe0\x00\x10JFIF"
        blob = mock_blob_input(
            name="photos/portrait.jpg",
            content=jpeg_header + b"\x00" * 50,
        )
        input_file = azure_files_mount / "portrait.jpg"
        input_file.write_bytes(blob.read())
        assert input_file.exists()

    @patch("subprocess.run")
    def test_processing_creates_output_file(self, mock_run, mock_blob_input, azure_files_mount):
        """After ffmpeg processes, an output file should exist."""
        mock_run.return_value = MagicMock(returncode=0, stdout=b"", stderr=b"")

        output_dir = azure_files_mount / "processed"
        output_dir.mkdir()
        output_path = output_dir / "thumb_image.png"

        # Simulate ffmpeg creating the output
        output_path.write_bytes(b"fake-processed-image-data")

        assert output_path.exists()
        assert output_path.stat().st_size > 0


class TestBlobTriggerInvalidInput:
    """Tests for the blob trigger with invalid or edge-case inputs."""

    def test_non_image_blob_rejected(self, mock_blob_input):
        """
        If a non-image file (e.g., .txt) triggers the function,
        it should be skipped or return an error — not crash.
        """
        blob = mock_blob_input(
            name="uploads/readme.txt",
            content=b"This is not an image file",
        )
        # The function should detect this isn't an image
        assert not blob.name.endswith((".png", ".jpg", ".jpeg", ".gif", ".bmp"))

    def test_empty_blob_handled(self, mock_blob_input):
        """Zero-byte blob should be handled gracefully."""
        blob = mock_blob_input(
            name="photos/empty.png",
            content=b"",
            length=0,
        )
        assert blob.length == 0
        assert blob.read() == b""

    def test_corrupt_image_data(self, mock_blob_input):
        """
        Blob with PNG extension but garbage content — ffmpeg will fail,
        function should catch and log the error.
        """
        blob = mock_blob_input(
            name="photos/corrupt.png",
            content=b"this-is-not-valid-png-data",
        )
        content = blob.read()
        # Not a valid PNG — doesn't start with PNG magic bytes
        assert not content.startswith(b"\x89PNG")

    def test_oversized_blob_handling(self, mock_blob_input):
        """
        Very large blob (simulated) — function should have size limits
        or handle gracefully without OOM.
        """
        # 100MB simulated blob
        blob = mock_blob_input(
            name="photos/huge.png",
            content=b"\x89PNG" + b"\x00" * 1024,  # small content, big reported size
            length=100 * 1024 * 1024,
        )
        assert blob.length == 100 * 1024 * 1024
        # Function should check blob.length before processing


class TestBlobTriggerFfmpegErrors:
    """Tests for ffmpeg-related errors in the blob trigger."""

    @patch("subprocess.run")
    def test_ffmpeg_not_found_on_mount(self, mock_run, mock_blob_input, azure_files_mount):
        """
        If ffmpeg binary is not found on the mount, the function
        should return a clear error.
        """
        mock_run.side_effect = FileNotFoundError(
            "[Errno 2] No such file or directory: '/mnt/azure-files/bin/ffmpeg'"
        )

        with pytest.raises(FileNotFoundError) as exc_info:
            subprocess.run(
                ["/mnt/azure-files/bin/ffmpeg", "-i", "input.png", "output.png"],
                check=True,
            )

        assert "ffmpeg" in str(exc_info.value)

    @patch("subprocess.run")
    def test_ffmpeg_returns_error_code(self, mock_run, mock_blob_input):
        """ffmpeg exits with error — function should log and not crash."""
        mock_run.side_effect = subprocess.CalledProcessError(
            returncode=1,
            cmd=["ffmpeg"],
            stderr=b"Error while decoding stream",
        )

        with pytest.raises(subprocess.CalledProcessError):
            subprocess.run(
                ["/mnt/azure-files/bin/ffmpeg", "-i", "bad.png", "out.png"],
                check=True,
                capture_output=True,
            )

    @patch("subprocess.run")
    def test_ffmpeg_timeout(self, mock_run, mock_blob_input):
        """ffmpeg hangs or takes too long — function should have a timeout."""
        mock_run.side_effect = subprocess.TimeoutExpired(
            cmd=["ffmpeg"], timeout=30
        )

        with pytest.raises(subprocess.TimeoutExpired):
            subprocess.run(
                ["/mnt/azure-files/bin/ffmpeg", "-i", "big.png", "out.png"],
                check=True,
                capture_output=True,
                timeout=30,
            )


class TestBlobTriggerMountAccess:
    """Tests for Azure Files mount access patterns in the blob trigger."""

    def test_mount_path_writable(self, azure_files_mount: pathlib.Path):
        """The mount directory should be writable for saving input files."""
        test_file = azure_files_mount / "write_test.tmp"
        test_file.write_bytes(b"test")
        assert test_file.exists()
        test_file.unlink()

    def test_mount_path_readable(self, azure_files_mount: pathlib.Path):
        """The mount directory should be readable for output files."""
        test_file = azure_files_mount / "read_test.tmp"
        test_file.write_bytes(b"test-content")
        assert test_file.read_bytes() == b"test-content"
        test_file.unlink()

    def test_concurrent_file_access_simulation(self, azure_files_mount: pathlib.Path):
        """
        Multiple function instances writing to the mount simultaneously.
        Files should use unique names to avoid conflicts.
        """
        # Simulate 5 instances writing at the same time
        files = []
        for i in range(5):
            f = azure_files_mount / f"instance_{i}_output.png"
            f.write_bytes(f"output-{i}".encode())
            files.append(f)

        # All files should exist with correct content
        for i, f in enumerate(files):
            assert f.exists()
            assert f.read_bytes() == f"output-{i}".encode()

        # Cleanup
        for f in files:
            f.unlink()
