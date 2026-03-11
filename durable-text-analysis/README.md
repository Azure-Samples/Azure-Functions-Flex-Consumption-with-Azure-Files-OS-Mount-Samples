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

This sample demonstrates a Durable Functions fan-out/fan-in orchestration that processes text files stored on an Azure Files OS mount in a Flex Consumption Function App. An HTTP trigger starts the orchestration, which fans out to analyze each text file in parallel and aggregates the results.

## Architecture

- **Azure Functions (Flex Consumption)**: Serverless compute with dynamic scaling
- **Durable Functions**: Stateful orchestration with fan-out/fan-in pattern
- **Azure Files**: SMB file share mounted at `/mounts/data/` containing text files
- **Application Insights**: Monitoring and telemetry
- **Azure Verified Modules**: Infrastructure as Code using AVM Bicep modules

## Features

- HTTP-triggered starter function that initiates orchestration
- Durable orchestrator that lists all text files on the Azure Files mount
- Parallel activity functions that analyze each file (word count, summaries)
- Aggregated results from all analyses
- Built-in status query endpoint to poll orchestration progress
- RBAC-based authentication (no connection strings)

## Prerequisites

- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli)
- [Azure Developer CLI (azd)](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd)
- [Python 3.11](https://www.python.org/downloads/)
- An Azure subscription

## Quick Start

1. **Clone the repository and navigate to this sample**:
   ```bash
   cd durable-text-analysis
   ```

2. **Authenticate with Azure**:
   ```bash
   azd auth login
   ```

3. **Deploy the infrastructure and application**:
   ```bash
   azd up
   ```

   This will:
   - Provision all Azure resources (Function App, Storage Account, Azure Files share, etc.)
   - Deploy the Python function code
   - Run the post-deploy hook (`scripts/post-up.sh`) which:
     - Uploads sample text files to the Azure Files share
     - Runs a health check to verify the function app is ready

   > [!NOTE]
   > The post-deploy hook uploads sample `.txt` files to the `data` Azure Files share so that the orchestration has files to analyze on first run.

4. **Get your function key**:
   ```bash
   FUNCTION_APP_NAME=$(azd env get-value AZURE_FUNCTION_APP_NAME)
   RESOURCE_GROUP=$(azd env get-value AZURE_RESOURCE_GROUP)
   az functionapp keys list -n $FUNCTION_APP_NAME -g $RESOURCE_GROUP --query "functionKeys.default" -o tsv
   ```

5. **Start the orchestration**:
   ```bash
   FUNC_URL=$(azd env get-value AZURE_FUNCTION_APP_URL)
   FUNC_KEY=<paste-function-key-here>
   curl -s -X POST "${FUNC_URL}/api/start-analysis?code=${FUNC_KEY}" | jq .
   ```

6. **Poll for results**:
   Use the `statusQueryGetUri` from the response to monitor progress. The orchestration typically completes within a few seconds for sample files:
   ```bash
   # Use the statusQueryGetUri URL from the response (it already includes the function key)
   curl -s "<statusQueryGetUri-from-response>" | jq .
   ```
   When `runtimeStatus` is `"Completed"`, the `output` field contains the aggregated analysis results.

## How It Works

1. You send a POST request to `/api/start-analysis?code=<key>`
2. The HTTP starter function creates a new Durable Functions orchestration instance
3. The orchestrator calls the `list_files` activity, which reads the Azure Files mount at `/mounts/data/` and returns all `.txt` file paths
4. The orchestrator **fans out** — it calls `analyze_text` for each file in parallel
5. Each `analyze_text` activity reads the file from the mount, counts words, and produces a per-file summary
6. The orchestrator **fans in** — it waits for all activities to complete, then calls `aggregate_results` to combine them
7. The aggregated result (total word count, per-file summaries) is returned as the orchestration output
8. You poll the built-in `statusQueryGetUri` endpoint until `runtimeStatus` is `"Completed"`

> [!IMPORTANT]
> The Durable Functions response uses the `id` field (not `instance_id`). Use the `statusQueryGetUri` URL from the response — it's the most reliable polling method and includes the function key.

## File Structure

```
durable-text-analysis/
├── azure.yaml              # azd configuration (postdeploy hook)
├── README.md               # This file
├── src/
│   ├── function_app.py     # HTTP starter + status endpoint, app registration
│   ├── orchestrator.py     # Durable orchestration logic (fan-out/fan-in)
│   ├── activities.py       # Activity functions (list_files, analyze_text, aggregate_results)
│   ├── requirements.txt    # Python dependencies
│   └── host.json           # Function host configuration
├── infra/
│   ├── main.bicep          # Main infrastructure template
│   ├── abbreviations.json  # Azure naming conventions
│   └── app/
│       ├── function.bicep  # Function app (direct Microsoft.Web/sites, Flex Consumption)
│       ├── rbac.bicep      # Role assignments
│       └── mounts.bicep    # Azure Files mount config
└── scripts/
    └── post-up.sh          # Post-deploy: sample file upload + health check
```

## Testing

After `azd up` completes, test the end-to-end flow:

```bash
# Get the function URL and key
FUNC_URL=$(azd env get-value AZURE_FUNCTION_APP_URL)
FUNCTION_APP_NAME=$(azd env get-value AZURE_FUNCTION_APP_NAME)
RESOURCE_GROUP=$(azd env get-value AZURE_RESOURCE_GROUP)
FUNC_KEY=$(az functionapp keys list -n $FUNCTION_APP_NAME -g $RESOURCE_GROUP --query "functionKeys.default" -o tsv)

# Start the orchestration
curl -s -X POST "${FUNC_URL}/api/start-analysis?code=${FUNC_KEY}" | jq .

# Wait a few seconds, then poll using statusQueryGetUri from the response
# The output field will contain the aggregated text analysis
```

You can also verify the function app is reachable:

```bash
FUNC_URL=$(azd env get-value AZURE_FUNCTION_APP_URL)
curl -s "$FUNC_URL" -o /dev/null -w "%{http_code}"
```

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| `401 Unauthorized` on POST | Missing or wrong function key | Get the key: `az functionapp keys list -n {app} -g {rg} --query "functionKeys.default" -o tsv` and pass it as `?code=<key>` |
| Orchestration returns empty results | No text files on mount | Re-run `./scripts/post-up.sh` to upload sample files, or verify files exist: `az storage file list --account-name {storage} --share-name data --auth-mode key -o table` |
| `runtimeStatus` stuck on `"Running"` | Activity failure | Check Application Insights for exceptions. Common cause: mount not attached yet (RBAC propagation takes 1–2 minutes) |
| `allowSharedKeyAccess` deployment error | Enterprise policy | The template already sets the `Az.Sec.DisableLocalAuth.Storage::Skip` tag. If your org blocks shared key access entirely, you may need a policy exemption for Azure Files mounts. |
| Function app returns 404 | Code not deployed | Run `azd deploy` to push the function code. The function host needs to start before endpoints are available. |

## Customization

You can modify the analysis logic in `src/activities.py` to:
- Add sentiment analysis or keyword extraction
- Process different file formats (CSV, JSON)
- Integrate with Azure AI services for richer analysis
- Change the mount path via the `MOUNT_PATH` app setting

## Documentation

For more details on Azure Files integration with Flex Consumption, see the [main documentation](../docs/).

## Clean Up

To delete all resources:

```bash
azd down
```

## Learn More

- [Azure Functions Flex Consumption](https://learn.microsoft.com/azure/azure-functions/flex-consumption-plan)
- [Durable Functions](https://learn.microsoft.com/azure/azure-functions/durable/)
- [Azure Files](https://learn.microsoft.com/azure/storage/files/)
- [Azure Verified Modules](https://aka.ms/avm)
