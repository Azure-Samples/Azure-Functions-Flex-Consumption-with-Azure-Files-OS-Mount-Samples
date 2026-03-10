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

- **2026-03-07 — Project restructured with AVM-based Bicep (per-sample infra).** Migrated from shared `infra/` to per-sample modular infrastructure. Each sample (durable-text-analysis/, ffmpeg-image-processing/) now has own azure.yaml (azd manifest), infra/main.bicep (subscription-scoped, AVM refs), modular Bicep (function.bicep, rbac.bicep, mounts.bicep, eventgrid.bicep), and scripts/post-up.sh. Removed legacy shared infra patterns. All samples independently deployable via `azd up` and AVM-compliant. See `.squad/orchestration-log/2026-03-07T16-55-15-kaylee.md`.

- **2026-03-07 — Documentation updated with deployment gotchas (10 files, all live).** After end-to-end deployment and testing, updated all documentation to reflect 4 key gotchas: (1) `allowSharedKeyAccess` + enterprise policy requires `Az.Sec.DisableLocalAuth.Storage::Skip` tag; (2) EventGrid system topic not auto-created for Flex Consumption blob triggers — manual CLI setup required; (3) Function key auth requires `?code=` query param, Durable response schema uses `id` (not `instance_id`), use `statusQueryGetUri` for polling; (4) Separate function apps per sample for isolation/scaling. Updated: quickstart-durable, quickstart-ffmpeg, tutorial, 3 concept docs, infra/README, root README, 2 sample READMEs. All docs use Microsoft Learn callout syntax (`> [!IMPORTANT]`, `> [!NOTE]`). See `.squad/orchestration-log/2026-03-07T00-12-13-kaylee.md` and `.squad/decisions.md`.

- **2026-03-07 — Fixed ffmpeg-image-processing deployment (chicken-and-egg EventGrid fix).** Deleted `infra/app/eventgrid.bicep` and removed the eventGridSubscription module from `main.bicep`. EventGrid *subscription* creation moved to `scripts/post-up.sh` (postdeploy hook) because the `blobs_extension` system key only exists after function code is deployed. The system *topic* stays in Bicep (no code dependency). Key learnings: (1) `@app.blob_trigger(source="EventGrid")` requires the **blob extension** webhook at `/runtime/webhooks/blobs?functionName=Host.Functions.{funcName}&code={blobs_extension}`, NOT the EventGrid webhook; (2) `listKeys()` in Bicep for system keys fails during initial provision when no code is deployed; (3) `--auth-mode key` is more reliable than `--auth-mode login` for Azure Files upload in scripts; (4) Removed stale `main.json` to avoid confusion — azd uses `main.bicep` directly. Also added `AZURE_EVENTGRID_TOPIC_NAME` output, retry logic for system key retrieval, and health check verification to post-up.sh.

- **2026-03-10 — Durable-text-analysis deployed and tested E2E.** Three critical fixes were needed: (1) **AVM web/site:0.15.1 does NOT propagate `functionAppConfig`** — replaced with direct `Microsoft.Web/sites@2024-04-01` resource. Without `functionAppConfig`, Flex Consumption deployment storage auth fails with 403. (2) **AVM storage-account:0.8.3 defaults to `publicNetworkAccess: None` and `defaultAction: Deny`** — must explicitly set `publicNetworkAccess: 'Enabled'` and `networkAcls: { defaultAction: 'Allow', bypass: 'AzureServices' }` for function app to reach storage. (3) **User-assigned identity requires full AzureWebJobsStorage settings** — `__credential: 'managedidentity'`, `__clientId`, and all three service URIs (`__blobServiceUri`, `__queueServiceUri`, `__tableServiceUri`). Also upgraded function app blob RBAC to `StorageBlobDataOwner`. `azd deploy` failed with Kudu restart issues — `func azure functionapp publish` is more reliable for initial deployment. Orchestration completed: 3 text files analyzed via fan-out/fan-in from `/mounts/data/`.
