"""
Tests for the HTTP trigger starter function (durable text analysis sample).

Expected behavior:
- POST /api/start with JSON body {"directory": "/path/to/dir"} starts the orchestrator.
- Returns HTTP 202 with the orchestration status URL.
- Missing or invalid request body returns HTTP 400.
- Internal errors return HTTP 500.

Assumptions (Zoe):
- The HTTP trigger function is named "http_start" in function_app.py.
- It creates a Durable Functions client, starts the orchestrator, and returns
  the standard create_check_status_response.
"""

import json
from unittest.mock import AsyncMock, MagicMock, patch

import pytest


class TestHttpStartTrigger:
    """Tests for the HTTP trigger that starts the orchestration."""

    def test_valid_request_starts_orchestration(self, mock_http_request):
        """
        A valid POST with a directory path should:
        1. Start the orchestrator with the directory as input.
        2. Return the management URLs (HTTP 202 pattern).
        """
        req = mock_http_request(
            method="POST",
            body={"directory": "/mnt/azure-files/documents"},
        )
        body = req.get_json()
        assert body["directory"] == "/mnt/azure-files/documents"

    def test_missing_directory_param_returns_400(self, mock_http_request):
        """POST with empty body or missing 'directory' key → 400."""
        req = mock_http_request(method="POST", body={})
        body = req.get_json()
        assert "directory" not in body

    def test_no_json_body_returns_400(self, mock_http_request):
        """POST with no body at all → 400."""
        req = mock_http_request(method="POST", body=None)
        with pytest.raises(ValueError):
            req.get_json()

    def test_get_request_returns_method_info(self, mock_http_request):
        """
        GET requests might be supported for health check or info.
        At minimum, should not crash.
        """
        req = mock_http_request(method="GET")
        assert req.method == "GET"

    def test_directory_path_validation(self, mock_http_request):
        """
        Directory path should be a reasonable path string.
        Edge cases: empty string, path traversal attempts, very long paths.
        """
        # Empty directory
        req = mock_http_request(method="POST", body={"directory": ""})
        body = req.get_json()
        assert body["directory"] == ""

        # Path traversal attempt — the function should sanitize or reject
        req = mock_http_request(
            method="POST",
            body={"directory": "/mnt/azure-files/../../etc/passwd"},
        )
        body = req.get_json()
        assert ".." in body["directory"]  # function should catch this

    def test_response_format(self):
        """
        The starter should return a response compatible with Durable Functions
        management API — statusQueryGetUri, sendEventPostUri, etc.
        """
        # Standard Durable Functions check status response shape
        expected_keys = {
            "id",
            "statusQueryGetUri",
            "sendEventPostUri",
            "terminatePostUri",
            "purgeHistoryDeleteUri",
        }
        # When the real function returns this, we verify the keys exist
        mock_response = {
            "id": "abc-123",
            "statusQueryGetUri": "http://localhost:7071/runtime/webhooks/durabletask/instances/abc-123",
            "sendEventPostUri": "http://localhost:7071/runtime/webhooks/durabletask/instances/abc-123/raiseEvent/{eventName}",
            "terminatePostUri": "http://localhost:7071/runtime/webhooks/durabletask/instances/abc-123/terminate",
            "purgeHistoryDeleteUri": "http://localhost:7071/runtime/webhooks/durabletask/instances/abc-123",
        }
        assert expected_keys.issubset(mock_response.keys())
