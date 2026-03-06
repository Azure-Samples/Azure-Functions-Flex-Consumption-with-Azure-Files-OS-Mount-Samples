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
