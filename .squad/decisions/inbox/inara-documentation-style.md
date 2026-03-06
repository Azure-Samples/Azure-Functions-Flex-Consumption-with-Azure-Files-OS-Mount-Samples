---
date: 2026-03-06
author: Inara
---

# Decision: Documentation Style and Structure

## Context

The full documentation suite for Azure Functions Flex Consumption + Azure Files OS mounts needed to be created. This included root README, quickstart tutorials, a deep-dive tutorial, and conceptual guides.

## Decision

All documentation follows **Microsoft Learn documentation style guide** with:

1. **Progressive Disclosure** — Start simple, advance gradually. Each quickstart has 6 structured steps (prerequisites → what you'll build → resource creation → configuration → deployment → verification → cleanup).

2. **Callout Blocks** — Key information highlighted using `> [!NOTE]`, `> [!TIP]`, `> [!WARNING]` syntax (learn.microsoft.com standard).

3. **Code Examples with Language Tags** — Every code block includes language tag and context (e.g., `# In function_app.py` or `# In bicep template`).

4. **Explicit Terminal Output** — Tutorials show expected terminal output where it reduces ambiguity (e.g., after `az deployment group create`).

5. **Security and Cost Caveats** — Every tutorial includes cleanup section and warnings about resource deletion. Concepts docs explain quotas and limits upfront.

6. **Conceptual Diagrams (Described)** — Architecture described in ASCII or conceptual boxes. Full diagrams can be added to `docs/images/` later by visual design.

## Rationale

- **Learn.microsoft.com compatibility** — Enables documentation to be imported into official Azure docs pipeline
- **Consistency** — All docs follow same structure and tone, making them scannable and trustworthy
- **Accessibility** — Progressive disclosure means beginners don't get overwhelmed; experts can skip to concepts
- **Testability** — Each quickstart is designed to be followable start-to-finish with real Azure resources
- **Security-first** — Managed identity, RBAC, quotas explained upfront

## What's Documented

1. **README.md** — Project overview, links to samples and docs, FAQ, learning paths
2. **quickstart-durable-text-analysis.md** — 10-minute tutorial for Sample 1 (Durable Functions orchestration)
3. **quickstart-ffmpeg-processing.md** — 10-minute tutorial for Sample 2 (large binary execution)
4. **tutorial-shared-file-access.md** — Comprehensive guide: when to use mounts vs. bindings, security, best practices
5. **concepts/flex-consumption-os-mounts.md** — What is Flex Consumption, what are OS mounts, how they combine
6. **concepts/azure-files-with-functions.md** — Azure Files setup, RBAC, mounting, troubleshooting
7. **concepts/large-binaries-on-mounts.md** — Pattern for running ffmpeg, ImageMagick, etc. on mounts

## Technical Alignment

Documentation references:
- `samples/durable-text-analysis/function_app.py` (code may need minor alignment)
- `samples/ffmpeg-image-processing/function_app.py` (code may need minor alignment)
- `infra/modules/function-app.bicep` (shared Bicep modules)
- `infra/modules/storage-account.bicep`
- `infra/scripts/setup-azure-files.sh`

Sample READMEs (to be written by Kaylee) will be self-contained "how to deploy this sample" guides; docs in `docs/` are "understand this pattern" guides.

## Impact

- **Kaylee** can reference these docs when writing sample code; quickstarts provide expected behavior
- **Zoe** can use docs as basis for test coverage (e.g., "quickstart should pass end-to-end")
- **Customers** get learn.microsoft.com-ready documentation without modification

## Out of Scope

- Screenshots and visual diagrams (can be added later)
- Internationalization (en-US only for v1)
- Video tutorials (can be created as addendum)
