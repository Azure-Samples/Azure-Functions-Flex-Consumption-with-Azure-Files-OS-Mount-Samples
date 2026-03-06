# Project Context

- **Owner:** Thiago Almeida
- **Project:** Azure Functions Flex Consumption samples and documentation for Azure Files OS share mounts. Demonstrating how to share data between function instances or between multiple apps using OS mount points.
- **Stack:** Python, Azure Functions (Flex Consumption), Durable Functions, Azure Files, ffmpeg
- **Key scenarios:** (1) Python + Durable Functions orchestrating parallel text file analysis against shared mounted files, (2) ffmpeg/image processing using large executables on shared OS mounts
- **Goal:** Official documentation tutorials + Azure Samples gallery entries showing Flex Consumption + Azure Files is production-ready
- **Created:** 2026-03-06

## Learnings

<!-- Append new learnings below. Each entry is something lasting about the project. -->

- **2026-03-06 — Project structure finalized (affects Kaylee's work).** Repo uses `samples/` (self-contained per Azure Samples gallery convention), `infra/modules/` (shared Bicep), `docs/` (learn.microsoft.com-ready). Kaylee will build sample code in `samples/durable-text-analysis/` and `samples/ffmpeg-image-processing/`. Shared modules referenced from sample-level `infra/main.bicep`. Decision: `.squad/decisions.md`.

- **2026-03-06 — Full solution built (19 files).** Both sample apps and shared infra are complete:
  - `samples/durable-text-analysis/`: Python v2 Durable Functions app with fan-out/fan-in orchestrator. Uses `df.Blueprint()` for orchestrator and activities, registered in `function_app.py`. Mount path configurable via `MOUNT_PATH` env var defaulting to `/mounts/data/`.
  - `samples/ffmpeg-image-processing/`: Blob-triggered function using EventGrid source (Flex Consumption default). ffmpeg called via subprocess stdin/stdout pipes — no temp files. Health endpoint verifies mount accessibility.
  - `infra/modules/`: 4 Bicep modules — `function-app.bicep` (FC1 SKU, Linux, Python 3.11), `storage-account.bicep` (with file share loop), `azure-files-mount.bicep` (patches `azureStorageAccounts` site config), `monitoring.bicep` (App Insights + Log Analytics).
  - `infra/scripts/`: 3 shell scripts — `deploy-sample.sh` (full end-to-end), `setup-azure-files.sh` (seed data + ffmpeg upload), `cleanup.sh` (resource group deletion).
  - Key gotcha: `mountPath` must start with `/mounts/` on Flex Consumption. Documented in `infra/README.md`.
  - Key gotcha: `azure-files-mount.bicep` uses `existing` keyword to patch — must deploy after function app exists.
  - Durable Functions host.json uses hub name `TextAnalysisHub` and extension bundle v4.x.

- **2026-03-06 — Test infrastructure complete (Zoe).** 55 tests passing across 3 suites. Zoe flagged activity naming contract: tests assume `list_files`, `analyze_text`, `aggregate_results` and ffmpeg at `/mnt/azure-files/bin/ffmpeg`. Implementation locked in these names — if changes needed, tests require update. See `.squad/orchestration-log/2026-03-06T19-43-zoe.md`.
