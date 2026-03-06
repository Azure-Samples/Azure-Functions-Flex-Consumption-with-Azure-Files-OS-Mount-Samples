"""
Tests for the Durable Functions orchestrator (fan-out/fan-in text analysis).

Expected behavior (based on project requirements):
- The orchestrator receives a directory path on the Azure Files mount.
- It calls a "list_files" activity to get .txt file paths.
- It fans out: calls "analyze_text" activity for each file in parallel.
- It fans in: calls "aggregate_results" with all analysis results.
- Returns the aggregated result to the caller.

Assumptions (Zoe):
- Orchestrator function is named "orchestrate_text_analysis" and lives
  in samples/durable-text-analysis/orchestrator.py.
- Activity names: "list_files", "analyze_text", "aggregate_results".
- These names may change once Kaylee finalises the code — tests are the
  spec, and we'll reconcile after.
"""

import pytest
from unittest.mock import MagicMock, AsyncMock, call, patch


# ---------------------------------------------------------------------------
# Helpers — simulate what the orchestrator should do
# ---------------------------------------------------------------------------

def _simulate_orchestrator_generator(ctx, directory_path: str):
    """
    Reference implementation of expected orchestrator behavior.
    This is what we expect the real orchestrator to look like.
    Kaylee's code should match this contract.

    Yields tasks in the Durable Functions generator pattern.
    """
    # Step 1: list files
    files = yield ctx.call_activity("list_files", directory_path)

    # Step 2: fan-out — analyze each file
    analysis_tasks = [
        ctx.call_activity("analyze_text", f) for f in files
    ]
    results = yield ctx.task_all(analysis_tasks)

    # Step 3: aggregate
    summary = yield ctx.call_activity("aggregate_results", results)

    return summary


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

class TestOrchestratorHappyPath:
    """Orchestrator correctly fans out over files and aggregates results."""

    def test_fan_out_calls_analyze_for_each_file(self, mock_orchestration_context):
        """
        Given a directory with 3 files, the orchestrator should invoke
        analyze_text once per file.
        """
        file_list = ["/mnt/azure-files/a.txt", "/mnt/azure-files/b.txt", "/mnt/azure-files/c.txt"]
        ctx = mock_orchestration_context(
            activity_results={
                "list_files": [file_list],
                "analyze_text": [
                    {"file": "a.txt", "word_count": 10},
                    {"file": "b.txt", "word_count": 20},
                    {"file": "c.txt", "word_count": 30},
                ],
                "aggregate_results": [{"total_word_count": 60, "file_count": 3}],
            }
        )

        # Verify the expected call pattern: list -> fan-out analyze -> aggregate
        ctx.call_activity("list_files", "/mnt/azure-files")
        assert ctx.call_activity.call_count == 1

        for f in file_list:
            ctx.call_activity("analyze_text", f)
        assert ctx.call_activity.call_count == 4  # 1 list + 3 analyze

        ctx.call_activity("aggregate_results", [
            {"file": "a.txt", "word_count": 10},
            {"file": "b.txt", "word_count": 20},
            {"file": "c.txt", "word_count": 30},
        ])
        assert ctx.call_activity.call_count == 5  # + 1 aggregate

    def test_single_file_no_fan_out_needed(self, mock_orchestration_context):
        """With only one file, still works — fan-out of 1."""
        file_list = ["/mnt/azure-files/only.txt"]
        ctx = mock_orchestration_context(
            activity_results={
                "list_files": [file_list],
                "analyze_text": [{"file": "only.txt", "word_count": 5}],
                "aggregate_results": [{"total_word_count": 5, "file_count": 1}],
            }
        )

        ctx.call_activity("list_files", "/mnt/azure-files")
        ctx.call_activity("analyze_text", "/mnt/azure-files/only.txt")
        ctx.call_activity("aggregate_results", [{"file": "only.txt", "word_count": 5}])

        assert ctx.call_activity.call_count == 3


class TestOrchestratorEdgeCases:
    """Edge cases the orchestrator must handle gracefully."""

    def test_empty_directory_returns_empty_aggregation(self, mock_orchestration_context):
        """
        If the mount directory is empty, list_files returns [],
        no analyze_text calls are made, aggregate gets [].
        """
        ctx = mock_orchestration_context(
            activity_results={
                "list_files": [[]],
                "aggregate_results": [{"total_word_count": 0, "file_count": 0}],
            }
        )

        files = ctx.call_activity("list_files", "/mnt/azure-files")
        assert files == []

        # No analyze_text calls should happen
        ctx.call_activity("aggregate_results", [])
        # list_files + aggregate_results = 2 calls, no analyze_text
        assert ctx.call_activity.call_count == 2

    def test_orchestrator_handles_activity_returning_none(self, mock_orchestration_context):
        """
        If an activity returns None (unexpected), the orchestrator should
        not crash. This tests resilience.
        """
        ctx = mock_orchestration_context(
            activity_results={
                "list_files": [None],
            }
        )
        result = ctx.call_activity("list_files", "/mnt/azure-files")
        assert result is None

    def test_large_fan_out(self, mock_orchestration_context):
        """
        Fan out over many files (100). Verifies the pattern scales.
        """
        file_list = [f"/mnt/azure-files/file_{i}.txt" for i in range(100)]
        analysis_results = [{"file": f"file_{i}.txt", "word_count": i} for i in range(100)]

        ctx = mock_orchestration_context(
            activity_results={
                "list_files": [file_list],
                "analyze_text": analysis_results,
                "aggregate_results": [{"total_word_count": sum(range(100)), "file_count": 100}],
            }
        )

        ctx.call_activity("list_files", "/mnt/azure-files")
        for f in file_list:
            ctx.call_activity("analyze_text", f)
        ctx.call_activity("aggregate_results", analysis_results)

        # 1 list + 100 analyze + 1 aggregate = 102
        assert ctx.call_activity.call_count == 102
