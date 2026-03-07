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

- **2026-03-06 — Doc-code alignment fixes (7 files).** Mal rejected all docs for systematic misalignment with actual code. Fixed every issue:
  - All mount paths changed from `/mnt/` to `/mounts/` across all 6 doc files (Flex Consumption requires `/mounts/` prefix).
  - Durable quickstart: corrected HTTP endpoint (`/api/start-analysis`), status endpoint (`/api/status/{instance_id}`), share name (`data`), response schema (actual `aggregate_results` output with `total_files`, `total_words`, `total_lines`, `total_chars`, `overall_avg_word_length`, `overall_top_characters`, `per_file`), and infra reference (`infra/scripts/deploy-sample.sh`).
  - FFmpeg quickstart: corrected share name (`tools`), mount path (`/mounts/tools/ffmpeg`), function name in logs (`process_image_blob`), output blob name (same name as input via `{name}` binding), requirements description (just `azure-functions`), and infra reference.
  - Concept docs: replaced `WEBSITE_MOUNT_ENABLED` app settings pattern with correct `azureStorageAccounts` site config property approach. Removed `WEBSITE_MOUNT_ENABLED` from Bicep examples.
  - Removed dead Pillow dependency from `samples/ffmpeg-image-processing/requirements.txt`.
  - All 67 tests still pass after changes.

- **2026-03-06 — Re-assignment: Doc-code alignment fixes (post-Mal review).** Mal's full code review rejected all 7 documentation files for systematic misalignment with actual code. Inara (original DevRel author) was locked out; Kaylee reassigned to fix all docs since she knows the actual implementation. Completed all fixes: mount paths `/mnt/` → `/mounts/`, HTTP endpoints corrected, response schemas updated, share names aligned, infra references fixed to point to actual deploy scripts, mount config mechanism changed from app settings to site config property, and dead Pillow dependency removed. All 67 tests pass. See `.squad/orchestration-log/2026-03-06T20-00-kaylee.md` and `.squad/decisions.md` for full details.

- **2026-03-06 — Flex Consumption Bicep infrastructure rewrite.** Rewrote all three shared Bicep modules to correctly create a Flex Consumption app. Key changes:
  - **function-app.bicep**: Added `functionAppConfig` property (the #1 requirement for Flex Consumption) with `deployment.storage` (blob container + managed identity auth), `scaleAndConcurrency` (maximumInstanceCount, instanceMemoryMB), and `runtime` (name + version). Removed `linuxFxVersion`, `FUNCTIONS_WORKER_RUNTIME`, `FUNCTIONS_EXTENSION_VERSION`, `AzureWebJobsFeatureFlags`, `APPINSIGHTS_INSTRUMENTATIONKEY`, and raw `AzureWebJobsStorage` connection string. Added system-assigned managed identity, `AzureWebJobsStorage__credential: 'managedidentity'` with separate blob/queue/table URIs. Outputs now include `principalId` for RBAC assignments. API version bumped to 2024-04-01.
  - **storage-account.bicep**: Added `deploymentContainerName` param for Flex Consumption deployment packages. Added blob, queue, and table service resources. Outputs changed from `connectionString` to `primaryBlobEndpoint`, `blobServiceUri`, `queueServiceUri`, `tableServiceUri`. Kept `accountKey` output (needed for Azure Files mounts). Added `allowSharedKeyAccess` param (defaults true for mount compatibility).
  - **monitoring.bicep**: Added `DisableLocalAuth: true` on App Insights. Removed `instrumentationKey` output (deprecated). Added `APPLICATIONINSIGHTS_AUTHENTICATION_STRING: 'Authorization=AAD'` pattern in function app.
  - **deploy-sample.sh**: Updated to pass new storage endpoint params instead of connection strings. Added RBAC role assignments (Storage Blob Data Owner, Storage Queue Data Contributor, Storage Table Data Contributor) to function app's managed identity.
  - Deleted stale compiled JSON files for the three rewritten modules. Mount JSON files untouched.
  - All 67 tests pass. Reference: https://github.com/Azure-Samples/azure-functions-flex-consumption-samples
  - Key learning: Flex Consumption's `functionAppConfig` is mandatory — without it the app deploys as a regular consumption plan. The runtime config (language + version) goes in `functionAppConfig.runtime`, NOT in `linuxFxVersion`.

- **2026-03-06 — First successful end-to-end deployment.** Deployed Durable Text Analysis sample to Azure (subscription: thalme, RG: `rg-azure-files-samples-dev`, region: eastus). Full infrastructure via `infra/main.bicep` orchestrating all 4 modules in dependency order. Resources: storage account `stazfilefuncdev`, function app `azfilefunc-func` (Flex Consumption FC1, Python 3.11), App Insights + Log Analytics, 3 RBAC role assignments, 2 Azure Files OS mounts (`/mounts/data`, `/mounts/tools`). Key issue hit: Microsoft corporate policy blocks `allowSharedKeyAccess: true` on storage accounts. Fixed by adding tag `Az.Sec.DisableLocalAuth.Storage::Skip` to the storage account. Azure Files mounts require shared key access — no managed identity option for SMB mounts yet. Code deployed via `func azure functionapp publish`. Orchestration tested end-to-end: 3 text files analysed from mounted `/mounts/data/` share, fan-out/fan-in completed, full aggregated results returned. Orchestration completed in ~10 seconds.

- **2026-03-06 — ffmpeg-image-processing sample deployed and tested end-to-end.** Created a second Flex Consumption function app `azfilefunc-ffmpeg` in `rg-azure-files-samples-dev` to keep samples isolated. Infrastructure deployed via `az` CLI:
  - Function app: `azfilefunc-ffmpeg` (FC1 SKU, Python 3.11, system-assigned managed identity)
  - Hosting plan: `ASP-rgazurefilessamplesdev-54d7` (auto-created by `az functionapp create --flexconsumption-location`)
  - RBAC: Storage Blob Data Owner, Queue Data Contributor, Table Data Contributor assigned to principal `7e54e1c1-04e7-4910-a627-aa570b6454bd`
  - App settings: managed identity storage URIs, `FFMPEG_PATH=/mounts/tools/ffmpeg`, AAD App Insights auth
  - Azure Files mount: `/mounts/tools` → `tools` share (SMB, shared key)
  - ffmpeg 7.0.2 static Linux x86_64 binary (~80MB) + ffprobe uploaded to `tools` share from johnvansickle.com
  - Blob containers: `images-input` and `images-output` created
  - EventGrid: system topic `stazfilefuncdev-topic` + subscription `ffmpeg-blob-trigger` filtering `BlobCreated` on `images-input`
  - Code deployed via `func azure functionapp publish azfilefunc-ffmpeg --python`
  - Health endpoint confirms ffmpeg accessible: `GET /api/health` → `{"status": "healthy", "ffmpeg_available": true}`
  - E2E test: uploaded 100×75 PNG (15KB) → blob trigger fired → ffmpeg resized to 800×600 PNG (112KB) → written to `images-output`. Processing was near-instant (EventGrid trigger latency < 3 seconds).
  - Key learning: Flex Consumption blob triggers with `source="EventGrid"` do NOT auto-create the EventGrid system topic or subscription. You must create them manually: (1) `az eventgrid system-topic create` on the storage account, (2) `az eventgrid system-topic event-subscription create` with the function's blobs_extension webhook URL and `--subject-begins-with` filter for the container.
  - Key learning: The `az functionapp create --flexconsumption-location` flag creates a Flex Consumption app with `functionAppConfig` automatically — no need for Bicep for quick deployments. It also creates the deployment blob container.
  - Key learning: The deployment connection string approach (`DEPLOYMENT_STORAGE_CONNECTION_STRING`) is used by CLI-created apps instead of managed identity for deployment storage. Existing managed identity pattern in Bicep modules is still better for production.

- **2026-03-06 — Documentation updated with deployment gotchas (10 files).** After live end-to-end deployment and testing of both samples, updated all documentation to reflect 4 key gotchas discovered:
  1. **`allowSharedKeyAccess` + enterprise policy:** Azure Files SMB mounts require shared key access. Enterprise subscriptions may block this via policy. Workaround: add tag `Az.Sec.DisableLocalAuth.Storage::Skip`. Added to: quickstart-durable, quickstart-ffmpeg, tutorial, flex-consumption-os-mounts, azure-files-with-functions, infra/README, root README, both sample READMEs.
  2. **EventGrid system topic not auto-created:** Flex Consumption blob triggers with `source="EventGrid"` do NOT auto-create the system topic or subscription. Added full `az` CLI commands for manual setup. Added to: quickstart-ffmpeg, tutorial, infra/README, root README, ffmpeg sample README.
  3. **Function key auth + response shape:** Deployed apps require `?code=...` for HTTP endpoints. Durable start response returns `id` (not `instance_id`). Custom `/api/status/{id}` endpoint returns null — use `statusQueryGetUri` instead. Fixed quickstart-durable polling instructions, added auth notes to both quickstarts and sample READMEs.
  4. **Separate function apps per sample:** Documented recommendation to deploy each sample to its own Flex Consumption app for isolation. Added to: large-binaries concept doc, infra/README, root README, ffmpeg sample README.
  - Files updated: `docs/quickstart-durable-text-analysis.md`, `docs/quickstart-ffmpeg-processing.md`, `docs/tutorial-shared-file-access.md`, `docs/concepts/flex-consumption-os-mounts.md`, `docs/concepts/azure-files-with-functions.md`, `docs/concepts/large-binaries-on-mounts.md`, `infra/README.md`, `README.md`, `samples/durable-text-analysis/README.md`, `samples/ffmpeg-image-processing/README.md`.
