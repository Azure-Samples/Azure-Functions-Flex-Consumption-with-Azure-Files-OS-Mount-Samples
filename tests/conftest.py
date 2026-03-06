"""
Shared pytest fixtures for Azure Functions + Azure Files samples.

These fixtures mock the Azure Functions runtime, Azure Files mount paths,
blob storage triggers, and Durable Functions contexts so tests run without
any real Azure resources.

Assumptions (Zoe, 2026-03-06):
- Samples use the Python v2 programming model (function_app.py entry point).
- Azure Files mount path is configured via AZURE_FILES_MOUNT_PATH env var
  or defaults to /mnt/azure-files in production. Tests use a tmp_path.
- Durable Functions orchestrator/activity patterns follow the standard
  azure-functions-durable SDK interfaces.
"""

import json
import os
import pathlib
import textwrap
from unittest.mock import AsyncMock, MagicMock, patch

import pytest


# ---------------------------------------------------------------------------
# Azure Files mount path fixtures
# ---------------------------------------------------------------------------

@pytest.fixture
def azure_files_mount(tmp_path: pathlib.Path) -> pathlib.Path:
    """Provides a temporary directory that simulates an Azure Files OS mount."""
    mount_dir = tmp_path / "azure-files"
    mount_dir.mkdir()
    return mount_dir


@pytest.fixture
def populated_mount(azure_files_mount: pathlib.Path) -> pathlib.Path:
    """Azure Files mount pre-populated with sample text files (known content)."""
    files = {
        "report.txt": (
            "Azure Functions Flex Consumption plan provides event-driven "
            "serverless compute for Azure. It offers automatic scaling. "
            "Functions run close to your data."
        ),
        "notes.txt": (
            "Azure Files shares can be mounted as OS-level paths. "
            "This lets functions read and write files using regular I/O. "
            "Shared access across instances is supported."
        ),
        "summary.txt": (
            "This repository contains sample code and documentation "
            "for using Azure Files with Azure Functions Flex Consumption."
        ),
    }
    for name, content in files.items():
        (azure_files_mount / name).write_text(content, encoding="utf-8")
    return azure_files_mount


@pytest.fixture
def empty_mount(azure_files_mount: pathlib.Path) -> pathlib.Path:
    """Azure Files mount with no files — edge case."""
    return azure_files_mount


@pytest.fixture
def nested_mount(azure_files_mount: pathlib.Path) -> pathlib.Path:
    """Azure Files mount with nested subdirectory structure."""
    sub = azure_files_mount / "subdir"
    sub.mkdir()
    (azure_files_mount / "top.txt").write_text("top-level file", encoding="utf-8")
    (sub / "nested.txt").write_text("nested file in subdirectory", encoding="utf-8")
    return azure_files_mount


@pytest.fixture
def mount_env(azure_files_mount: pathlib.Path, monkeypatch):
    """Sets AZURE_FILES_MOUNT_PATH env var to the mock mount directory."""
    monkeypatch.setenv("AZURE_FILES_MOUNT_PATH", str(azure_files_mount))
    return azure_files_mount


# ---------------------------------------------------------------------------
# Azure Functions HTTP request/response mocks
# ---------------------------------------------------------------------------

@pytest.fixture
def mock_http_request():
    """Factory for creating mock azure.functions.HttpRequest objects."""

    def _make_request(
        method: str = "POST",
        url: str = "http://localhost:7071/api/start",
        body: dict | None = None,
        params: dict | None = None,
    ) -> MagicMock:
        req = MagicMock()
        req.method = method
        req.url = url
        req.params = params or {}
        req.route_params = {}
        if body is not None:
            req.get_json.return_value = body
            req.get_body.return_value = json.dumps(body).encode("utf-8")
        else:
            req.get_json.side_effect = ValueError("No JSON body")
            req.get_body.return_value = b""
        return req

    return _make_request


# ---------------------------------------------------------------------------
# Durable Functions context mocks
# ---------------------------------------------------------------------------

@pytest.fixture
def mock_orchestration_context():
    """
    Returns a factory that builds a mock DurableOrchestrationContext.

    The mock tracks call_activity invocations and lets tests control
    what each activity returns.
    """

    def _make_context(activity_results: dict[str, list] | None = None):
        """
        activity_results: mapping from activity name to a list of return
        values (consumed in order as the orchestrator calls that activity).
        """
        results = activity_results or {}
        call_counts: dict[str, int] = {}

        ctx = MagicMock()
        ctx.instance_id = "test-instance-001"
        ctx.is_replaying = False

        def call_activity(name, input_=None):
            call_counts.setdefault(name, 0)
            idx = call_counts[name]
            call_counts[name] += 1
            values = results.get(name, [None])
            return values[idx] if idx < len(values) else None

        ctx.call_activity = MagicMock(side_effect=call_activity)
        ctx.task_all = AsyncMock(
            side_effect=lambda tasks: [t for t in tasks]
        )
        ctx.set_custom_status = MagicMock()
        ctx._call_counts = call_counts
        return ctx

    return _make_context


# ---------------------------------------------------------------------------
# Blob storage trigger mocks
# ---------------------------------------------------------------------------

@pytest.fixture
def mock_blob_input():
    """Factory for creating mock azure.functions.InputStream (blob trigger)."""

    def _make_blob(
        name: str = "image.png",
        content: bytes = b"\x89PNG\r\n\x1a\n",  # minimal PNG header
        length: int | None = None,
        uri: str = "https://example.blob.core.windows.net/images/image.png",
    ) -> MagicMock:
        blob = MagicMock()
        blob.name = name
        blob.length = length or len(content)
        blob.uri = uri
        blob.read.return_value = content
        return blob

    return _make_blob


# ---------------------------------------------------------------------------
# Sample data paths
# ---------------------------------------------------------------------------

TESTS_DIR = pathlib.Path(__file__).parent

@pytest.fixture
def durable_sample_data() -> pathlib.Path:
    """Path to durable text analysis sample data directory."""
    return TESTS_DIR / "test_durable_text_analysis" / "sample_data"


@pytest.fixture
def ffmpeg_sample_data() -> pathlib.Path:
    """Path to ffmpeg image processing sample data directory."""
    return TESTS_DIR / "test_ffmpeg_image_processing" / "sample_data"
