# FFmpeg Image Processing Sample

This sample demonstrates event-driven image processing using FFmpeg on an Azure Files OS mount in a Flex Consumption Function App. Images uploaded to Blob Storage trigger the function via EventGrid, which processes them using FFmpeg tools mounted from Azure Files.

## Architecture

- **Azure Functions (Flex Consumption)**: Serverless compute with dynamic scaling
- **EventGrid**: Event-driven triggers for blob storage events
- **Azure Files**: SMB file share mounted at `/mounts/tools/` containing FFmpeg binary
- **Blob Storage**: Input and output containers for images
- **Application Insights**: Monitoring and telemetry
- **Azure Verified Modules**: Infrastructure as Code using AVM Bicep modules

## Features

- EventGrid-triggered blob trigger that processes images automatically
- FFmpeg binary stored on Azure Files OS mount
- Resize and convert images using FFmpeg
- Output images saved to a dedicated blob container via blob output binding
- RBAC-based authentication (no connection strings)

## Prerequisites

- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli)
- [Azure Developer CLI (azd)](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd)
- [Python 3.11](https://www.python.org/downloads/)
- An Azure subscription

## Quick Start

1. **Clone the repository and navigate to this sample**:
   ```bash
   cd ffmpeg-image-processing
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
   - Provision all Azure resources (Function App, Storage Account, EventGrid system topic, Azure Files, etc.)
   - Deploy the Python function code
   - Run the post-deploy hook (`scripts/post-up.sh`) which:
     - Downloads and uploads the FFmpeg binary to the Azure Files share
     - Creates the EventGrid subscription pointing to the blob trigger webhook
     - Runs a health check to verify the function is ready

   > [!NOTE]
   > The EventGrid subscription is created in the post-deploy hook (not during provisioning) because the blob trigger webhook endpoint requires a `blobs_extension` system key that only exists after the function code is deployed and the host has started.

4. **Upload a test image**:
   ```bash
   STORAGE_ACCOUNT=$(azd env get-value AZURE_STORAGE_ACCOUNT_NAME)
   az storage blob upload \
     --account-name $STORAGE_ACCOUNT \
     --container-name images-input \
     --name test-image.jpg \
     --file /path/to/your/image.jpg \
     --auth-mode login
   ```

   The blob trigger fires within a few seconds. Check the `images-output` container for the processed result.

5. **Check the output**:
   ```bash
   az storage blob list \
     --account-name $STORAGE_ACCOUNT \
     --container-name images-output \
     --auth-mode login \
     --output table
   ```

## How It Works

1. An image is uploaded to the `images-input` blob container
2. EventGrid detects the `BlobCreated` event and delivers it to the function's blob trigger webhook
3. The function receives the image bytes via its **blob input binding** (`@app.blob_trigger(source="EventGrid")`)
4. The function processes the image using FFmpeg from the `/mounts/tools/` mount
5. The processed image is returned via the **blob output binding**, which writes it to the `images-output` container

No manual blob download or upload happens in the function code — the Azure Functions runtime handles I/O through the bindings.

## File Structure

```
ffmpeg-image-processing/
├── azure.yaml              # azd configuration (postdeploy hook)
├── README.md               # This file
├── src/
│   ├── function_app.py     # Blob trigger + output binding, health endpoint
│   ├── process_image.py    # Image processing logic with FFmpeg
│   ├── requirements.txt    # Python dependencies
│   └── host.json           # Function host configuration
├── infra/
│   ├── main.bicep          # Main infrastructure template
│   ├── abbreviations.json  # Azure naming conventions
│   └── app/
│       ├── function.bicep  # Function app module (Flex Consumption)
│       ├── rbac.bicep      # Role assignments
│       └── mounts.bicep    # Azure Files mount config
└── scripts/
    └── post-up.sh          # Post-deploy: ffmpeg upload + EventGrid subscription + health check
```

## Testing

After `azd up` completes, test the end-to-end flow:

```bash
# Upload any JPEG/PNG image
STORAGE_ACCOUNT=$(azd env get-value AZURE_STORAGE_ACCOUNT_NAME)
az storage blob upload \
  --account-name $STORAGE_ACCOUNT \
  --container-name images-input \
  --name sample.jpg \
  --file ./sample.jpg \
  --auth-mode login

# Wait a few seconds, then check the output container
az storage blob list \
  --account-name $STORAGE_ACCOUNT \
  --container-name images-output \
  --auth-mode login \
  --output table
```

The blob trigger fires within a few seconds of upload. You can also verify the function is healthy:

```bash
FUNCTION_APP_URL=$(azd env get-value AZURE_FUNCTION_APP_URL)
curl "$FUNCTION_APP_URL/api/health"
```

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| Images not being processed | ffmpeg not on mount | Check `curl https://{app}/api/health` — if `ffmpeg_available` is `false`, re-run `./scripts/post-up.sh` |
| Images not being processed | EventGrid subscription missing | Run `az eventgrid system-topic event-subscription list --system-topic-name {topic} -g {rg}` to verify the subscription exists |
| Function triggers after a delay | RBAC propagation | Role assignments can take 1–2 minutes to propagate after deployment. Wait and retry. |
| `allowSharedKeyAccess` deployment error | Enterprise policy | The template already sets the `Az.Sec.DisableLocalAuth.Storage::Skip` tag. If your org blocks shared key access entirely, you may need a policy exemption for Azure Files mounts. |

## Customization

You can modify the FFmpeg processing logic in `src/process_image.py` to:
- Apply different filters (grayscale, blur, etc.)
- Change output format (JPEG, PNG, WebP)
- Resize to different dimensions
- Add watermarks or overlays

## Documentation

For more details on Azure Files integration with Flex Consumption, see the [main documentation](../docs/).

## Clean Up

To delete all resources:

```bash
azd down
```

## Learn More

- [Azure Functions Flex Consumption](https://learn.microsoft.com/azure/azure-functions/flex-consumption-plan)
- [EventGrid Blob Storage Events](https://learn.microsoft.com/azure/event-grid/event-schema-blob-storage)
- [Azure Files](https://learn.microsoft.com/azure/storage/files/)
- [FFmpeg Documentation](https://ffmpeg.org/documentation.html)
- [Azure Verified Modules](https://aka.ms/avm)
