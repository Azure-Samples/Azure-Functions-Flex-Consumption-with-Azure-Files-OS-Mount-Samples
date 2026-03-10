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

- EventGrid-triggered function that processes images automatically
- FFmpeg binary stored on Azure Files OS mount
- Resize and convert images using FFmpeg
- Output images saved to a dedicated blob container
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
   - Provision all Azure resources (Function App, Storage Account, EventGrid, Azure Files, etc.)
   - Deploy the Python function code
   - Run the post-deployment script to download and upload FFmpeg binary

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
2. EventGrid detects the blob created event and triggers the function
3. The function:
   - Downloads the image from blob storage
   - Processes it using FFmpeg from the `/mounts/tools/` mount
   - Uploads the processed image to `images-output` container
4. Cleanup of temporary files

## File Structure

```
ffmpeg-image-processing/
├── azure.yaml              # azd configuration
├── README.md               # This file
├── src/
│   ├── function_app.py     # EventGrid trigger and app registration
│   ├── process_image.py    # Image processing logic with FFmpeg
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
