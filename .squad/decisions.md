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

### Decision: Sample Implementation Patterns

**Author:** Kaylee (Cloud Dev)  
**Date:** 2026-03-06  
**Status:** Implemented

#### Context

Built both sample apps and shared infra. Recording implementation patterns the team should know.

#### Decisions

1. **Durable Functions use `df.Blueprint()`** — orchestrator and activities live in separate modules (`orchestrator.py`, `activities.py`) and register via `app.register_functions(bp)` in `function_app.py`. This keeps the entry point clean.

2. **ffmpeg sample uses stdin/stdout pipes** — no temporary files written to local disk. Flex Consumption instances have limited local storage, so piping through subprocess is safer.

3. **Blob trigger uses `source="EventGrid"`** — Flex Consumption defaults to Event Grid-based blob triggers for near-instant response. This is set explicitly in the decorator.

4. **Mount config is a separate Bicep module** — `azure-files-mount.bicep` patches an existing function app via `existing` keyword. Must deploy after the function app. This avoids circular dependencies.

5. **All scripts are idempotent** — `setup-azure-files.sh` uses `|| true` on share creation so re-runs don't fail. `cleanup.sh` checks existence before deleting.

#### Impact

- **Inara**: Sample READMEs are written with quickstart instructions. Full tutorial docs can reference these directly.
- **Zoe**: Python files all parse clean. Test targets: `activities.py` (unit-testable analysis logic), `process_image.py` (mock subprocess for ffmpeg tests).
- **Mal**: Bicep modules follow the shared-module pattern from the architecture decision. Each sample could get its own `infra/main.bicep` that references `../../infra/modules/`.

### Decision: Documentation Style and Structure

**Author:** Inara (DevRel)  
**Date:** 2026-03-06  
**Status:** Implemented

#### Context

The full documentation suite for Azure Functions Flex Consumption + Azure Files OS mounts needed to be created. This included root README, quickstart tutorials, a deep-dive tutorial, and conceptual guides.

#### Decision

All documentation follows **Microsoft Learn documentation style guide** with:

1. **Progressive Disclosure** — Start simple, advance gradually. Each quickstart has 6 structured steps (prerequisites → what you'll build → resource creation → configuration → deployment → verification → cleanup).

2. **Callout Blocks** — Key information highlighted using `> [!NOTE]`, `> [!TIP]`, `> [!WARNING]` syntax (learn.microsoft.com standard).

3. **Code Examples with Language Tags** — Every code block includes language tag and context (e.g., `# In function_app.py` or `# In bicep template`).

4. **Explicit Terminal Output** — Tutorials show expected terminal output where it reduces ambiguity (e.g., after `az deployment group create`).

5. **Security and Cost Caveats** — Every tutorial includes cleanup section and warnings about resource deletion. Concepts docs explain quotas and limits upfront.

6. **Conceptual Diagrams (Described)** — Architecture described in ASCII or conceptual boxes. Full diagrams can be added to `docs/images/` later by visual design.

#### Rationale

- **Learn.microsoft.com compatibility** — Enables documentation to be imported into official Azure docs pipeline
- **Consistency** — All docs follow same structure and tone, making them scannable and trustworthy
- **Accessibility** — Progressive disclosure means beginners don't get overwhelmed; experts can skip to concepts
- **Testability** — Each quickstart is designed to be followable start-to-finish with real Azure resources
- **Security-first** — Managed identity, RBAC, quotas explained upfront

#### What's Documented

1. **README.md** — Project overview, links to samples and docs, FAQ, learning paths
2. **quickstart-durable-text-analysis.md** — 10-minute tutorial for Sample 1 (Durable Functions orchestration)
3. **quickstart-ffmpeg-processing.md** — 10-minute tutorial for Sample 2 (large binary execution)
4. **tutorial-shared-file-access.md** — Comprehensive guide: when to use mounts vs. bindings, security, best practices
5. **concepts/flex-consumption-os-mounts.md** — What is Flex Consumption, what are OS mounts, how they combine
6. **concepts/azure-files-with-functions.md** — Azure Files setup, RBAC, mounting, troubleshooting
7. **concepts/large-binaries-on-mounts.md** — Pattern for running ffmpeg, ImageMagick, etc. on mounts

#### Technical Alignment

Documentation references:
- `samples/durable-text-analysis/function_app.py` (code may need minor alignment)
- `samples/ffmpeg-image-processing/function_app.py` (code may need minor alignment)
- `infra/modules/function-app.bicep` (shared Bicep modules)
- `infra/modules/storage-account.bicep`
- `infra/scripts/setup-azure-files.sh`

Sample READMEs (to be written by Kaylee) will be self-contained "how to deploy this sample" guides; docs in `docs/` are "understand this pattern" guides.

#### Impact

- **Kaylee** can reference these docs when writing sample code; quickstarts provide expected behavior
- **Zoe** can use docs as basis for test coverage (e.g., "quickstart should pass end-to-end")
- **Customers** get learn.microsoft.com-ready documentation without modification

### Decision: Test Infrastructure and Conventions

**Author:** Zoe (Tester)  
**Date:** 2026-03-06  
**Status:** Implemented

#### Context

Tests need to run in CI without Azure resources, ffmpeg binaries, or Azure Functions runtime.

#### Decisions

1. **Tests live at repo root `tests/`**, not inside each sample directory. This keeps test deps separate from sample deps customers would copy.

2. **All Azure runtime interfaces are mocked** — mount paths use `tmp_path`, Durable Functions context is a MagicMock factory, blob inputs are mock InputStreams. No real Azure SDK calls in unit tests.

3. **ffmpeg subprocess calls are mocked** via `unittest.mock.patch("subprocess.run")`. CI doesn't need the ffmpeg binary.

4. **Assumed activity function names:** `list_files`, `analyze_text`, `aggregate_results`. If Kaylee uses different names, tests need a find-replace — the contract is documented.

5. **Bicep validation** uses `az bicep build` and skips gracefully if Azure CLI is absent or no `.bicep` files exist yet.

6. **CI workflow** (`.github/workflows/ci.yml`) runs Python 3.9/3.10/3.11 matrix with coverage and a separate Bicep validation job.

7. **Integration tests requiring real Azure resources are deferred.** Marked with `@pytest.mark.integration` when added later.

#### Impact

- **Kaylee:** Activity function names and module paths must match or tests need updating.
- **Mal:** CI workflow is ready; just merge and enable.
- **Inara:** Tutorial steps can reference `pytest tests/` as the validation command.

## Governance

- All meaningful changes require team consensus
- Document architectural decisions here
- Keep history focused on work, decisions focused on direction
