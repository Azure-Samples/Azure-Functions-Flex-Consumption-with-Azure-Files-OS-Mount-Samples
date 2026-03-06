# Concepts: Azure Files with Azure Functions

This guide explains **how to set up and use Azure Files** as a mount on Azure Functions Flex Consumption. You'll learn storage configuration, permissions, and practical mounting patterns.

## What is Azure Files?

**Azure Files** provides managed network file shares in Azure Storage using the **SMB protocol** (Server Message Block). It's compatible with Windows, Linux, and macOS clients.

### Azure Files vs. Other Storage Options

| Option | Protocol | Use Case | Mount on Functions |
|--------|----------|----------|-------------------|
| **Azure Files** | SMB | Shared file access, legacy apps | ✅ Yes (Flex/Premium only) |
| **Azure Blob Storage** | HTTP/REST | Unstructured data, media | ⚠️ Via binding, not mount |
| **Azure Data Lake** | HTTP/REST | Big data, analytics | ⚠️ Via binding, not mount |
| **Azure Queue** | HTTP/REST | Async messaging | ✅ Via binding (not mount) |
| **Azure Table** | HTTP/REST | NoSQL key-value | ✅ Via binding (not mount) |

**For OS mounts, only Azure Files works.**

## Azure Files Architecture

```
Storage Account
    ├── File Service (Azure Files)
    │   ├── Share 1: "data" (100 GB)
    │   │   ├── folder1/
    │   │   ├── folder2/
    │   │   │   └── file.txt
    │   │   └── ...
    │   ├── Share 2: "backups" (1 TB)
    │   └── Share 3: "logs" (50 GB)
    ├── Blob Service
    ├── Queue Service
    └── Table Service
```

A **storage account** can have multiple **file shares**. Each share is a volume that can be mounted independently.

### Storage Tiers

| Tier | Throughput | Scalability | Cost | Best For |
|------|-----------|------------|------|----------|
| **Standard** | 60 MB/s | Up to 100 TiB | Low | Most workloads, development/test |
| **Premium** | 100+ MB/s | Up to 100 TiB | Higher | High-throughput, latency-sensitive |

**Recommendation:** Start with Standard for development. Switch to Premium if you hit throughput limits.

## Setting Up Azure Files for Functions

### Step 1: Create a Storage Account

```bash
STORAGE_ACCOUNT="mystorageaccount"
RESOURCE_GROUP="rg-functions"
LOCATION="eastus"

az storage account create \
  --resource-group $RESOURCE_GROUP \
  --name $STORAGE_ACCOUNT \
  --location $LOCATION \
  --sku Standard_LRS \
  --kind StorageV2
```

### Step 2: Create a File Share

```bash
SHARE_NAME="functiondata"
QUOTA=100  # GB

az storage share-rm create \
  --resource-group $RESOURCE_GROUP \
  --storage-account-name $STORAGE_ACCOUNT \
  --name $SHARE_NAME \
  --quota $QUOTA
```

### Step 3: Upload Content (Optional)

```bash
# Create local test data
mkdir -p local_data
echo "test content" > local_data/test.txt

# Upload to share
STORAGE_KEY=$(az storage account keys list \
  --resource-group $RESOURCE_GROUP \
  --account-name $STORAGE_ACCOUNT \
  --query "[0].value" -o tsv)

az storage file upload-batch \
  --destination $SHARE_NAME \
  --source local_data \
  --account-name $STORAGE_ACCOUNT \
  --account-key $STORAGE_KEY
```

### Step 4: Configure RBAC Permissions

#### Using Managed Identity (Recommended)

Your function app needs a **managed identity** with the right role on the storage account:

```bash
# If using system-assigned identity
PRINCIPAL_ID=$(az functionapp identity show \
  --resource-group $RESOURCE_GROUP \
  --name $FUNCTION_APP_NAME \
  --query principalId -o tsv)

# Assign the role
az role assignment create \
  --assignee $PRINCIPAL_ID \
  --role "Storage File Data SMB Share Contributor" \
  --scope /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT
```

**Why Managed Identity?**
- No secrets to manage
- Automatic token refresh
- Auditable in Azure AD
- Follows security best practices

#### Available Roles

| Role | Permissions | Use For |
|------|-------------|---------|
| **Storage File Data SMB Share Contributor** | Read, write, delete files | General-purpose read/write |
| **Storage File Data SMB Share Reader** | Read files only | Read-only workloads |
| **Storage File Data SMB Share Elevated Contributor** | Full permissions including ownership | Admin tasks |

> [!WARNING]
> **Storage Blob Data Contributor** and similar blob roles do NOT grant Azure Files access. Use the SMB-specific roles.

### Step 5: Configure Mount on Function App

#### Via Bicep

```bicep
param functionAppName string
param storageAccountName string
param shareName string

resource functionApp 'Microsoft.Web/sites@2022-03-01' = {
  name: functionAppName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: functionPlanId
    siteConfig: {
      linuxFxVersion: 'PYTHON|3.11'
      azureStorageAccounts: {
        fileMount: {
          type: 'AzureFiles'
          accountName: storageAccountName
          shareName: shareName
          mountPath: '/mnt/filedata'
          accessKey: ''  // Leave empty for managed identity
        }
      }
      appSettings: [
        {
          name: 'WEBSITE_MOUNT_ENABLED'
          value: 'true'
        }
      ]
    }
  }
}

// Assign role to managed identity
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(functionApp.id, storageAccount.id, 'Storage File Data SMB Share Contributor')
  scope: storageAccount
  properties: {
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '0c867c2a-1d8c-454a-a3db-ab2ea1bdc8bb')
  }
}
```

#### Via Azure CLI

```bash
# Enable mount for your function app
az functionapp config appsettings set \
  --resource-group $RESOURCE_GROUP \
  --name $FUNCTION_APP_NAME \
  --settings WEBSITE_MOUNT_ENABLED=true

# Add the mount configuration
# (Note: CLI mount setup is limited; Bicep is preferred)
```

#### Via Azure Portal

1. Open your function app
2. Go to **Settings > Configuration**
3. Select **Path Mappings**
4. Click **New Azure File Share Mount**
5. Fill in:
   - **Local path**: `/mnt/filedata`
   - **Storage account**: Your storage account
   - **Share name**: Your share
   - **Access method**: (Select "Managed Identity" if available)
6. Save

### Step 6: Verify Mount Configuration

After deploying your function app, verify the mount is active:

```bash
# Check the app settings
az functionapp config appsettings list \
  --resource-group $RESOURCE_GROUP \
  --name $FUNCTION_APP_NAME | grep -i mount

# Expected output includes WEBSITE_MOUNT_ENABLED=true and path mappings
```

In your function code, verify the mount is accessible:

```python
import os
from pathlib import Path

@app.function_route(route="check-mount")
def check_mount(req):
    mount_path = "/mnt/filedata"
    if Path(mount_path).exists():
        files = os.listdir(mount_path)
        return f"Mount accessible. Files: {files}"
    else:
        return "Mount not found", 500
```

## Using Azure Files from Function Code

### Reading Files

```python
from pathlib import Path

MOUNT_PATH = "/mnt/filedata"

def read_config():
    config_file = Path(MOUNT_PATH) / "config.json"
    with open(config_file, "r") as f:
        return json.load(f)
```

### Writing Files

```python
from pathlib import Path
import json

MOUNT_PATH = "/mnt/filedata"

def write_results(data: dict):
    output_file = Path(MOUNT_PATH) / "results.json"
    with open(output_file, "w") as f:
        json.dump(data, f)
```

### Listing Directory Contents

```python
from pathlib import Path

MOUNT_PATH = "/mnt/filedata"

def list_files():
    files = [str(f.relative_to(MOUNT_PATH)) for f in Path(MOUNT_PATH).rglob("*") if f.is_file()]
    return files
```

### File Locking for Coordination

If multiple function instances write to the same file, use locks:

```python
import fcntl
import time
from pathlib import Path

MOUNT_PATH = "/mnt/filedata"

def write_with_lock(filename: str, data: str):
    file_path = Path(MOUNT_PATH) / filename
    
    with open(file_path, "w") as f:
        fcntl.flock(f, fcntl.LOCK_EX)  # Exclusive lock
        try:
            f.write(data)
        finally:
            fcntl.flock(f, fcntl.LOCK_UN)  # Release lock
```

## Performance Tuning

### Caching

The OS caches frequently-accessed files. After the first read, subsequent accesses are fast:

```python
# First read: ~50ms (network + cache miss)
with open("/mnt/data/large_file.bin", "rb") as f:
    data1 = f.read(1024)

# Second read: ~5ms (OS cache hit)
with open("/mnt/data/large_file.bin", "rb") as f:
    data2 = f.read(1024)
```

### Batch Operations

Group file operations to reduce network round-trips:

```python
# Inefficient: 1000 individual reads
for i in range(1000):
    with open(f"/mnt/data/file_{i}.txt", "r") as f:
        data = f.read()
    process(data)

# More efficient: Read all at once
files = list(Path("/mnt/data").glob("file_*.txt"))
all_data = [f.read_text() for f in files]
for data in all_data:
    process(data)
```

### Timeouts

Set appropriate timeouts for file operations:

```python
import signal

def timeout_handler(signum, frame):
    raise TimeoutError("File operation timed out")

signal.signal(signal.SIGALRM, timeout_handler)
signal.alarm(30)  # 30-second timeout

try:
    with open("/mnt/data/largefile.bin", "rb") as f:
        data = f.read()
finally:
    signal.alarm(0)  # Cancel alarm
```

## Quotas and Limits

### Setting Share Quotas

Prevent runaway costs by limiting share size:

```bash
az storage share-rm update \
  --resource-group $RESOURCE_GROUP \
  --storage-account-name $STORAGE_ACCOUNT \
  --name $SHARE_NAME \
  --quota 500  # 500 GB limit
```

### Share Limits

| Limit | Value |
|-------|-------|
| Max share size | 100 TiB |
| Max file size | 4 TiB |
| Max files per share | Millions (limited by quota) |
| Throughput (standard) | 60 MB/s |
| Throughput (premium) | 100+ MB/s |

### Function App Limits

| Limit | Value |
|-------|-------|
| Max mounts per function app | Multiple (OS filesystem limit) |
| Mount timeout | 10 minutes |
| Mount auth token refresh | Automatic |

## Monitoring and Diagnostics

### Enable Diagnostics

```bash
az storage account diagnostics-settings create \
  --resource-group $RESOURCE_GROUP \
  --storage-account-name $STORAGE_ACCOUNT \
  --name fileservicediagnostics \
  --logs-enabled true \
  --metrics-enabled true \
  --log-retention-days 30
```

### Monitor Share Usage

```bash
# Check current share usage
az storage share-rm stats \
  --resource-group $RESOURCE_GROUP \
  --storage-account-name $STORAGE_ACCOUNT \
  --name $SHARE_NAME
```

### Log Analysis

View mount access patterns in Application Insights:

```kusto
// KQL query for function invocations accessing mounts
customMetrics
| where name == "function_invocation"
| extend mount_accessed = tostring(customDimensions.mount_path)
| where isnotempty(mount_accessed)
| summarize count() by mount_accessed, bin(timestamp, 1m)
```

## Troubleshooting

### "Permission denied" when accessing mount

**Solution:**
1. Verify the function app's managed identity is assigned the **Storage File Data SMB Share Contributor** role
2. Check the storage account's firewall rules aren't blocking the function app
3. Ensure the share exists and the account name is correct

### "Mount path not found" in code

**Solution:**
1. Verify `WEBSITE_MOUNT_ENABLED=true` in function app settings
2. Check the mount path matches what's configured (e.g., `/mnt/filedata`)
3. Wait 5-10 seconds after deployment; mount may be initializing

### Slow file access

**Solution:**
1. Check if you're hitting Azure Files throughput limits (60 MB/s for standard)
2. Verify the storage account and function app are in the same region
3. Consider upgrading to Premium tier if throughput is consistently high

### "Stale NFS file handle" (on Linux)

**Solution:**
1. This indicates the mount was disconnected and reconnected
2. Typically resolved by restarting the function app
3. If frequent, consider increasing SMB timeout values

---

## Next Steps

- **[Shared File Access Patterns Tutorial](../tutorial-shared-file-access.md)** — Learn best practices
- **[Flex Consumption & OS Mounts Concepts](./flex-consumption-os-mounts.md)** — Understand the platform
- **[Quickstarts](../quickstart-durable-text-analysis.md)** — Hands-on examples

**Key Takeaway:** Azure Files is the storage solution for OS mounts on Azure Functions. Use managed identity for authentication, set quotas for cost control, and leverage POSIX file APIs from your code.
