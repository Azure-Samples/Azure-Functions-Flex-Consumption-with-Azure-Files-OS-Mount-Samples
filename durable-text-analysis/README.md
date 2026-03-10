# Durable Text Analysis Sample

This sample demonstrates a Durable Functions fan-out/fan-in orchestration that processes text files stored on an Azure Files OS mount in a Flex Consumption Function App.

## Architecture

- **Azure Functions (Flex Consumption)**: Serverless compute with dynamic scaling
- **Durable Functions**: Stateful orchestration with fan-out/fan-in pattern
- **Azure Files**: SMB file share mounted at `/mounts/data/` in the function app
- **Application Insights**: Monitoring and telemetry
- **Azure Verified Modules**: Infrastructure as Code using AVM Bicep modules

## Features

- HTTP-triggered starter function that initiates orchestration
- Durable orchestrator that lists all text files on the Azure Files mount
- Parallel activity functions that analyze each file
- Aggregated results from all analyses
- Status query endpoint to check orchestration progress

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
   - Run the post-deployment script to upload sample text files

4. **Test the function**:
   ```bash
   FUNC_URL=$(azd env get-value AZURE_FUNCTION_APP_URL)
   # Get the function key from Azure Portal or CLI
   curl -X POST "${FUNC_URL}/api/start-analysis?code=<your-function-key>"
   ```

5. **Check orchestration status**:
   Use the `statusQueryGetUri` from the response above to monitor progress.

## How It Works

1. The HTTP starter function (`/api/start-analysis`) receives a POST request
2. It starts a new orchestration instance
3. The orchestrator:
   - Lists all `.txt` files in `/mounts/data/`
   - Fans out to analyze each file in parallel
   - Aggregates word counts and summaries
4. Results are returned when all activities complete

## File Structure

```
durable-text-analysis/
├── azure.yaml              # azd configuration
├── README.md               # This file
├── src/
│   ├── function_app.py     # HTTP triggers and app registration
│   ├── orchestrator.py     # Durable orchestration logic
│   ├── activities.py       # Activity functions for file analysis
│   ├── requirements.txt    # Python dependencies
│   └── host.json           # Function host configuration
├── infra/
│   ├── main.bicep          # Main infrastructure template
│   ├── abbreviations.json  # Azure naming conventions
│   └── app/
│       ├── function.bicep  # Function app module
│       ├── rbac.bicep      # Role assignments
│       └── mounts.bicep    # Azure Files mount config
└── scripts/
    └── post-up.sh          # Post-deployment script
```

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
