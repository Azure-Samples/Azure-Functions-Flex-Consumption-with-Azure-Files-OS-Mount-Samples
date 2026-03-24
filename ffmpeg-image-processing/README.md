<!--
---
name: FFmpeg image processing with Azure Functions Flex Consumption and Azure Files
description: Python event-driven image processing sample that uses FFmpeg from an Azure Files OS mount in Azure Functions Flex Consumption, with EventGrid blob triggers and azd/Bicep deployment.
page_type: sample
products:
- azure-functions
- azure-files
- azure-storage
- azure-event-grid
- azure
urlFragment: functions-flex-consumption-ffmpeg-image-processing-azure-files
languages:
- python
- bicep
- azdeveloper
---
-->

# FFmpeg Image Processing Sample

Event-driven image processing using FFmpeg on an Azure Files OS mount in a Flex Consumption function app. Images uploaded to Blob Storage trigger the function via EventGrid, which processes them using FFmpeg from the mount and saves the result to an output container.

## Architecture

- **Azure Functions (Flex Consumption)** — Serverless compute with OS-level mount support
- **Azure Files** — SMB share mounted at `/mounts/tools/` containing the FFmpeg binary
- **EventGrid** — Blob-created events trigger the function
- **Blob Storage** — `images-input` and `images-output` containers
- **Application Insights** — Monitoring and telemetry
- **Managed identity** — RBAC-based access (no connection strings)

## Prerequisites

- [Azure Developer CLI (azd)](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd) version 1.9.0 or later
- [Git](https://git-scm.com/)
- An Azure subscription

## Deploy

1. Clone the repository:

   ```bash
   git clone https://github.com/Azure-Samples/Azure-Functions-Flex-Consumption-with-Azure-Files-OS-Mount-Samples.git
   ```

2. Navigate to this sample and deploy:

   ```bash
   cd Azure-Functions-Flex-Consumption-with-Azure-Files-OS-Mount-Samples/ffmpeg-image-processing
   azd init
   azd auth login
   azd up
   ```

`azd up` provisions all Azure resources, deploys the function code, and runs a post-deployment script that:

1. Downloads and uploads the FFmpeg binary to the Azure Files share
2. Creates the EventGrid subscription for blob triggers
3. Runs a health check

> [!NOTE]  
> The Event Grid subscription is created in the post-deploy hook (not during provisioning). The subscription is create after deployment because the blob trigger webhook requires a `blobs_extension` system key, which only exists after the Functions host has successfully started and generated the key.

## Test

```bash
STORAGE_ACCOUNT=$(azd env get-value AZURE_STORAGE_ACCOUNT_NAME)

az storage blob upload \
  --account-name "$STORAGE_ACCOUNT" \
  --container-name images-input \
  --name sample_image.jpg \
  --file sample_image.jpg \
  --auth-mode login
```

Wait a few seconds, then check the output container:

```bash
az storage blob list \
  --account-name "$STORAGE_ACCOUNT" \
  --container-name images-output \
  --auth-mode login \
  --output table
```

Verify the function is healthy:

```bash
FUNCTION_APP_URL=$(azd env get-value AZURE_FUNCTION_APP_URL)
curl "$FUNCTION_APP_URL/api/health"
```

## How it works

1. An image is uploaded to the `images-input` blob container.
2. EventGrid detects the `BlobCreated` event and delivers it to the function's blob trigger webhook.
3. The function reads the image via the blob input binding.
4. FFmpeg (at `/mounts/tools/ffmpeg`) resizes and converts the image.
5. The processed image is written to `images-output` via the blob output binding.

## File structure

```
ffmpeg-image-processing/
├── azure.yaml                    # azd template config (dual-platform postdeploy hooks)
├── sample_image.jpg              # Sample image for testing
├── src/
│   ├── function_app.py           # Blob trigger + output binding, health endpoint
│   ├── process_image.py          # FFmpeg image processing logic
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
| Images not processed | FFmpeg not on mount | Check `curl $FUNCTION_APP_URL/api/health` — if `ffmpeg_available` is `false`, re-run `azd up` |
| Images not processed | EventGrid subscription missing | Run `az eventgrid system-topic event-subscription list --system-topic-name <topic> -g <rg>` to verify |
| Slow first execution | Cold start + RBAC propagation | Wait 1-2 minutes after deployment for role assignments to propagate |

> [!IMPORTANT]
> **Security note:** This sample uses `allowSharedKeyAccess` on the storage account because Azure Files SMB mounts don't yet support managed identity. The storage account key is stored in Azure Key Vault and referenced during deployment. For production, add network isolation: use **VNet integration** for the function app and restrict storage access with **Private Endpoints** (recommended) or **Service Endpoints**. Disable public network access on the storage account when using Private Endpoints. See [Configure networking for Azure Functions](https://learn.microsoft.com/azure/azure-functions/configure-networking-how-to) for details.

## Customization

Modify `src/process_image.py` to change the FFmpeg processing logic — different filters, output formats (JPEG, PNG, WebP), resize dimensions, watermarks, etc.

## Clean up

```bash
azd down --purge
```

## Tutorial

For a step-by-step walkthrough, see [Tutorial: Process images by using FFmpeg on a mounted Azure Files share](https://learn.microsoft.com/azure/azure-functions/tutorial-ffmpeg-processing-azure-files).

## Learn more

- [Azure Functions Flex Consumption plan](https://learn.microsoft.com/azure/azure-functions/flex-consumption-plan)
- [Choose a file access strategy for Azure Functions](https://learn.microsoft.com/azure/azure-functions/concept-file-access-options)
- [EventGrid blob storage events](https://learn.microsoft.com/azure/event-grid/event-schema-blob-storage)
- [FFmpeg documentation](https://ffmpeg.org/documentation.html)
