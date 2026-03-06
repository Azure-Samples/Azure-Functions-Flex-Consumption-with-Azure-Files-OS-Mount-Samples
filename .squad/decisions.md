# Squad Decisions

## Active Decisions

### Decision: Repository Project Structure

**Author:** Mal (Lead)  
**Date:** 2026-03-06  
**Status:** Proposed

#### Context

We need a repository structure that:
- Houses two self-contained Azure Functions samples (Python Durable Functions text analysis, ffmpeg image processing)
- Follows Azure Samples gallery conventions (each sample stands alone with README, code, infra, and deployment steps)
- Includes documentation that can feed into official Azure docs (tutorials, quickstarts, conceptual)
- Shares common infrastructure (Bicep modules, scripts) without coupling the samples together

#### Decision

```
AzureFilesSampleAndDocs/
│
├── README.md                          # Repo overview, links to samples & docs
├── LICENSE
├── SECURITY.md
├── CODE_OF_CONDUCT.md
├── CONTRIBUTING.md
│
├── samples/
│   ├── durable-text-analysis/         # Sample 1: Durable Functions + Azure Files
│   │   ├── README.md                  # Self-contained: what it does, prereqs, deploy, run
│   │   ├── function_app.py            # Azure Functions Flex Consumption app (v2 model)
│   │   ├── orchestrator.py            # Durable orchestrator — fan-out/fan-in over files
│   │   ├── activities.py              # Activity functions — read/analyze text files
│   │   ├── requirements.txt
│   │   ├── host.json
│   │   ├── local.settings.json.example
│   │   └── infra/
│   │       ├── main.bicep             # Deploys this sample end-to-end
│   │       └── main.bicepparam        # Parameter file
│   │
│   └── ffmpeg-image-processing/       # Sample 2: ffmpeg on OS-mounted share
│       ├── README.md                  # Self-contained: what it does, prereqs, deploy, run
│       ├── function_app.py            # Azure Functions Flex Consumption app (v2 model)
│       ├── process_image.py           # Image/video processing logic using ffmpeg binary
│       ├── requirements.txt
│       ├── host.json
│       ├── local.settings.json.example
│       └── infra/
│           ├── main.bicep             # Deploys this sample end-to-end
│           └── main.bicepparam        # Parameter file
│
├── infra/
│   ├── modules/
│   │   ├── function-app.bicep         # Flex Consumption function app + plan
│   │   ├── storage-account.bicep      # Storage account with Azure Files share
│   │   ├── azure-files-mount.bicep    # OS-level share mount config on the function app
│   │   └── monitoring.bicep           # App Insights + Log Analytics (optional)
│   ├── scripts/
│   │   ├── setup-azure-files.sh       # CLI script: create share, set quotas, upload seed data
│   │   ├── deploy-sample.sh           # CLI script: deploy a sample by name
│   │   └── cleanup.sh                 # Tear down resource group
│   └── README.md                      # How infra modules work and compose
│
├── docs/
│   ├── quickstart-durable-text-analysis.md    # 10-minute quickstart
│   ├── quickstart-ffmpeg-processing.md        # 10-minute quickstart
│   ├── tutorial-shared-file-access.md         # Deep-dive tutorial
│   ├── concepts/
│   │   ├── flex-consumption-os-mounts.md      # What OS mounts are, how they work
│   │   ├── azure-files-with-functions.md      # Azure Files integration patterns
│   │   └── large-binaries-on-mounts.md        # Pattern: shipping ffmpeg/other binaries via mount
│   └── images/                                # Architecture diagrams
│       └── .gitkeep
│
├── .github/
│   ├── workflows/
│   │   ├── ci.yml                     # Lint + validate Bicep + dry-run tests
│   │   └── deploy-samples.yml         # Manual dispatch: deploy a sample to Azure
│   └── ISSUE_TEMPLATE/
│       └── bug_report.md
│
└── .squad/                            # Team coordination (already exists)
```

#### Rationale

1. **`samples/` with self-contained folders** — Azure Samples gallery convention. Each sample has its own README, code, infra, and requirements. A customer can clone one folder and go. No cross-sample dependencies.

2. **`infra/modules/` for shared Bicep** — Both samples need a Flex Consumption function app, a storage account, and an Azure Files mount. Shared modules avoid drift. Each sample's `infra/main.bicep` references these shared modules. If a customer only wants one sample, the sample's own `main.bicep` is the entry point — it just happens to call shared modules from `../../infra/modules/`.

3. **`docs/` separate from samples** — Docs are for the learn.microsoft.com pipeline. Quickstarts map 1:1 to samples. Concepts stand alone. Tutorials can span samples. This keeps sample READMEs focused on "deploy and run" while docs handle "understand and learn."

4. **Python v2 programming model** — Flex Consumption supports the v2 model. Single `function_app.py` entry point per sample. No `function.json` files. This is the modern approach and what new customers should learn.

5. **`local.settings.json.example` not `local.settings.json`** — The real file is in `.gitignore`. The example file documents what values are needed without leaking secrets.

6. **No monorepo tooling** — Two samples don't need Nx, Turborepo, or shared virtual environments. Each sample is pip-installable on its own. Keep it simple.

#### What's Out of Scope (Deferred)

- **.NET / Node.js / Java samples** — Python first. Add other languages only if there's explicit demand.
- **Terraform alternative** — Bicep is the Azure-native choice. Terraform can come later.
- **Sample for Durable Entities** — Interesting pattern with shared state on mounts, but not in v1 scope.

#### Impact

- **Kaylee** builds sample code inside `samples/*/`
- **Inara** writes docs in `docs/` and sample READMEs in `samples/*/README.md`
- **Zoe** writes tests that live alongside or reference each sample
- **Shared infra** is a joint concern — Kaylee writes the Bicep, Mal reviews

## Governance

- All meaningful changes require team consensus
- Document architectural decisions here
- Keep history focused on work, decisions focused on direction
