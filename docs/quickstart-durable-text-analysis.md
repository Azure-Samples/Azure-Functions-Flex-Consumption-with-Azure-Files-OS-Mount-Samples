# Quickstart: Durable Text Analysis with Azure Files OS Mount

In this 10-minute quickstart, you'll deploy a Python Azure Functions app that uses **Durable Functions** to orchestrate parallel text file analysis. Your function app will mount an Azure Files share, analyze multiple text files in parallel (fan-out), aggregate the results (fan-in), and return them to the caller.

This demonstrates a key advantage of OS mounts: shared file access across multiple function instances without network overhead.

## Prerequisites

- **Azure subscription** — [Create a free account](https://azure.microsoft.com/free/) if you don't have one
- **Azure CLI** — [Install](https://learn.microsoft.com/cli/azure/install-azure-cli)
- **Azure Functions Core Tools** — [Install](https://learn.microsoft.com/azure/azure-functions/functions-run-local?tabs=linux%2Ccsharp%2Cbash)
- **Python 3.9+** — [Install](https://www.python.org/downloads/)
- **Git** — [Install](https://git-scm.com/)

## What You'll Build

You'll deploy an application with three components:

1. **Orchestrator Function** — Receives a trigger to analyze a folder of text files. Reads the mount point, discovers files, and fans out parallel analysis tasks.
2. **Activity Functions** — Each analyzes one file: word count, character count, sentiment (mock).
3. **Azure Files Mount** — A shared network path mounted on your function app, accessible to all instances.

When you trigger the orchestration, it will:
- ✅ Connect to your mounted Azure Files share
- ✅ List all text files in a folder
- ✅ Start parallel analysis tasks (one per file)
- ✅ Wait for all tasks to complete (fan-in)
- ✅ Return aggregated results

## Step 1: Create Azure Resources

> [!NOTE]
> We'll use Bicep to automate resource creation. Alternatively, you can create resources manually in the Azure Portal.

### 1.1 Clone the Repository

```bash
git clone https://github.com/Azure-Samples/azure-files-flex-consumption-samples.git
cd azure-files-flex-consumption-samples/samples/durable-text-analysis
```

### 1.2 Log In to Azure

```bash
az login
az account set --subscription <YOUR_SUBSCRIPTION_ID>
```

### 1.3 Create a Resource Group

```bash
RESOURCE_GROUP="rg-durable-text"
LOCATION="eastus"

az group create --name $RESOURCE_GROUP --location $LOCATION
```

### 1.4 Deploy Infrastructure with Bicep

```bash
az deployment group create \
  --resource-group $RESOURCE_GROUP \
  --template-file infra/main.bicep \
  --parameters infra/main.bicepparam
```

**What this deploys:**
- Storage account with an Azure Files share
- Flex Consumption function app plan
- Azure Functions app
- Application Insights for monitoring
- Managed Identity with permissions to the storage account

Expected output: You'll see `"provisioningState": "Succeeded"` and your function app name.

Save these values for the next step:

```bash
# After deployment, get your resource names
STORAGE_ACCOUNT=$(az deployment group show --resource-group $RESOURCE_GROUP --name main --query properties.outputs.storageAccountName.value -o tsv)
FUNCTION_APP_NAME=$(az deployment group show --resource-group $RESOURCE_GROUP --name main --query properties.outputs.functionAppName.value -o tsv)
SHARE_NAME="text-data"

echo "Storage Account: $STORAGE_ACCOUNT"
echo "Function App: $FUNCTION_APP_NAME"
echo "Share Name: $SHARE_NAME"
```

## Step 2: Configure Azure Files Mount

The Bicep deployment creates the Azure Files share, but you need to verify the mount is configured on your function app.

### 2.1 Verify Storage Account Access

```bash
# Verify the storage account has a share
az storage share list --account-name $STORAGE_ACCOUNT --query "[].name" -o table
```

Expected output:
```
Name
------
text-data
```

### 2.2 Verify Mount Configuration on Function App

```bash
# List mounts on your function app
az functionapp config appsettings list --resource-group $RESOURCE_GROUP --name $FUNCTION_APP_NAME | grep -i mount
```

Expected output: You should see an app setting like `WEBSITE_MOUNT_ENABLED=true` and a path mapping. If not, the Bicep template will handle this during deployment. You can also manually configure it via the Azure Portal under **Settings > Configuration > Path Mappings**.

> [!TIP]
> The OS mount typically appears at `/mnt/filedata` inside the function container. Your app settings will map this local path to the Azure Files share.

## Step 3: Upload Sample Text Files

### 3.1 Create Local Sample Files

```bash
mkdir -p sample_texts
cat > sample_texts/file1.txt << 'EOF'
Azure Functions is a serverless compute service that lets you run code on-demand without managing infrastructure.
EOF

cat > sample_texts/file2.txt << 'EOF'
Durable Functions extends Azure Functions with workflow capabilities like orchestration and state management.
EOF

cat > sample_texts/file3.txt << 'EOF'
Azure Files provides managed file shares in the cloud accessible via the SMB protocol.
EOF
```

### 3.2 Upload Files to Azure Files Share

```bash
# Get the storage account key
STORAGE_KEY=$(az storage account keys list --resource-group $RESOURCE_GROUP --account-name $STORAGE_ACCOUNT --query "[0].value" -o tsv)

# Upload files to the share
az storage file upload-batch \
  --destination $SHARE_NAME \
  --source sample_texts \
  --account-name $STORAGE_ACCOUNT \
  --account-key $STORAGE_KEY
```

Verify the upload:

```bash
az storage file list --share-name $SHARE_NAME --account-name $STORAGE_ACCOUNT --account-key $STORAGE_KEY -o table
```

Expected output:
```
Name
------
file1.txt
file2.txt
file3.txt
```

## Step 4: Deploy the Function App

### 4.1 Install Dependencies

```bash
pip install -r requirements.txt
```

### 4.2 Configure Local Settings

```bash
cp local.settings.json.example local.settings.json
```

Edit `local.settings.json` to include your mount path:

```json
{
  "IsEncrypted": false,
  "Values": {
    "FUNCTIONS_WORKER_RUNTIME": "python",
    "AzureWebJobsStorage": "DefaultEndpointsProtocol=https;AccountName=...",
    "MOUNT_PATH": "/mnt/filedata"
  }
}
```

### 4.3 Deploy to Azure

```bash
func azure functionapp publish $FUNCTION_APP_NAME --build remote
```

Expected output:
```
Getting site publishing info...
Creating archive for current directory...
Uploading archive...
Upload completed successfully.
Deployment successful.
```

## Step 5: Trigger the Orchestration

Your orchestrator function is now live. Trigger it via HTTP.

### 5.1 Get Your Function URL

```bash
# Get the function app's default host key
HOST_KEY=$(az functionapp keys list --resource-group $RESOURCE_GROUP --name $FUNCTION_APP_NAME --query "functionKeys.default" -o tsv)

# Build the trigger URL
FUNCTION_URL="https://${FUNCTION_APP_NAME}.azurewebsites.net/api/orchestrators/TextAnalysisOrchestrator"
```

### 5.2 Trigger the Orchestrator

```bash
curl -X POST "$FUNCTION_URL" \
  -H "x-functions-key: $HOST_KEY" \
  -H "Content-Type: application/json" \
  -d '{}'
```

Expected output (a JSON response with an instance ID):

```json
{
  "id": "abc123def456",
  "statusQueryGetUri": "https://...",
  "sendEventPostUri": "https://...",
  "terminatePostUri": "https://..."
}
```

Save the `id` value. You'll use it to check the result.

## Step 6: Verify Results

### 6.1 Check Orchestration Status

```bash
INSTANCE_ID="abc123def456"  # From the trigger response

curl "https://${FUNCTION_APP_NAME}.azurewebsites.net/api/orchestrators/TextAnalysisOrchestrator/${INSTANCE_ID}" \
  -H "x-functions-key: $HOST_KEY"
```

While processing, you'll see:

```json
{
  "name": "TextAnalysisOrchestrator",
  "instanceId": "abc123def456",
  "runtimeStatus": "Running",
  "input": null,
  "output": null,
  "createdTime": "2026-03-06T10:00:00Z",
  "lastUpdatedTime": "2026-03-06T10:00:05Z"
}
```

### 6.2 Wait for Completion

Repeat the check every few seconds. When complete, you'll see:

```json
{
  "name": "TextAnalysisOrchestrator",
  "instanceId": "abc123def456",
  "runtimeStatus": "Completed",
  "input": null,
  "output": {
    "results": [
      {
        "file": "file1.txt",
        "word_count": 15,
        "char_count": 98,
        "sentiment": "positive"
      },
      {
        "file": "file2.txt",
        "word_count": 18,
        "char_count": 120,
        "sentiment": "positive"
      },
      {
        "file": "file3.txt",
        "word_count": 12,
        "char_count": 85,
        "sentiment": "neutral"
      }
    ],
    "total_words": 45,
    "total_chars": 303,
    "analysis_duration_seconds": 2.34
  },
  "createdTime": "2026-03-06T10:00:00Z",
  "lastUpdatedTime": "2026-03-06T10:00:05Z"
}
```

> [!TIP]
> Your function app accessed all three files in parallel through the OS mount. No network calls were needed—it read them directly from the mounted share. This is the power of OS mounts combined with Durable Functions.

### 6.3 Monitor in Application Insights

```bash
# Open Application Insights in the Portal
az monitor app-insights show --resource-group $RESOURCE_GROUP --app $FUNCTION_APP_NAME --query instrumentationKey -o tsv
```

Copy the link and paste it into your browser to see traces, performance metrics, and dependencies.

## Clean Up Resources

To avoid ongoing charges, delete the resource group:

```bash
az group delete --name $RESOURCE_GROUP --yes
```

> [!WARNING]
> This deletes the resource group and all resources in it (function app, storage account, etc.). Make sure you don't need them before running this command.

---

## Next Steps

- **Explore more patterns** — Read [Shared File Access Patterns](../tutorial-shared-file-access.md) to understand when to use OS mounts vs. bindings.
- **Learn about Durable Functions** — Visit the [Durable Functions documentation](https://learn.microsoft.com/azure/azure-functions/durable/durable-functions-overview).
- **Run the sample locally** — Use the Azure Functions emulator to test before deploying.
- **Try the FFmpeg sample** — If you need to run large binaries, check out the [FFmpeg Image Processing quickstart](./quickstart-ffmpeg-processing.md).

## Troubleshooting

**"Mount path not found"** — Verify the mount is configured. Check your function app's **Settings > Configuration > Path Mappings** in the Azure Portal.

**"Permission denied" when reading files** — Ensure the function app's managed identity has **Storage File Data SMB Share Contributor** role on the storage account.

**"Deployment failed"** — Check the Bicep parameters file (`infra/main.bicepparam`). Ensure all required values are set and the storage account name is globally unique.

**"Orchestration timed out"** — The Durable Functions timeout is set in `function_app.py`. Increase `maxRetryInterval` if your files are large or your analysis is slow.

---

**Congratulations!** You've successfully deployed and run a Durable Functions orchestration on Flex Consumption with Azure Files OS mounts. 🎉
