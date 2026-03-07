# Project Context

- **Owner:** Thiago Almeida
- **Project:** Azure Functions Flex Consumption samples and documentation for Azure Files OS share mounts. Demonstrating how to share data between function instances or between multiple apps using OS mount points.
- **Stack:** Python, Azure Functions (Flex Consumption), Durable Functions, Azure Files, ffmpeg
- **Key scenarios:** (1) Python + Durable Functions orchestrating parallel text file analysis against shared mounted files, (2) ffmpeg/image processing using large executables on shared OS mounts
- **Goal:** Official documentation tutorials + Azure Samples gallery entries showing Flex Consumption + Azure Files is production-ready
- **Created:** 2026-03-06

## Core Context

**Previous sessions (2026-03-06, abbreviated):**
- Project structure finalized: `samples/`, `infra/modules/` (shared Bicep), `docs/` (learn.microsoft.com-ready)
- Full solution built: 2 sample apps (durable text analysis with fan-out/fan-in, ffmpeg image processing via blob trigger) + 4 shared Bicep modules (function-app, storage-account, azure-files-mount, monitoring) + 3 deployment scripts
- Test infrastructure: 55 passing tests across 3 suites (activity names locked: list_files, analyze_text, aggregate_results)
- Doc-code alignment fixes: Mal rejected all 7 docs for misalignment; Kaylee fixed mount paths (`/mnt/` → `/mounts/`), endpoints, schemas, share names, infra refs
- Bicep infrastructure rewrite: Added `functionAppConfig` (mandatory for Flex Consumption), managed identity auth, separate endpoint URIs, RBAC assignments, removed legacy properties
- First E2E deployment (Durable app): Discovered `allowSharedKeyAccess` enterprise policy block; workaround: `Az.Sec.DisableLocalAuth.Storage::Skip` tag
- ffmpeg app deployed separately: EventGrid system topic/subscription NOT auto-created — manual setup required via CLI. Key learning: `az functionapp create --flexconsumption-location` auto-creates Flex Consumption with `functionAppConfig`

## Learnings

<!-- Append new learnings below. Each entry is something lasting about the project. -->

- **2026-03-07 — Documentation updated with deployment gotchas (10 files, all live).** After end-to-end deployment and testing, updated all documentation to reflect 4 key gotchas: (1) `allowSharedKeyAccess` + enterprise policy requires `Az.Sec.DisableLocalAuth.Storage::Skip` tag; (2) EventGrid system topic not auto-created for Flex Consumption blob triggers — manual CLI setup required; (3) Function key auth requires `?code=` query param, Durable response schema uses `id` (not `instance_id`), use `statusQueryGetUri` for polling; (4) Separate function apps per sample for isolation/scaling. Updated: quickstart-durable, quickstart-ffmpeg, tutorial, 3 concept docs, infra/README, root README, 2 sample READMEs. All docs use Microsoft Learn callout syntax (`> [!IMPORTANT]`, `> [!NOTE]`). See `.squad/orchestration-log/2026-03-07T00-12-13-kaylee.md` and `.squad/decisions.md`.
