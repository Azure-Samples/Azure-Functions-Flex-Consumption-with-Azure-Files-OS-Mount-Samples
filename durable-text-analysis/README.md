<!--
---
name: Durable text analysis with Azure Functions Flex Consumption and Azure Files
description: Python Durable Functions fan-out/fan-in sample that analyzes text files from an Azure Files OS mount on Azure Functions Flex Consumption, provisioned and deployed with azd and Bicep.
page_type: sample
products:
- azure-functions
- azure-files
- azure-storage
- azure
urlFragment: functions-flex-consumption-durable-text-analysis-azure-files
languages:
- python
- bicep
- azdeveloper
---
-->

# Durable Text Analysis Sample

A Durable Functions fan-out/fan-in orchestration that analyzes text files stored on an Azure Files OS mount in a Flex Consumption function app. An HTTP trigger starts the orchestration, which fans out to analyze each text file in parallel and aggregates the results.

## Architecture

- **Azure Functions (Flex Consumption)** — Serverless compute with OS-level mount support
- **Durable Functions** — Stateful orchestration with fan-out/fan-in pattern
- **Azure Files** — SMB share mounted at `/mounts/data/` containing text files
- **Application Insights** — Monitoring and telemetry
- **Managed identity** — RBAC-based access (no connection strings)

## Prerequisites

- [Azure Developer CLI (azd)](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd) version 1.9.0 or later
- [Git](https://git-scm.com/)
- [jq](https://jqlang.org/) (for formatting JSON responses)
- An Azure subscription

## Deploy

1. Clone the repository:

   ```bash
   git clone https://github.com/Azure-Samples/Azure-Functions-Flex-Consumption-with-Azure-Files-OS-Mount-Samples.git
   ```

2. Navigate to this sample and deploy:

   ```bash
   cd Azure-Functions-Flex-Consumption-with-Azure-Files-OS-Mount-Samples/durable-text-analysis
   azd init
   azd auth login
   azd up
   ```

`azd up` provisions all Azure resources, deploys the function code, and runs a post-deployment script that:

1. Uploads sample text files to the Azure Files share
2. Runs a health check

## Test

1. Get your function key:

   ```bash
   FUNCTION_APP_NAME=$(azd env get-value AZURE_FUNCTION_APP_NAME)
   RESOURCE_GROUP=$(azd env get-value AZURE_RESOURCE_GROUP)
   FUNC_KEY=$(az functionapp keys list \
     -n "$FUNCTION_APP_NAME" -g "$RESOURCE_GROUP" \
     --query "functionKeys.default" -o tsv)
   ```

2. Start the orchestration:

   ```bash
   FUNC_URL=$(azd env get-value AZURE_FUNCTION_APP_URL)
   curl -s -X POST "${FUNC_URL}/api/start-analysis?code=${FUNC_KEY}" | jq .
   ```

3. Poll for results using the `statusQueryGetUri` from the response:

   ```bash
   curl -s "<statusQueryGetUri-from-response>" | jq .
   ```

   When the orchestration completes, the `output` field contains the aggregated analysis results from all text files.

## How it works

1. An HTTP POST to `/api/start-analysis` starts the Durable Functions orchestration.
2. The orchestrator lists all `.txt` files on the `/mounts/data/` mount.
3. It fans out, calling an activity function for each file in parallel.
4. Each activity reads a text file from the mount and returns analysis results (word count, character count, etc.).
5. The orchestrator aggregates results and returns the combined output.

## File structure

```
durable-text-analysis/
├── azure.yaml                    # azd template config (dual-platform postdeploy hooks)
├── src/
│   ├── function_app.py           # HTTP starter + health endpoint
│   ├── orchestrator.py           # Durable orchestrator (fan-out/fan-in)
│   ├── activities.py             # Activity functions (text analysis)
│   ├── requirements.txt          # Python dependencies
│   └── host.json                 # Function host configuration
├── infra/
│   ├── main.bicep                # Main infrastructure template (subscription scope)
│   ├── main.parameters.json      # azd parameter mapping
│   ├── abbreviations.json        # Azure naming conventions
│   └── app/
│       ├── function.bicep        # Function app (Flex Consumption)
│       ├── rbac.bicep            # Role assignments (managed identity)
│       └── mounts.bicep          # Azure Files mount configuration
└── scripts/
    ├── post-up.sh                # Post-deploy script (Bash)
    └── post-up.ps1               # Post-deploy script (PowerShell)
```

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| Orchestration returns empty results | No text files on mount | Re-run `azd up` to upload sample files, or upload your own `.txt` files to the Azure Files share |
| `401 Unauthorized` | Missing function key | Include `?code=<function-key>` in the request URL |
| Polling returns `Running` indefinitely | Activity function errors | Check Application Insights logs for exceptions |

> [!IMPORTANT]
> **Security note:** This sample uses `allowSharedKeyAccess` on the storage account because Azure Files SMB mounts don't yet support managed identity. The storage account key is stored in Azure Key Vault and referenced during deployment. For production, add network isolation: use **VNet integration** for the function app and restrict storage access with **Private Endpoints** (recommended) or **Service Endpoints**. Disable public network access on the storage account when using Private Endpoints. See [Configure networking for Azure Functions](https://learn.microsoft.com/azure/azure-functions/configure-networking-how-to) for details.

## Clean up

```bash
azd down --purge
```

## Tutorial

For a step-by-step walkthrough, see [Tutorial: Durable text analysis with a mounted Azure Files share](https://learn.microsoft.com/azure/azure-functions/durable/tutorial-durable-text-analysis-azure-files).

## Learn more

- [Azure Functions Flex Consumption plan](https://learn.microsoft.com/azure/azure-functions/flex-consumption-plan)
- [Durable Functions overview](https://learn.microsoft.com/azure/azure-functions/durable/durable-functions-overview)
- [Choose a file access strategy for Azure Functions](https://learn.microsoft.com/azure/azure-functions/concept-file-access-options)
- [Azure Files documentation](https://learn.microsoft.com/azure/storage/files/)
