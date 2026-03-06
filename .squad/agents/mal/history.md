# Project Context

- **Owner:** Thiago Almeida
- **Project:** Azure Functions Flex Consumption samples and documentation for Azure Files OS share mounts. Demonstrating how to share data between function instances or between multiple apps using OS mount points.
- **Stack:** Python, Azure Functions (Flex Consumption), Durable Functions, Azure Files, ffmpeg
- **Key scenarios:** (1) Python + Durable Functions orchestrating parallel text file analysis against shared mounted files, (2) ffmpeg/image processing using large executables on shared OS mounts
- **Goal:** Official documentation tutorials + Azure Samples gallery entries showing Flex Consumption + Azure Files is production-ready
- **Created:** 2026-03-06

## Learnings

<!-- Append new learnings below. Each entry is something lasting about the project. -->

- **2026-03-06 — Project structure decided.** Repo uses `samples/` (self-contained per Azure Samples gallery convention), `infra/modules/` (shared Bicep), `docs/` (learn.microsoft.com-ready). Decision doc: `.squad/decisions/inbox/mal-project-structure.md`.
- **Key paths:** `samples/durable-text-analysis/`, `samples/ffmpeg-image-processing/`, `infra/modules/`, `docs/`, `docs/concepts/`.
- **Architecture choice:** Python v2 programming model (single `function_app.py` per sample). No `function.json` files.
- **Scope control:** Python only for v1. No .NET/Node/Java. No Terraform. No Durable Entities sample yet.
- **User preference:** Thiago wants official-quality docs + samples. Aiming for Azure Samples gallery + learn.microsoft.com tutorials.
- **2026-03-06 — Full build review complete.** Reviewed all 19 sample files, 7 docs, 55 tests, CI workflow. Two blocking issues found: (1) Systematic doc-code misalignment — quickstarts use wrong mount paths (/mnt/ vs /mounts/), wrong HTTP endpoints, wrong output schemas, wrong share names, and reference non-existent per-sample infra files. Assigned to Kaylee. (2) Sequential mount deployments in deploy-sample.sh overwrite each other because azure-files-mount.bicep replaces the entire azureStorageAccounts config. Assigned to Zoe. Sample code patterns, Azure best practices, test coverage, and scope are all solid. Verdict: `.squad/decisions/inbox/mal-code-review-verdict.md`.
- **Mount path convention:** Flex Consumption requires `/mounts/` prefix (not `/mnt/`). All code and Bicep are correct; all docs are wrong. This is the #1 customer-facing bug.
- **Test-code name gap:** Tests use `list_files`/`analyze_text`; actual activities are `list_text_files`/`analyse_text_file`. Tests pass because they mock the pattern, not import real code. Not blocking but worth tracking for future integration tests.

- **2026-03-06 — Code review verdict issued and fixes tracked.** Full code review verdict documented: CONDITIONAL APPROVAL with 4 approved areas (with notes) and 2 blocking rejections. Kaylee assigned to fix all 7 documentation files (completed successfully: mount paths, endpoints, schemas, share names, infra references, config mechanism). Zoe assigned to fix mount overwrite bug via plural module pattern (completed successfully: 12 new regression tests, all 67 tests pass). Both fixes now documented in decisions.md and orchestration logs. Ready for re-review of both Kaylee's and Zoe's work.
