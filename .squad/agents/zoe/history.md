# Project Context

- **Owner:** Thiago Almeida
- **Project:** Azure Functions Flex Consumption samples and documentation for Azure Files OS share mounts. Demonstrating how to share data between function instances or between multiple apps using OS mount points.
- **Stack:** Python, Azure Functions (Flex Consumption), Durable Functions, Azure Files, ffmpeg
- **Key scenarios:** (1) Python + Durable Functions orchestrating parallel text file analysis against shared mounted files, (2) ffmpeg/image processing using large executables on shared OS mounts
- **Goal:** Official documentation tutorials + Azure Samples gallery entries showing Flex Consumption + Azure Files is production-ready
- **Created:** 2026-03-06

## Learnings

<!-- Append new learnings below. Each entry is something lasting about the project. -->

- **2026-03-06 — Project structure finalized (affects Zoe's work).** Repo uses `samples/` (self-contained per Azure Samples gallery convention), `infra/modules/` (shared Bicep), `docs/` (learn.microsoft.com-ready). Zoe will write tests alongside each sample in `samples/*/` and create test suites that reference sample code and deployment. Test coverage for both samples and shared infra. Decision: `.squad/decisions.md`.

- **2026-03-06 — Test infrastructure built.** 55 tests across 3 test suites, all passing. Key files:
  - `tests/conftest.py` — shared fixtures (mock mount paths, HTTP requests, Durable context, blob input).
  - `tests/test_durable_text_analysis/` — orchestrator fan-out/fan-in, activities (list/analyze/aggregate), HTTP starter.
  - `tests/test_ffmpeg_image_processing/` — subprocess mocking, binary discovery, blob trigger, mount access patterns.
  - `tests/test_infra/` — Bicep syntax validation (skips gracefully if az CLI absent).
  - `tests/requirements-test.txt` — pytest, pytest-asyncio, pytest-mock, pytest-cov, responses.
  - `pytest.ini` — config with `integration` marker for future Azure-resource tests.
  - `.github/workflows/ci.yml` — Python 3.9/3.10/3.11 matrix, coverage artifacts, Bicep validation.
  - Assumptions: activity names are `list_files`, `analyze_text`, `aggregate_results`; ffmpeg at `/mnt/azure-files/bin/ffmpeg`; mount path via `AZURE_FILES_MOUNT_PATH` env var. May need adjustment when Kaylee's code lands.
  - **Not in scope yet:** integration tests requiring real Azure resources — noted as future work in Bicep validation tests.

- **2026-03-06 — Implementation complete (Kaylee).** Both sample apps and shared Bicep infrastructure delivered with 19 files. Activity function names and mount paths are locked in per test contract. Ready for reconciliation if any implementation details differ. See `.squad/orchestration-log/2026-03-06T19-43-kaylee.md`.
