# Azure Functions Flex Consumption with Azure Files OS Mount Samples

This repository contains samples that demonstrate how to use **OS-level file system mounts** with **Azure Functions Flex Consumption** to access shared files and large binaries from Azure Files.

Each sample is an [Azure Developer CLI (azd)](https://learn.microsoft.com/azure/developer/azure-developer-cli/overview) template that provisions infrastructure using [Azure Verified Modules (AVM)](https://aka.ms/avm) Bicep modules, deploys function code, and runs post-deployment setup — all with a single `azd up` command.

## Samples

| Sample | Scenario | Key Concepts |
|--------|----------|--------------|
| [FFmpeg Image Processing](./ffmpeg-image-processing) | Process images using an ffmpeg binary on an Azure Files OS mount, triggered by EventGrid blob events | Large binary on mount, EventGrid blob trigger, subprocess calls |
| [Durable Text Analysis](./durable-text-analysis) | Orchestrate parallel text file analysis using Durable Functions fan-out/fan-in against files on a shared mount | Durable Functions, fan-out/fan-in, shared mount across instances |

## Prerequisites

- An Azure subscription — [Create a free account](https://azure.microsoft.com/free/)
- [Azure Developer CLI (azd)](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd) version 1.9.0 or later
- [Git](https://git-scm.com/)

## Getting started

1. Clone this repository:

   ```bash
   git clone https://github.com/Azure-Samples/Azure-Functions-Flex-Consumption-with-Azure-Files-OS-Mount-Samples.git
   ```

2. Navigate to a sample folder and follow the instructions in its README.

## Why OS mounts?

OS-level mounts let your function app access an Azure Files share as a local file system path. This means you can:

- **Run large binaries** (ffmpeg, ImageMagick) from a mount instead of bundling them in your deployment package, keeping cold starts fast.
- **Share files across instances** — every instance of your function app sees the same mounted share.
- **Use POSIX file I/O** — read and write files with standard file system calls instead of SDK-based blob operations.

OS mounts are supported on **Flex Consumption** and **Elastic Premium** plans (Linux only). For more information, see [Choose a file access strategy for Azure Functions](https://learn.microsoft.com/azure/azure-functions/concept-file-access-options).

## Cross-platform support

Each sample includes post-deployment scripts for both platforms:

- `scripts/post-up.sh` — Bash (Linux, macOS, Git Bash on Windows, Cloud Shell)
- `scripts/post-up.ps1` — PowerShell (Windows)

The `azure.yaml` configuration automatically selects the correct script for your OS.

## Tutorials

Step-by-step tutorials for these samples are available on Microsoft Learn:

- [Tutorial: Process images by using FFmpeg on a mounted Azure Files share](https://learn.microsoft.com/azure/azure-functions/tutorial-ffmpeg-processing-azure-files)
- [Tutorial: Durable text analysis with a mounted Azure Files share](https://learn.microsoft.com/azure/azure-functions/durable/tutorial-durable-text-analysis-azure-files)

## Related documentation

- [Azure Functions Flex Consumption plan](https://learn.microsoft.com/azure/azure-functions/flex-consumption-plan)
- [Choose a file access strategy for Azure Functions](https://learn.microsoft.com/azure/azure-functions/concept-file-access-options)
- [Storage considerations for Azure Functions](https://learn.microsoft.com/azure/azure-functions/storage-considerations)
- [Azure Files documentation](https://learn.microsoft.com/azure/storage/files/)
- [Azure Developer CLI documentation](https://learn.microsoft.com/azure/developer/azure-developer-cli/)
