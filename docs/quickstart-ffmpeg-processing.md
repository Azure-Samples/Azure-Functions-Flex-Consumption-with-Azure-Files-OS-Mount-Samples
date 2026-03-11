# Quickstart: FFmpeg Image Processing with Azure Files OS Mount

In this 10-minute quickstart, you'll deploy a Python Azure Functions app that uses an **ffmpeg binary on an OS-mounted Azure Files share** to process images. When you upload an image to an Azure Blob, the function will trigger, download it, convert it using ffmpeg from the mount, and save the result back to storage.

This demonstrates a key advantage of OS mounts: hosting large third-party binaries (like ffmpeg) outside your deployment package to keep cold starts fast and code size small.

## Prerequisites

- **Azure subscription** — [Create a free account](https://azure.microsoft.com/free/) if you don't have one
- **Azure CLI** — [Install](https://learn.microsoft.com/cli/azure/install-azure-cli)
- **Azure Functions Core Tools** — [Install](https://learn.microsoft.com/azure/azure-functions/functions-run-local?tabs=linux%2Ccsharp%2Cbash)
- **Python 3.9+** — [Install](https://www.python.org/downloads/)
- **Git** — [Install](https://git-scm.com/)
- **ffmpeg** (local, for preparing the binary) — [Install](https://ffmpeg.org/download.html) or use `apt-get install ffmpeg` on Linux/WSL

## What You'll Build

You'll deploy an application with three components:

1. **Function App** — Listens for image uploads to Azure Blob Storage.
2. **Process Function** — Triggered by blob uploads, reads the image, calls ffmpeg from the mounted share, and saves the converted image.
3. **Azure Files Mount** — Contains the ffmpeg binary and any temporary files.

When you upload an image (JPG, PNG), the function will:
- ✅ Trigger on the blob upload
- ✅ Call ffmpeg from the OS mount
- ✅ Convert the image format and resize it
- ✅ Save the result to output storage

## Step 1: Create Azure Resources

> [!NOTE]
> We'll use Bicep to automate resource creation. Alternatively, you can create resources manually in the Azure Portal.

### 1.1 Clone the Repository

```bash
git clone https://github.com/Azure-Samples/azure-files-flex-consumption-samples.git
cd azure-files-flex-consumption-samples/samples/ffmpeg-image-processing
```

### 1.2 Log In to Azure

```bash
az login
az account set --subscription <YOUR_SUBSCRIPTION_ID>
```

### 1.3 Create a Resource Group

```bash
RESOURCE_GROUP="rg-ffmpeg-processing"
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
- Storage account with a blob container and Azure Files share
- Flex Consumption function app plan
- Azure Functions app
- Application Insights for monitoring
- Managed Identity with permissions to storage

Expected output: `"provisioningState": "Succeeded"`

Save these values for the next step:

```bash
# After deployment, get your resource names
STORAGE_ACCOUNT=$(az deployment group show --resource-group $RESOURCE_GROUP --name main --query properties.outputs.storageAccountName.value -o tsv)
FUNCTION_APP_NAME=$(az deployment group show --resource-group $RESOURCE_GROUP --name main --query properties.outputs.functionAppName.value -o tsv)
SHARE_NAME="ffmpeg-binaries"
INPUT_CONTAINER="images-input"
OUTPUT_CONTAINER="images-output"

echo "Storage Account: $STORAGE_ACCOUNT"
echo "Function App: $FUNCTION_APP_NAME"
```

## Step 2: Upload FFmpeg Binary to Azure Files

### 2.1 Prepare FFmpeg Binary

On your local machine, get the ffmpeg binary and prepare it for upload.

**On Linux/macOS:**

```bash
# Get ffmpeg binary
which ffmpeg
ffmpeg_path=$(which ffmpeg)

# Create a directory to hold the binary
mkdir -p ffmpeg_share
cp $ffmpeg_path ffmpeg_share/ffmpeg

# Make it executable
chmod +x ffmpeg_share/ffmpeg

# Verify
./ffmpeg_share/ffmpeg -version | head -1
```

**On Windows:**

Download the ffmpeg binary from [ffmpeg.org](https://ffmpeg.org/download.html), extract it, and copy `ffmpeg.exe` to a local folder.

### 2.2 Upload to Azure Files

```bash
# Get storage account key
STORAGE_KEY=$(az storage account keys list --resource-group $RESOURCE_GROUP --account-name $STORAGE_ACCOUNT --query "[0].value" -o tsv)

# Upload ffmpeg binary to the share
az storage file upload \
  --share-name $SHARE_NAME \
  --source ffmpeg_share/ffmpeg \
  --path ffmpeg \
  --account-name $STORAGE_ACCOUNT \
  --account-key $STORAGE_KEY

# Verify upload
az storage file list --share-name $SHARE_NAME --account-name $STORAGE_ACCOUNT --account-key $STORAGE_KEY -o table
```

Expected output:
```
Name
------
ffmpeg
```

> [!TIP]
> The Azure Files share is mounted at `/mnt/ffmpeg_binaries` inside the function container. Your function will call `/mnt/ffmpeg_binaries/ffmpeg` directly.

## Step 3: Configure OS Mount

The Bicep deployment configures the mount, but let's verify it.

### 3.1 Verify Mount Configuration

```bash
# Check the function app's path mappings
az functionapp config appsettings list --resource-group $RESOURCE_GROUP --name $FUNCTION_APP_NAME | grep -i mount
```

Expected output: You should see mount configuration settings. If not, manually configure the mount in the Azure Portal under **Settings > Configuration > Path Mappings**.

## Step 4: Deploy the Function App

### 4.1 Install Dependencies

```bash
pip install -r requirements.txt
```

The `requirements.txt` includes:
- `azure-functions` — Core Functions runtime
- `azure-storage-blob` — Interact with Blob Storage
- `python-dotenv` — Load environment variables

### 4.2 Configure Local Settings

```bash
cp local.settings.json.example local.settings.json
```

Edit `local.settings.json` to match your deployment:

```json
{
  "IsEncrypted": false,
  "Values": {
    "FUNCTIONS_WORKER_RUNTIME": "python",
    "AzureWebJobsStorage": "DefaultEndpointsProtocol=https;AccountName=...",
    "FFMPEG_PATH": "/mnt/ffmpeg_binaries/ffmpeg",
    "TEMP_PATH": "/mnt/ffmpeg_binaries/temp"
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

## Step 5: Upload an Image to Trigger Processing

### 5.1 Create Input Blob Container

```bash
az storage container create \
  --name $INPUT_CONTAINER \
  --account-name $STORAGE_ACCOUNT \
  --account-key $STORAGE_KEY

az storage container create \
  --name $OUTPUT_CONTAINER \
  --account-name $STORAGE_ACCOUNT \
  --account-key $STORAGE_KEY
```

### 5.2 Create a Sample Image

Create a simple test image locally:

```bash
# On macOS with ImageMagick
convert -size 400x300 xc:blue sample_image.jpg

# Or on Linux
ffmpeg -f lavfi -i color=c=blue:s=400x300 -frames:v 1 sample_image.jpg -y

# Or on Windows, download a sample image from the web
# And save it as sample_image.jpg
```

### 5.3 Upload the Image

```bash
az storage blob upload \
  --container-name $INPUT_CONTAINER \
  --name sample_image.jpg \
  --file sample_image.jpg \
  --account-name $STORAGE_ACCOUNT \
  --account-key $STORAGE_KEY
```

The upload will automatically trigger your function.

> [!TIP]
> Your function is triggered by the blob upload. If the trigger doesn't fire immediately, wait 10-15 seconds and check the function's execution logs in the Azure Portal.

## Step 6: Verify the Converted Image

### 6.1 Check Function Logs

```bash
# View function app logs
az functionapp log tail --resource-group $RESOURCE_GROUP --name $FUNCTION_APP_NAME
```

Expected output:
```
2026-03-06T10:00:01.234Z Executing 'ProcessImageFunction' (Reason='New blob detected', Id=12345)
2026-03-06T10:00:02.456Z Image processing started for sample_image.jpg
2026-03-06T10:00:03.789Z FFmpeg conversion completed successfully
2026-03-06T10:00:04.000Z Executed 'ProcessImageFunction' (Succeeded, Id=12345, Duration=2765ms)
```

### 6.2 Download the Converted Image

```bash
# List output blobs
az storage blob list \
  --container-name $OUTPUT_CONTAINER \
  --account-name $STORAGE_ACCOUNT \
  --account-key $STORAGE_KEY \
  -o table

# Download the converted image
az storage blob download \
  --container-name $OUTPUT_CONTAINER \
  --name sample_image_converted.png \
  --file ./output_image.png \
  --account-name $STORAGE_ACCOUNT \
  --account-key $STORAGE_KEY
```

### 6.3 Monitor Performance

```bash
# Check the function app's CPU, memory, and execution time
az monitor app-insights metrics list \
  --resource-group $RESOURCE_GROUP \
  --app $FUNCTION_APP_NAME \
  --metric requests/duration
```

You should see execution times in the 1-3 second range (including ffmpeg startup and conversion time).

> [!NOTE]
> The first execution may be slightly slower (cold start). Subsequent invocations will be faster because the function container stays warm and ffmpeg is cached.

## Clean Up Resources

To avoid ongoing charges, delete the resource group:

```bash
az group delete --name $RESOURCE_GROUP --yes
```

> [!WARNING]
> This deletes the resource group and all resources in it (function app, storage account, etc.). Make sure you don't need them before running this command.

---

## Next Steps

- **Customize ffmpeg parameters** — Modify `process_image.py` to resize, crop, rotate, or apply filters. See [ffmpeg documentation](https://ffmpeg.org/ffmpeg.html).
- **Add error handling** — Wrap the ffmpeg subprocess call with try/except to handle corrupted images or unsupported formats.
- **Use other binaries** — The pattern works with any executable: ImageMagick, LibreOffice, Pandoc, etc. Upload the binary and call it from the mount.
- **Read more** — Check out [Running Large Binaries on Mounts](../concepts/large-binaries-on-mounts.md) for best practices and performance tips.

## Troubleshooting

**"ffmpeg: command not found"** — Verify the binary was uploaded to Azure Files. Check the mount path in your function app settings. Ensure the binary has execute permissions.

**"Permission denied"** — Verify the storage account access key in the mount configuration is correct and hasn't been rotated. Check the function app's mount settings under **Settings > Configuration > Path Mappings** in the Azure Portal. Note: OS mounts use storage account keys, not managed identity RBAC.

**"Blob trigger not firing"** — Ensure the function app's managed identity can read from the input blob container. Check the app's managed identity and assign **Storage Blob Data Reader** if needed.

**"Conversion takes too long"** — Flex Consumption cold starts add ~1-2 seconds. If you're processing large files, consider resizing the image first or using a Premium function plan for more consistent performance.

**"ffmpeg binary too large"** — Keep ffmpeg and temporary files on the Azure Files mount to avoid bloating your deployment package. The mount approach is specifically designed for this scenario.

---

**Congratulations!** You've successfully deployed an image processing function on Flex Consumption with ffmpeg on an OS mount. 🎉
