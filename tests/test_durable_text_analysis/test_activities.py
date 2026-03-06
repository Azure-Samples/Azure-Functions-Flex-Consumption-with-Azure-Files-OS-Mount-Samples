"""
Tests for the Durable Functions activity functions.

Expected activities (from project requirements):
1. list_files(directory_path) → list[str]
   - Lists .txt files in the given directory on the Azure Files mount.
2. analyze_text(file_path) → dict
   - Reads a text file, returns analysis (word count, line count, char count, etc.).
3. aggregate_results(results: list[dict]) → dict
   - Combines analysis results into a summary.

These are pure Python functions when given file paths — no Azure runtime needed.
We test them directly using mock mount paths (tmp_path fixtures from conftest).

Assumptions (Zoe):
- Activities are importable from samples.durable-text-analysis.activities
  or an equivalent module path. Since samples use hyphens in dir names,
  imports may need sys.path manipulation. Tests will define expected
  behavior; import wiring adjusts later.
"""

import os
import pathlib

import pytest


# ---------------------------------------------------------------------------
# list_files activity tests
# ---------------------------------------------------------------------------

class TestListFilesActivity:
    """Tests for the list_files activity function."""

    def test_lists_txt_files_in_directory(self, populated_mount: pathlib.Path):
        """Returns paths to all .txt files in the mount directory."""
        txt_files = sorted(
            str(f) for f in populated_mount.iterdir() if f.suffix == ".txt"
        )
        assert len(txt_files) == 3
        assert all(f.endswith(".txt") for f in txt_files)

    def test_empty_directory_returns_empty_list(self, empty_mount: pathlib.Path):
        """Empty directory → empty list, no error."""
        txt_files = [f for f in empty_mount.iterdir() if f.suffix == ".txt"]
        assert txt_files == []

    def test_ignores_non_txt_files(self, azure_files_mount: pathlib.Path):
        """Only .txt files should be returned, not .log, .csv, etc."""
        (azure_files_mount / "data.csv").write_text("a,b,c")
        (azure_files_mount / "app.log").write_text("log entry")
        (azure_files_mount / "readme.txt").write_text("hello")

        txt_files = [f for f in azure_files_mount.iterdir() if f.suffix == ".txt"]
        assert len(txt_files) == 1
        assert txt_files[0].name == "readme.txt"

    def test_nested_directory_handling(self, nested_mount: pathlib.Path):
        """
        Verify behavior with nested directories. The activity should either:
        - Only list top-level .txt files (simple), OR
        - Recursively list all .txt files (comprehensive).
        Testing both cases — Kaylee picks the approach.
        """
        # Top-level only
        top_level = [f for f in nested_mount.iterdir() if f.is_file() and f.suffix == ".txt"]
        assert len(top_level) == 1
        assert top_level[0].name == "top.txt"

        # Recursive
        all_txt = list(nested_mount.rglob("*.txt"))
        assert len(all_txt) == 2
        names = sorted(f.name for f in all_txt)
        assert names == ["nested.txt", "top.txt"]

    def test_directory_does_not_exist(self, tmp_path: pathlib.Path):
        """Non-existent directory should raise a clear error."""
        bad_path = tmp_path / "does-not-exist"
        assert not bad_path.exists()
        with pytest.raises((FileNotFoundError, OSError)):
            list(bad_path.iterdir())


# ---------------------------------------------------------------------------
# analyze_text activity tests
# ---------------------------------------------------------------------------

class TestAnalyzeTextActivity:
    """Tests for the analyze_text activity function."""

    def test_basic_analysis(self, durable_sample_data: pathlib.Path):
        """Analyze a known file — verify word count, line count, char count."""
        report = durable_sample_data / "report.txt"
        content = report.read_text(encoding="utf-8")

        words = content.split()
        lines = content.strip().splitlines()

        # Known content: 5 lines, specific word/char counts
        assert len(lines) == 5
        assert len(words) > 0
        assert len(content) > 0

    def test_empty_file(self, azure_files_mount: pathlib.Path):
        """Empty file should return zero counts, not error."""
        empty = azure_files_mount / "empty.txt"
        empty.write_text("", encoding="utf-8")

        content = empty.read_text(encoding="utf-8")
        assert content == ""
        assert len(content.split()) == 0

    def test_unicode_content(self, durable_sample_data: pathlib.Path):
        """Files with Unicode characters are analyzed without errors."""
        unicode_file = durable_sample_data / "unicode.txt"
        content = unicode_file.read_text(encoding="utf-8")

        assert "Héllo" in content
        assert "日本語" in content
        # Word splitting should still work
        words = content.split()
        assert len(words) > 0

    def test_large_file_simulation(self, azure_files_mount: pathlib.Path):
        """
        Simulate a large file (~1MB of text). The activity should handle it
        without running out of memory or timing out.
        """
        large = azure_files_mount / "large.txt"
        line = "This is a line of text that repeats to simulate a large file. " * 10
        large.write_text(line * 1000, encoding="utf-8")

        content = large.read_text(encoding="utf-8")
        assert len(content) > 500_000  # at least 500KB
        words = content.split()
        assert len(words) > 10_000

    def test_file_with_only_whitespace(self, azure_files_mount: pathlib.Path):
        """File with only spaces/newlines — word count should be 0."""
        ws_file = azure_files_mount / "whitespace.txt"
        ws_file.write_text("   \n\n  \t  \n", encoding="utf-8")

        content = ws_file.read_text(encoding="utf-8")
        assert len(content.split()) == 0

    def test_file_not_found(self, azure_files_mount: pathlib.Path):
        """Attempting to analyze a non-existent file raises an error."""
        missing = azure_files_mount / "ghost.txt"
        with pytest.raises(FileNotFoundError):
            missing.read_text(encoding="utf-8")


# ---------------------------------------------------------------------------
# aggregate_results activity tests
# ---------------------------------------------------------------------------

class TestAggregateResultsActivity:
    """Tests for the aggregate_results activity function."""

    def test_aggregate_multiple_results(self):
        """Aggregating several analysis results produces correct totals."""
        results = [
            {"file": "a.txt", "word_count": 100, "line_count": 10, "char_count": 500},
            {"file": "b.txt", "word_count": 200, "line_count": 20, "char_count": 1000},
            {"file": "c.txt", "word_count": 50, "line_count": 5, "char_count": 250},
        ]

        total_words = sum(r["word_count"] for r in results)
        total_lines = sum(r["line_count"] for r in results)
        total_chars = sum(r["char_count"] for r in results)

        assert total_words == 350
        assert total_lines == 35
        assert total_chars == 1750

    def test_aggregate_single_result(self):
        """Single-file aggregation should work fine."""
        results = [
            {"file": "only.txt", "word_count": 42, "line_count": 3, "char_count": 200},
        ]

        total_words = sum(r["word_count"] for r in results)
        assert total_words == 42

    def test_aggregate_empty_results(self):
        """Empty results list — totals should all be zero."""
        results = []
        total_words = sum(r.get("word_count", 0) for r in results)
        assert total_words == 0

    def test_aggregate_handles_missing_keys_gracefully(self):
        """
        If a result dict is missing expected keys (e.g., activity returned
        partial data), aggregation should handle it with defaults.
        """
        results = [
            {"file": "a.txt", "word_count": 10},
            {"file": "b.txt"},  # missing word_count
        ]
        total = sum(r.get("word_count", 0) for r in results)
        assert total == 10
