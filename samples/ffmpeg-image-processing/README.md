# ffmpeg Image Processing — Azure Functions Flex Consumption + Azure Files

This sample shows how to use a **large binary (ffmpeg)** stored on an
**Azure Files OS mount** to process images inside an Azure Functions
**Flex Consumption** app.

## What it does

1. A **Blob-triggered function** fires when a new image lands in the
   `images-input` storage container.
2. The function reads the image and shells out to the **ffmpeg binary**
   located on the OS mount (e.g. `/mounts/tools/ffmpeg`).
3. ffmpeg resizes and converts the image.
4. The processed image is written to the `images-output` container via a
   Blob output binding.

## Why use an OS mount for ffmpeg?

Flex Consumption function apps have a **deployment package size limit**.
ffmpeg is ~100 MB — too large to bundle.  By placing the binary on an
Azure Files share and mounting it into the function app at the OS level,
every instance sees the binary at a well-known path without inflating
the deployment package.

## Architecture

```
Blob (images-input)
        │
        ▼
  Blob Trigger ──► process_image.py ──► ffmpeg @ /mounts/tools/ffmpeg
        │
        ▼
  Blob Output (images-output)
```

## Prerequisites

| Tool | Version |
|------|---------|
| Python | 3.10+ |
| Azure Functions Core Tools | 4.x |
| Azure CLI | 2.60+ |
| Azurite (for local dev) | latest |
| ffmpeg | 6.x (static build) |

## Quickstart — local development

```bash
# 1. Copy the example settings
cp local.settings.json.example local.settings.json

# 2. Install dependencies
pip install -r requirements.txt

# 3. Create local mount dirs and place ffmpeg
mkdir -p /tmp/mounts/tools
# Copy or symlink a local ffmpeg binary:
ln -s $(which ffmpeg) /tmp/mounts/tools/ffmpeg

# 4. Update local.settings.json:
#    "FFMPEG_PATH": "/tmp/mounts/tools/ffmpeg"

# 5. Start Azurite (in a separate terminal)
azurite --silent

# 6. Create the blob containers
az storage container create -n images-input  --connection-string "UseDevelopmentStorage=true"
az storage container create -n images-output --connection-string "UseDevelopmentStorage=true"

# 7. Start the function app
func start

# 8. Upload a test image
az storage blob upload -f test.png -c images-input -n test.png \
   --connection-string "UseDevelopmentStorage=true"
```

The processed image will appear in `images-output`.

## Health check

```bash
curl http://localhost:7071/api/health
```

Returns JSON with `ffmpeg_available: true` if the binary is reachable.

## Deploy to Azure

```bash
# From the repo root
bash infra/scripts/deploy-sample.sh ffmpeg-image-processing
```

Or deploy manually — see `../../infra/README.md` for details.

## Project structure

| File | Purpose |
|------|---------|
| `function_app.py` | App entry point; blob trigger + health endpoint |
| `process_image.py` | ffmpeg subprocess wrapper (resize, convert) |
| `host.json` | Extension bundle configuration |
| `requirements.txt` | Python dependencies |
| `local.settings.json.example` | Template for local settings |

## Configuration

| Setting | Description | Default |
|---------|-------------|---------|
| `FFMPEG_PATH` | Path to the ffmpeg binary on the OS mount | `/mounts/tools/ffmpeg` |
| `OUTPUT_WIDTH` | Target image width in pixels | `800` |
| `OUTPUT_FORMAT` | Output format (png, jpg, webp, etc.) | `png` |
| `AzureWebJobsStorage` | Storage connection string | (required) |

## License

MIT — see [LICENSE](../../LICENSE) in the repository root.
