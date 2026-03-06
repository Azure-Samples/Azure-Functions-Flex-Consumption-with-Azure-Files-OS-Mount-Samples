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
