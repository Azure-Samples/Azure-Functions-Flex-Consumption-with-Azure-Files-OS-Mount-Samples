#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# deploy-sample.sh
#
# Deploys a specific sample to Azure using the shared Bicep modules.
# Handles: resource group creation, Bicep deployment, Azure Files setup,
# OS mount configuration, and function app deployment via Core Tools.
#
# Usage:
#   bash infra/scripts/deploy-sample.sh <sample-name> [options]
#
# Examples:
#   bash infra/scripts/deploy-sample.sh durable-text-analysis
#   bash infra/scripts/deploy-sample.sh ffmpeg-image-processing --location eastus2
# ---------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INFRA_DIR="$REPO_ROOT/infra"

# ---- Defaults --------------------------------------------------------------
SAMPLE_NAME="${1:-}"
LOCATION="eastus"
RESOURCE_GROUP=""
BASE_NAME=""

shift || true

# ---- Parse optional arguments -----------------------------------------------
while [[ $# -gt 0 ]]; do
    case $1 in
        --location|-l) LOCATION="$2"; shift 2 ;;
        --resource-group|-g) RESOURCE_GROUP="$2"; shift 2 ;;
        --base-name|-n) BASE_NAME="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# ---- Validate ---------------------------------------------------------------
VALID_SAMPLES=("durable-text-analysis" "ffmpeg-image-processing")
if [[ -z "$SAMPLE_NAME" ]]; then
    echo "Usage: $0 <sample-name> [--location <region>] [--resource-group <rg>]"
    echo "Available samples: ${VALID_SAMPLES[*]}"
    exit 1
fi

SAMPLE_DIR="$REPO_ROOT/samples/$SAMPLE_NAME"
if [[ ! -d "$SAMPLE_DIR" ]]; then
    echo "Error: Sample directory not found: $SAMPLE_DIR"
    exit 1
fi

# Derive names if not provided.
SUFFIX=$(openssl rand -hex 3)
BASE_NAME="${BASE_NAME:-azfiles-${SAMPLE_NAME}-${SUFFIX}}"
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-${BASE_NAME}}"
STORAGE_ACCOUNT="st$(echo "$BASE_NAME" | tr -d '-' | head -c 20)"
FUNCTION_APP="${BASE_NAME}-func"

echo "============================================================"
echo "  Deploying sample: $SAMPLE_NAME"
echo "  Location:         $LOCATION"
echo "  Resource Group:   $RESOURCE_GROUP"
echo "  Storage Account:  $STORAGE_ACCOUNT"
echo "  Function App:     $FUNCTION_APP"
echo "============================================================"

# ---- Step 1: Resource Group -------------------------------------------------
echo ""
echo "==> Creating resource group..."
az group create \
    --name "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --output none

# ---- Step 2: Deploy infrastructure via Bicep --------------------------------
echo "==> Deploying infrastructure (storage, monitoring, function app)..."

# Deployment container name for Flex Consumption app packages.
DEPLOY_CONTAINER="app-package-$(echo "$FUNCTION_APP" | head -c 32)-$(openssl rand -hex 4)"

# Deploy storage account with file shares and deployment container.
az deployment group create \
    --resource-group "$RESOURCE_GROUP" \
    --template-file "$INFRA_DIR/modules/storage-account.bicep" \
    --parameters \
        storageAccountName="$STORAGE_ACCOUNT" \
        location="$LOCATION" \
        deploymentContainerName="$DEPLOY_CONTAINER" \
        fileShareNames='["data","tools"]' \
    --output none

# Retrieve outputs from storage deployment.
STORAGE_BLOB_ENDPOINT=$(az deployment group show \
    --resource-group "$RESOURCE_GROUP" \
    --name storage-account \
    --query 'properties.outputs.primaryBlobEndpoint.value' -o tsv 2>/dev/null || echo "")
STORAGE_BLOB_URI=$(az deployment group show \
    --resource-group "$RESOURCE_GROUP" \
    --name storage-account \
    --query 'properties.outputs.blobServiceUri.value' -o tsv 2>/dev/null || echo "")
STORAGE_QUEUE_URI=$(az deployment group show \
    --resource-group "$RESOURCE_GROUP" \
    --name storage-account \
    --query 'properties.outputs.queueServiceUri.value' -o tsv 2>/dev/null || echo "")
STORAGE_TABLE_URI=$(az deployment group show \
    --resource-group "$RESOURCE_GROUP" \
    --name storage-account \
    --query 'properties.outputs.tableServiceUri.value' -o tsv 2>/dev/null || echo "")
ACCOUNT_KEY=$(az deployment group show \
    --resource-group "$RESOURCE_GROUP" \
    --name storage-account \
    --query 'properties.outputs.accountKey.value' -o tsv 2>/dev/null || echo "")

# Deploy monitoring.
az deployment group create \
    --resource-group "$RESOURCE_GROUP" \
    --template-file "$INFRA_DIR/modules/monitoring.bicep" \
    --parameters baseName="$BASE_NAME" location="$LOCATION" \
    --output none

INSIGHTS_CONN=$(az deployment group show \
    --resource-group "$RESOURCE_GROUP" \
    --name monitoring \
    --query 'properties.outputs.connectionString.value' -o tsv 2>/dev/null || echo "")

# Build additional app settings depending on sample.
EXTRA_SETTINGS="{}"
if [[ "$SAMPLE_NAME" == "durable-text-analysis" ]]; then
    EXTRA_SETTINGS='{"MOUNT_PATH":"/mounts/data/"}'
elif [[ "$SAMPLE_NAME" == "ffmpeg-image-processing" ]]; then
    EXTRA_SETTINGS='{"FFMPEG_PATH":"/mounts/tools/ffmpeg","OUTPUT_WIDTH":"800","OUTPUT_FORMAT":"png"}'
fi

# Deploy function app (Flex Consumption with managed identity).
az deployment group create \
    --resource-group "$RESOURCE_GROUP" \
    --template-file "$INFRA_DIR/modules/function-app.bicep" \
    --parameters \
        functionAppName="$FUNCTION_APP" \
        location="$LOCATION" \
        storageBlobEndpoint="$STORAGE_BLOB_ENDPOINT" \
        deploymentContainerName="$DEPLOY_CONTAINER" \
        storageBlobServiceUri="$STORAGE_BLOB_URI" \
        storageQueueServiceUri="$STORAGE_QUEUE_URI" \
        storageTableServiceUri="$STORAGE_TABLE_URI" \
        appInsightsConnectionString="$INSIGHTS_CONN" \
        additionalAppSettings="$EXTRA_SETTINGS" \
    --output none

# Assign Storage Blob Data Owner role to function app's managed identity
# so it can read deployment packages and access AzureWebJobsStorage.
FUNC_PRINCIPAL_ID=$(az deployment group show \
    --resource-group "$RESOURCE_GROUP" \
    --name function-app \
    --query 'properties.outputs.principalId.value' -o tsv 2>/dev/null || echo "")
STORAGE_ACCOUNT_ID=$(az deployment group show \
    --resource-group "$RESOURCE_GROUP" \
    --name storage-account \
    --query 'properties.outputs.storageAccountId.value' -o tsv 2>/dev/null || echo "")

if [[ -n "$FUNC_PRINCIPAL_ID" && -n "$STORAGE_ACCOUNT_ID" ]]; then
    echo "==> Assigning Storage Blob Data Owner role to function app identity..."
    az role assignment create \
        --assignee-object-id "$FUNC_PRINCIPAL_ID" \
        --assignee-principal-type ServicePrincipal \
        --role "Storage Blob Data Owner" \
        --scope "$STORAGE_ACCOUNT_ID" \
        --output none 2>/dev/null || true

    echo "==> Assigning Storage Queue Data Contributor role..."
    az role assignment create \
        --assignee-object-id "$FUNC_PRINCIPAL_ID" \
        --assignee-principal-type ServicePrincipal \
        --role "Storage Queue Data Contributor" \
        --scope "$STORAGE_ACCOUNT_ID" \
        --output none 2>/dev/null || true

    echo "==> Assigning Storage Table Data Contributor role..."
    az role assignment create \
        --assignee-object-id "$FUNC_PRINCIPAL_ID" \
        --assignee-principal-type ServicePrincipal \
        --role "Storage Table Data Contributor" \
        --scope "$STORAGE_ACCOUNT_ID" \
        --output none 2>/dev/null || true
fi

# ---- Step 3: Configure OS mounts -------------------------------------------
# IMPORTANT: All mounts are deployed in a single Bicep call using the plural
# azure-files-mounts.bicep module.  The Microsoft.Web/sites/config resource
# REPLACES the entire azureStorageAccounts dictionary on each deployment, so
# deploying mounts one-at-a-time causes earlier mounts to be overwritten.
echo "==> Configuring Azure Files OS mounts..."

MOUNTS_JSON=$(cat <<EOF
[
  {
    "name": "data",
    "shareName": "data",
    "accountName": "$STORAGE_ACCOUNT",
    "accountKey": "$ACCOUNT_KEY",
    "mountPath": "/mounts/data"
  },
  {
    "name": "tools",
    "shareName": "tools",
    "accountName": "$STORAGE_ACCOUNT",
    "accountKey": "$ACCOUNT_KEY",
    "mountPath": "/mounts/tools"
  }
]
EOF
)

az deployment group create \
    --resource-group "$RESOURCE_GROUP" \
    --template-file "$INFRA_DIR/modules/azure-files-mounts.bicep" \
    --parameters \
        functionAppName="$FUNCTION_APP" \
        mounts="$MOUNTS_JSON" \
    --name "configure-mounts" \
    --output none

# ---- Step 4: Upload seed data and tools -------------------------------------
echo "==> Setting up Azure Files content..."
bash "$INFRA_DIR/scripts/setup-azure-files.sh" \
    --resource-group "$RESOURCE_GROUP" \
    --storage-account "$STORAGE_ACCOUNT"

# ---- Step 5: Deploy function app code ---------------------------------------
echo "==> Deploying function app code from $SAMPLE_DIR..."
pushd "$SAMPLE_DIR" > /dev/null

# Install Python deps and publish.
pip install -r requirements.txt --quiet 2>/dev/null || true
func azure functionapp publish "$FUNCTION_APP" --python

popd > /dev/null

echo ""
echo "============================================================"
echo "  ✓ Deployment complete!"
echo ""
echo "  Function App URL: https://${FUNCTION_APP}.azurewebsites.net"
echo "  Resource Group:   $RESOURCE_GROUP"
echo ""
echo "  To tear down:"
echo "    bash infra/scripts/cleanup.sh --resource-group $RESOURCE_GROUP"
echo "============================================================"
