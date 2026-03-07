# Project Context

- **Owner:** Thiago Almeida
- **Project:** Azure Functions Flex Consumption samples and documentation for Azure Files OS share mounts. Demonstrating how to share data between function instances or between multiple apps using OS mount points.
- **Stack:** Python, Azure Functions (Flex Consumption), Durable Functions, Azure Files, ffmpeg
- **Key scenarios:** (1) Python + Durable Functions orchestrating parallel text file analysis against shared mounted files, (2) ffmpeg/image processing using large executables on shared OS mounts
- **Goal:** Official documentation tutorials + Azure Samples gallery entries showing Flex Consumption + Azure Files is production-ready
- **Created:** 2026-03-06

## Learnings

<!-- Append new learnings below. Each entry is something lasting about the project. -->

- **2026-03-06 — Project structure finalized (affects Inara's work).** Repo uses `samples/` (self-contained per Azure Samples gallery convention), `infra/modules/` (shared Bicep), `docs/` (learn.microsoft.com-ready). Inara will write docs in `docs/` (quickstarts, tutorials, concepts) and sample READMEs in each `samples/*/README.md`. Docs pipeline separate from sample deployment logic. Decision: `.squad/decisions.md`.

- **2026-03-06 — Full documentation suite completed (Inara).** Created comprehensive docs covering all required files: Root README (project overview, links, FAQ), two quickstarts (durable text analysis, ffmpeg processing with step-by-step guides), tutorial on shared file access patterns (when/why/how to use mounts), and three conceptual docs (Flex Consumption basics, Azure Files setup, large binary patterns). All follow Microsoft Learn style, include callouts, code examples with language tags, and progressive disclosure from simple to advanced. Docs reference sample paths like `samples/durable-text-analysis/function_app.py` — code may need minor alignment later but tutorial flow is complete.

- **2026-03-06 — Samples and tests complete.** Kaylee delivered 19 files (2 sample apps + shared infra). Zoe delivered 55 passing tests across 3 suites with CI workflow. Docs are aligned with sample code paths and test coverage expectations. See `.squad/orchestration-log/2026-03-06T19-43-kaylee.md` and `.squad/orchestration-log/2026-03-06T19-43-zoe.md`.

- **2026-03-06 — Doc review and fixes (Kaylee assigned).** Mal's full code review rejected all 7 docs for systematic misalignment (mount paths, HTTP endpoints, response schemas, share names, infra references, mount config mechanism). Inara (original author) was locked out; Kaylee reassigned to fix since she knows actual code. All docs now align: `/mnt/` → `/mounts/`, endpoints corrected, schemas updated, share names fixed, infra references point to actual deploy scripts, mount config mechanism updated from app settings to site config property. Removed dead Pillow dependency. All 67 tests pass. See `.squad/orchestration-log/2026-03-06T20-00-kaylee.md` and `.squad/decisions.md` (Decision: Doc-Code Alignment Fixes).

- **2026-03-07 — Deployment gotchas documented across all 10 files (Kaylee).** After live Azure testing of both samples, four critical gotchas were identified and documented: (1) `allowSharedKeyAccess` enterprise Azure Policy workaround (tag: `Az.Sec.DisableLocalAuth.Storage::Skip`), (2) EventGrid system topic manual setup for Flex Consumption blob triggers, (3) Function key auth (`?code=` query param) + Durable Functions response schema (`id` not `instance_id`, use `statusQueryGetUri` for polling), (4) separate function app per sample pattern. Updated all 10 docs with Microsoft Learn callout syntax (`> [!IMPORTANT]`, `> [!NOTE]`). See `.squad/orchestration-log/2026-03-07T00-12-13-kaylee.md` and `.squad/decisions.md` (Decision: Document All Deployment Gotchas from Live Testing).
