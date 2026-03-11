# Azure Functions Flex Consumption with Azure Files OS Mount Samples

This repository contains production-ready samples and tutorials demonstrating how to use **OS-level file system mounts** with **Azure Functions Flex Consumption** to access shared data and large binaries from Azure Files.

Whether you're building a data processing pipeline, running compute-intensive workloads with third-party executables, or coordinating work across function instances, these samples show you how to do it reliably and cost-effectively on Flex Consumption.

## 📋 What's Inside

### Two Complete Samples

Each sample is a fully self-contained, `azd`-compatible project with its own infrastructure using Azure Verified Modules (AVM).

| Sample | Scenario | Key Concepts |
|--------|----------|--------------|
| **[Durable Text Analysis](./durable-text-analysis)** | Orchestrate parallel text file analysis using Durable Functions fan-out/fan-in pattern against files shared across instances | Durable Functions, fan-out/fan-in, shared mount access, distributed coordination |
| **[FFmpeg Image Processing](./ffmpeg-image-processing)** | Process images and video using ffmpeg binary deployed on an OS mount, triggered via EventGrid Blob Storage events | Large binary execution on mounts, function triggers, subprocess calls, cost optimization |

### Documentation

- **[Getting Started](#getting-started)** — Choose your path
- **[Quickstart: Durable Text Analysis](./docs/quickstart-durable-text-analysis.md)** — 10 minutes to your first orchestrated analysis
- **[Quickstart: FFmpeg Image Processing](./docs/quickstart-ffmpeg-processing.md)** — 10 minutes to your first converted image
- **[Tutorial: Shared File Access Patterns](./docs/tutorial-shared-file-access.md)** — Deep-dive into when, how, and why to use OS mounts
- **[Concepts: Flex Consumption & OS Mounts](./docs/concepts/flex-consumption-os-mounts.md)** — Understand the platform
- **[Concepts: Azure Files with Functions](./docs/concepts/azure-files-with-functions.md)** — Integration patterns and setup
- **[Concepts: Running Large Binaries on Mounts](./docs/concepts/large-binaries-on-mounts.md)** — Patterns for ffmpeg, ImageMagick, and similar tools

## 🚀 Getting Started

### Prerequisites

Before you begin, you'll need:

- **Azure subscription** — [Create a free account](https://azure.microsoft.com/free/) if you don't have one
- **Azure CLI** — [Install](https://learn.microsoft.com/cli/azure/install-azure-cli)
- **Azure Developer CLI (azd)** — [Install](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd)
- **Python 3.11** — [Install](https://www.python.org/downloads/)
- **Git** — [Install](https://git-scm.com/)

### Quick Start

Choose a scenario:

**I want to learn about parallel processing with Durable Functions:**
```bash
cd durable-text-analysis
azd up
```
Then follow the [Durable Text Analysis Quickstart](./docs/quickstart-durable-text-analysis.md).

**I want to use large executables (ffmpeg, ImageMagick) in my functions:**
```bash
cd ffmpeg-image-processing
azd up
```
Then follow the [FFmpeg Image Processing Quickstart](./docs/quickstart-ffmpeg-processing.md).

**I need to understand when and how to use OS mounts:**
Read [Shared File Access Patterns](./docs/tutorial-shared-file-access.md) first, then pick a sample.

## 💡 Why OS Mounts?

Traditional Azure Functions rely on **bindings** (blob input/output bindings, queue triggers, etc.). These are powerful but have limits:

- Bindings move data into/out of the function execution context (network overhead for large files)
- You can't easily run large third-party binaries (they'd bloat your deployment artifact)
- Sharing state or files between *multiple function instances* requires external coordination

**OS-level mounts** let you:
- Access files as if they're on your local disk (POSIX semantics)
- Mount the same Azure Files share on every instance of your function app (shared access)
- Deploy large binaries once on the mount and run them from any instance
- Reduce cold start time by keeping artifacts off your deployment package

The catch? Mounts only work on **Flex Consumption** (and App Service). Premium and Consumption plans don't support them yet.

## 📖 Learning Paths

### Path 1: I'm New to Azure Functions

1. Read: [Flex Consumption & OS Mounts](./docs/concepts/flex-consumption-os-mounts.md)
2. Read: [Azure Files with Functions](./docs/concepts/azure-files-with-functions.md)
3. Follow: [Durable Text Analysis Quickstart](./docs/quickstart-durable-text-analysis.md)
4. Read: [Shared File Access Patterns](./docs/tutorial-shared-file-access.md) for security and best practices

### Path 2: I Need to Run Large Binaries

1. Read: [Running Large Binaries on Mounts](./docs/concepts/large-binaries-on-mounts.md)
2. Follow: [FFmpeg Image Processing Quickstart](./docs/quickstart-ffmpeg-processing.md)
3. Adapt the pattern to your executable (ImageMagick, LibreOffice, etc.)

### Path 3: I Need Distributed Coordination

1. Read: [Shared File Access Patterns](./docs/tutorial-shared-file-access.md)
2. Follow: [Durable Text Analysis Quickstart](./docs/quickstart-durable-text-analysis.md)
3. Learn more: [Durable Functions documentation](https://learn.microsoft.com/azure/azure-functions/durable/durable-functions-overview)

## 🔒 Security & Best Practices

- **Use Managed Identity** — Authenticate to Azure Storage without storing keys
- **RBAC** — Assign the minimum permissions needed (e.g., Storage File Data SMB Share Contributor)
- **Mount Options** — Mounts are read-write by default; restrict to read-only if your workload allows
- **Quotas** — Set Azure Files share quotas to prevent runaway storage costs

See [Shared File Access Patterns](./docs/tutorial-shared-file-access.md) for detailed guidance.

## ⚠️ Known Issues & Deployment Gotchas

These were discovered during live end-to-end Azure testing. Read them before deploying.

| Gotcha | Impact | Details |
|--------|--------|---------|
| **`allowSharedKeyAccess` and enterprise policy** | Azure Files mounts fail silently | Enterprise subscriptions may enforce `allowSharedKeyAccess: false`. Add tag `Az.Sec.DisableLocalAuth.Storage::Skip` to exempt the storage account. This is configured in the sample bicep templates. |
| **EventGrid system topic** | Blob trigger never fires | Flex Consumption EventGrid blob triggers require creation of the EventGrid system topic and event subscription. This is configured in the ffmpeg sample is a post deploy shell script called by AZD. |
| **Function key required for HTTP endpoints** | `401 Unauthorized` on deployed app | Include `?code=<function-key>` in all HTTP requests. Get the key via `az functionapp keys list` or Azure Portal. |
| **Durable Functions response shape** | Polling may fail | The start endpoint returns a management payload. Use the `statusQueryGetUri` from the response to poll orchestration status. |

For deployment troubleshooting, see each sample's README.

## ❓ FAQ

**Q: Do I need to use Bicep to deploy these samples?**  
A: The samples use `azd` (Azure Developer CLI) which orchestrates Bicep deployment. You can run `azd up` to deploy everything automatically, or use the Bicep templates manually with `az deployment sub create`.

**Q: Can I use these samples with other languages (C#, Node.js, Java)?**  
A: These samples are Python-specific. However, the concepts (OS mounts, Flex Consumption, Azure Files) apply across languages. The infrastructure (Bicep templates) can be reused for any language runtime.

**Q: What are the limits for file shares mounted on Flex Consumption?**  
A: See [Azure Files quotas and performance](https://learn.microsoft.com/azure/storage/files/storage-files-scale-targets) and [Flex Consumption limits](https://learn.microsoft.com/azure/azure-functions/flex-consumption-plan). Key: Flex Consumption instances are Linux-based and handle SMB mounts efficiently.

**Q: Can I mount multiple shares on the same function app?**  
A: Yes. Each mount uses a unique local path on the function container. The `mounts.bicep` module accepts an array of mount configurations. See [Azure Files with Functions](./docs/concepts/azure-files-with-functions.md) for configuration details.

**Q: What's the difference between an OS mount and a storage binding?**  
A: OS mounts give you direct file system access (POSIX semantics). Storage bindings are Azure SDK integrations that read/write blobs or queues via HTTP. Use bindings for cloud-to-cloud integration; use mounts when you need file system semantics or want to avoid network overhead. See [Shared File Access Patterns](./docs/tutorial-shared-file-access.md).

## 🤝 Contributing

We welcome contributions! Please see [CONTRIBUTING.md](./CONTRIBUTING.md) for guidelines.

## 📄 License

This project is licensed under the [MIT License](./LICENSE).

## 🆘 Support

- **Documentation issues?** Open an issue in this repo with the `docs` label.
- **Sample code issues?** Open an issue with the `samples` label.
- **Azure Services questions?** Visit the [Azure Support Center](https://azure.microsoft.com/support/) or [Microsoft Q&A](https://learn.microsoft.com/answers/products/).

---

**Ready to go?** Pick a quickstart above and get started in 10 minutes! 🚀
