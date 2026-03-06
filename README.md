# Azure Functions Flex Consumption with Azure Files OS Mount Samples

This repository contains production-ready samples and tutorials demonstrating how to use **OS-level file system mounts** with **Azure Functions Flex Consumption** to access shared data and large binaries from Azure Files.

Whether you're building a data processing pipeline, running compute-intensive workloads with third-party executables, or coordinating work across function instances, these samples show you how to do it reliably and cost-effectively on Flex Consumption.

## 📋 What's Inside

### Two Complete Samples

| Sample | Scenario | Key Concepts |
|--------|----------|--------------|
| **[Durable Text Analysis](./samples/durable-text-analysis)** | Orchestrate parallel text file analysis using Durable Functions fan-out/fan-in pattern against files shared across instances | Durable Functions, fan-out/fan-in, shared mount access, distributed coordination |
| **[FFmpeg Image Processing](./samples/ffmpeg-image-processing)** | Process images and video using ffmpeg binary deployed on an OS mount, triggered via Blob Storage | Large binary execution on mounts, function triggers, subprocess calls, cost optimization |

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
- **Azure Functions Core Tools** — [Install](https://learn.microsoft.com/azure/azure-functions/functions-run-local?tabs=linux%2Ccsharp%2Cbash)
- **Python 3.9+** — [Install](https://www.python.org/downloads/)
- **Git** — [Install](https://git-scm.com/)

### Quick Start

Choose a scenario:

**I want to learn about parallel processing with Durable Functions:**
```bash
cd samples/durable-text-analysis
cat README.md
```
Then follow the [Durable Text Analysis Quickstart](./docs/quickstart-durable-text-analysis.md).

**I want to use large executables (ffmpeg, ImageMagick) in my functions:**
```bash
cd samples/ffmpeg-image-processing
cat README.md
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

## 🏗️ Repository Structure

```
├── README.md                           # ← You are here
├── LICENSE
├── SECURITY.md
├── CODE_OF_CONDUCT.md
│
├── samples/
│   ├── durable-text-analysis/          # Sample 1: Durable Functions + shared mounts
│   │   ├── README.md
│   │   ├── function_app.py
│   │   ├── orchestrator.py
│   │   ├── activities.py
│   │   ├── requirements.txt
│   │   └── infra/
│   │
│   └── ffmpeg-image-processing/        # Sample 2: Large binary execution on mounts
│       ├── README.md
│       ├── function_app.py
│       ├── process_image.py
│       ├── requirements.txt
│       └── infra/
│
├── infra/
│   ├── modules/                        # Shared Bicep infrastructure modules
│   │   ├── function-app.bicep
│   │   ├── storage-account.bicep
│   │   ├── azure-files-mount.bicep
│   │   └── monitoring.bicep
│   ├── scripts/
│   │   ├── setup-azure-files.sh
│   │   ├── deploy-sample.sh
│   │   └── cleanup.sh
│   └── README.md
│
└── docs/
    ├── quickstart-durable-text-analysis.md
    ├── quickstart-ffmpeg-processing.md
    ├── tutorial-shared-file-access.md
    ├── concepts/
    │   ├── flex-consumption-os-mounts.md
    │   ├── azure-files-with-functions.md
    │   └── large-binaries-on-mounts.md
    └── images/
```

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

## ❓ FAQ

**Q: Do I need to use Bicep to deploy these samples?**  
A: The samples include Bicep templates for automation, but you can also deploy resources manually via the Azure Portal or CLI scripts. See each sample's README for options.

**Q: Can I use these samples with other languages (C#, Node.js, Java)?**  
A: These samples are Python-specific. However, the concepts (OS mounts, Flex Consumption, Durable Functions) apply across languages. Adapt the code to your language using the [Azure Functions documentation](https://learn.microsoft.com/azure/azure-functions/).

**Q: What are the limits for file shares mounted on Flex Consumption?**  
A: See [Azure Files quotas and performance](https://learn.microsoft.com/azure/storage/files/storage-files-scale-targets) and [Flex Consumption limits](https://learn.microsoft.com/azure/azure-functions/flex-consumption-plan). Key: Flex Consumption instances are Linux-based and handle SMB mounts efficiently.

**Q: Can I mount multiple shares on the same function app?**  
A: Yes. Each mount uses a unique local path on the function container. See [Azure Files with Functions](./docs/concepts/azure-files-with-functions.md) for configuration details.

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
