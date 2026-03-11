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

- **2026-03-06 — Mount overwrite bug fixed (Zoe, assigned by Mal).** The deploy script deployed mounts sequentially, but `Microsoft.Web/sites/config` replaces the entire `azureStorageAccounts` dict each time — so only the last mount survived. Fix: created `azure-files-mounts.bicep` (plural) that accepts an array and deploys all mounts in one shot via `reduce/union`. Updated `deploy-sample.sh` to use the plural module. Kept the singular module for backward compat. Added 12 tests in `tests/test_infra/test_mount_overwrite_fix.py` covering module compilation, structural correctness, and deploy script validation. Full suite: 67 passed, 0 failed. **Key lesson:** Any Bicep resource that uses a dictionary property (like `azureStorageAccounts`) will overwrite the entire dictionary on deploy — never deploy such resources piecemeal.

- **2026-03-06 — Re-assignment: Mount overwrite bug fix (post-Mal review).** Mal's full code review rejected deploy script for critical mount overwrite bug. Zoe (original tester) was locked out but reassigned to fix since she understands infrastructure and test patterns. Bug: sequential mount deployments via singular module clobbered prior mounts because `Microsoft.Web/sites/config` replaces entire `azureStorageAccounts` dictionary. Solution: created `azure-files-mounts.bicep` (plural) accepting array of mounts, using `reduce()`/`union()` to merge all mounts in single atomic config deployment. Updated `deploy-sample.sh` to use plural module. Kept singular module for backward compat. Added 12 regression tests in `tests/test_infra/test_mount_overwrite_fix.py` covering edge cases and verifying mount coexistence. All 67 tests pass. Key lesson: dictionary-based Bicep resources require atomic merge patterns; never deploy piecemeal. See `.squad/orchestration-log/2026-03-06T20-00-zoe.md` and `.squad/decisions.md` for full details.

- **2026-03-11 — Documentation audit completed (Inara).** All 3 quickstart and tutorial docs audited against actual code and infrastructure. Fixed 9 discrepancies: mount paths corrected, local.settings.json refs removed with inline instructions, EventGrid post-deploy documented, unused TEMP_PATH removed, requirements.txt accuracy fixed, share name corrected, health check endpoint added to docs, activity descriptions fixed, and path consistency ensured. All docs now match ground truth and reference the shared infrastructure patterns that Zoe's tests help validate. See `.squad/decisions.md` (Documentation Audit & Code Alignment Fixes).
