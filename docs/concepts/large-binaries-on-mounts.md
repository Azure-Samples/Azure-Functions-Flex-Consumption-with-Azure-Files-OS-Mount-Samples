# Concepts: Running Large Binaries on OS Mounts

This guide explains **how and why** to run large third-party binaries (ffmpeg, ImageMagick, LibreOffice, Pandoc, etc.) from Azure Files OS mounts instead of packaging them with your function code.

## The Problem: Large Binaries in Functions

### Scenario: You need FFmpeg in your function app

FFmpeg binary on Linux is ~150-500 MB depending on the build.

### Option 1: Package It (❌ Bad)

```
Deployment Package
├── __init__.py
├── function_app.py
├── requirements.txt
└── vendor/ffmpeg/    ← 400 MB of binary

Total: ~450 MB
```

**Problems:**
- ❌ Huge deployment artifact (slow to deploy)
- ❌ Wasted space if running multiple instances (400 MB × N instances)
- ❌ Slow cold starts (unzipping 450 MB takes time)
- ❌ Updates require re-deploying the entire package

### Option 2: Download on First Run (⚠️ Mediocre)

```python
def setup_ffmpeg():
    # Download from blob on first invocation
    ffmpeg_blob = blob_client.download_blob("ffmpeg")
    with open("/tmp/ffmpeg", "wb") as f:
        f.write(ffmpeg_blob.readall())
```

**Problems:**
- ⚠️ Cold start latency: first invocation waits for download
- ⚠️ Bandwidth cost: downloading on every instance
- ⚠️ Temporary storage limits (App Service temp disk may be small)

### Option 3: OS Mount (✅ Best)

```
Azure Files Share
└── ffmpeg (400 MB, uploaded once)

Function Instances
├─ Instance 1 → mount at /mnt/binaries/ffmpeg
├─ Instance 2 → mount at /mnt/binaries/ffmpeg
└─ Instance 3 → mount at /mnt/binaries/ffmpeg
```

**Advantages:**
- ✅ Binary uploaded once, shared by all instances
- ✅ Deployment package stays small (~50 KB)
- ✅ Cold starts are fast (no download needed)
- ✅ Updates: just replace the binary on the share

---

## Recommended Pattern: OS Mount

### Architecture

```
┌────────────────────────────────┐
│ Azure Functions Flex            │
│ (Python Code: 50 KB)            │
├────────────────────────────────┤
│ OS Mount: /mnt/binaries         │
│ (FFmpeg: 400 MB, shared)        │
└─────────────┬────────────────────┘
              │
        ┌─────▼──────┐
        │ Azure Files│
        │ (shared    │
        │  mount)    │
        └────────────┘
```

### Step 1: Prepare the Binary

On your local machine:

```bash
# Get ffmpeg (Linux example)
wget https://johnvansickle.com/ffmpeg/releases/ffmpeg-snapshot.tar.xz
tar xf ffmpeg-snapshot.tar.xz
cd ffmpeg-*
./configure --enable-gpl --enable-libx264
make
strip ffmpeg  # Reduce size

# Verify it works
./ffmpeg -version

# Check size
ls -lh ffmpeg  # Should be ~50-500 MB depending on build
```

### Step 2: Upload to Azure Files

```bash
STORAGE_ACCOUNT="myaccount"
SHARE_NAME="binaries"
STORAGE_KEY=$(az storage account keys list \
  --account-name $STORAGE_ACCOUNT \
  --query "[0].value" -o tsv)

# Create directory in share
az storage directory create \
  --share-name $SHARE_NAME \
  --name ffmpeg-bin \
  --account-name $STORAGE_ACCOUNT \
  --account-key $STORAGE_KEY

# Upload binary
az storage file upload \
  --share-name $SHARE_NAME \
  --source ./ffmpeg \
  --path ffmpeg-bin/ffmpeg \
  --account-name $STORAGE_ACCOUNT \
  --account-key $STORAGE_KEY
```

### Step 3: Mount on Function App

Configure the mount (see [Azure Files with Functions](./azure-files-with-functions.md)):

```bicep
azureStorageAccounts: {
  binariesMount: {
    type: 'AzureFiles'
    accountName: storageAccountName
    shareName: 'binaries'
    mountPath: '/mnt/binaries'
  }
}
```

### Step 4: Call Binary from Function

```python
import subprocess
from pathlib import Path

FFMPEG_PATH = "/mnt/binaries/ffmpeg-bin/ffmpeg"
TEMP_PATH = "/mnt/binaries/temp"

@app.function_route(route="convert-video", methods=["POST"])
def convert_video(req):
    input_video = req.get_json()["video_url"]
    
    try:
        result = subprocess.run(
            [
                FFMPEG_PATH,
                "-i", input_video,
                "-vcodec", "libx264",
                "-crf", "23",
                f"{TEMP_PATH}/output.mp4"
            ],
            capture_output=True,
            timeout=300,
            check=True
        )
        return {"status": "success", "message": result.stdout.decode()}
    except subprocess.CalledProcessError as e:
        return {"status": "error", "error": e.stderr.decode()}, 400
```

---

## Common Large Binaries and Setup

### FFmpeg (Video/Audio Processing)

```bash
# Size: ~50-500 MB (depending on dependencies)
# License: LGPL/GPL

# Download pre-built
wget https://johnvansickle.com/ffmpeg/releases/ffmpeg-snapshot.tar.xz

# Or build from source
git clone https://git.ffmpeg.org/ffmpeg.git ffmpeg
cd ffmpeg
./configure --enable-gpl --enable-libx264 --enable-libx265
make -j4
strip ffmpeg
```

**Usage in Functions:**

```python
subprocess.run([
    "/mnt/binaries/ffmpeg",
    "-i", "input.mp4",
    "-vf", "scale=1280:720",
    "output.mp4"
])
```

### ImageMagick (Image Processing)

```bash
# Size: ~20-50 MB

# Pre-built (Linux)
apt-get download imagemagick-6-common imagemagick-6.q16
# Extract binaries

# Or compile from source
wget https://imagemagick.org/download/ImageMagick.tar.gz
tar xzf ImageMagick.tar.gz
cd ImageMagick-*
./configure
make -j4
```

**Usage in Functions:**

```python
subprocess.run([
    "/mnt/binaries/convert",
    "input.jpg",
    "-resize", "200x200",
    "output.jpg"
])
```

### LibreOffice (Document Conversion)

```bash
# Size: ~500+ MB

# Pre-built
wget https://download.documentfoundation.org/libreoffice/stable/latest/linux/...

# Note: Heavy, may not be practical for every invocation
```

**Usage in Functions:**

```python
subprocess.run([
    "/mnt/binaries/libreoffice",
    "--headless",
    "--convert-to", "pdf",
    "--outdir", "/mnt/binaries/output",
    "document.docx"
])
```

### Pandoc (Document Conversion)

```bash
# Size: ~15 MB

wget https://github.com/jgm/pandoc/releases/download/latest/pandoc-latest-linux-amd64.tar.gz
tar xzf pandoc-latest-linux-amd64.tar.gz
```

**Usage in Functions:**

```python
subprocess.run([
    "/mnt/binaries/pandoc",
    "input.md",
    "-f", "markdown",
    "-t", "pdf",
    "-o", "output.pdf"
])
```

---

## Performance Considerations

### Cold Start Impact

```
Cold Start Breakdown (OS Mount):
├─ Container spin-up: ~500 ms
├─ Mount initialization: ~100-200 ms
├─ Python runtime load: ~300 ms
├─ Function code load: ~100 ms
└─ First execution: ~200 ms
    ────────────────────────
    Total: ~1.2 seconds

Subsequent execution: ~200 ms
```

Compare this to **packaging binaries** (adds unzip time and storage initialization).

### Binary Caching

```python
# First invocation: Binary is loaded from network mount into OS cache
subprocess.run(["/mnt/binaries/ffmpeg", ...])  # ~1-2 seconds

# Second invocation: Binary is in OS memory cache
subprocess.run(["/mnt/binaries/ffmpeg", ...])  # ~500 ms
```

The OS automatically caches frequently-accessed executables.

### Temporary File Storage

Store temporary files on the mount too (not `/tmp`):

```python
import tempfile

# Good: Use mount for temp files (persistent, shared)
TEMP_DIR = "/mnt/binaries/temp"
output_file = Path(TEMP_DIR) / "output.mp4"

# Avoid: Use /tmp (limited, ephemeral)
# temp_file = Path("/tmp") / "output.mp4"
```

**Why?**
- `/tmp` is ephemeral (cleared when container stops)
- `/tmp` is smaller and may fill up
- Mount is persistent and shared

---

## Error Handling

### Check Binary Existence

```python
from pathlib import Path

FFMPEG_PATH = "/mnt/binaries/ffmpeg"

def process_with_ffmpeg(input_file):
    if not Path(FFMPEG_PATH).exists():
        raise FileNotFoundError(f"FFmpeg not found at {FFMPEG_PATH}")
    
    result = subprocess.run([FFMPEG_PATH, "-version"], capture_output=True)
    if result.returncode != 0:
        raise RuntimeError("FFmpeg failed to initialize")
```

### Handle Subprocess Errors

```python
def safe_subprocess_call(args, timeout=300):
    try:
        result = subprocess.run(
            args,
            capture_output=True,
            timeout=timeout,
            check=True,
            text=True
        )
        return result.stdout
    except subprocess.TimeoutExpired:
        raise TimeoutError(f"Process timed out after {timeout} seconds")
    except subprocess.CalledProcessError as e:
        raise RuntimeError(f"Process failed: {e.stderr}")
    except FileNotFoundError:
        raise RuntimeError(f"Binary not found: {args[0]}")
```

### Cleanup Temporary Files

```python
import shutil
from pathlib import Path

def cleanup_temp_files():
    TEMP_DIR = Path("/mnt/binaries/temp")
    # Remove files older than 24 hours
    now = time.time()
    for file_path in TEMP_DIR.glob("*"):
        if now - file_path.stat().st_mtime > 24 * 3600:
            file_path.unlink()
```

---

## Updating Binaries

### Scenario: New FFmpeg Release

You don't need to redeploy your function. Just update the binary on the mount:

```bash
# 1. Build new FFmpeg
# ... build steps ...

# 2. Upload to the share, replacing old version
az storage file upload \
  --share-name binaries \
  --source ./ffmpeg \
  --path ffmpeg-bin/ffmpeg \
  --account-name $STORAGE_ACCOUNT \
  --account-key $STORAGE_KEY \
  --overwrite

# 3. Functions automatically use the new version on next invocation
# (No redeployment needed!)
```

This is a huge advantage over packaging: you can update executables without touching your function code.

---

## Multi-Arch Binaries

If you need to support multiple architectures (ARM, x86):

```
Azure Files Share
├── ffmpeg-bin/
│   ├── ffmpeg-x86_64
│   ├── ffmpeg-arm64
│   └── version.txt (metadata)
```

In your function:

```python
import platform

MOUNT_PATH = "/mnt/binaries"
ARCH = platform.machine()  # 'x86_64' or 'aarch64', etc.

def get_ffmpeg_path():
    arch_map = {
        'x86_64': 'ffmpeg-x86_64',
        'aarch64': 'ffmpeg-arm64',
    }
    binary_name = arch_map.get(ARCH)
    if not binary_name:
        raise RuntimeError(f"Unsupported architecture: {ARCH}")
    
    return Path(MOUNT_PATH) / "ffmpeg-bin" / binary_name
```

---

## Best Practices

### ✅ DO

- ✅ Upload binaries once, share across instances
- ✅ Use mount for temporary files (not `/tmp`)
- ✅ Set appropriate timeouts for subprocess calls
- ✅ Cache frequently-used binaries in OS memory
- ✅ Update binaries without redeploying functions
- ✅ Monitor binary execution in Application Insights

### ❌ DON'T

- ❌ Download binary on every invocation
- ❌ Package large binaries with function code
- ❌ Assume binary exists; check before use
- ❌ Leave temporary files around (set cleanup jobs)
- ❌ Run multiple massive binaries concurrently (resource-intensive)
- ❌ Ignore subprocess errors

---

## Performance Benchmarks

Running ffmpeg to convert a 10 MB video:

| Approach | First Invocation | Subsequent | Notes |
|----------|-----------------|-----------|-------|
| **Packaged Binary** | 4-5 sec | 2-3 sec | Unzipping overhead |
| **Downloaded on Use** | 5-8 sec | 3-4 sec | Download overhead |
| **OS Mount** | 2-3 sec | 1-2 sec | ✅ Best option |

---

## Troubleshooting

### "Permission denied" when executing binary

**Cause:** Binary doesn't have execute permissions on Azure Files.

**Solution:**
```bash
# On your local machine, before uploading
chmod +x ffmpeg

# Or fix permissions after upload (if possible)
# Note: Azure Files may not preserve Unix permissions perfectly
```

### "Binary not found" in function

**Cause:** Mount path is incorrect or mount didn't initialize.

**Solution:**
1. Verify mount configuration in function app settings
2. Log the actual path in your function
3. Wait for mount to initialize after deployment

### Slow binary startup

**Cause:** Network latency loading binary from SMB mount.

**Solution:**
1. Use smaller binary builds (strip debug symbols)
2. Ensure function app and storage account are in same region
3. Use Premium storage tier for higher throughput

---

## Next Steps

- **[Quickstart: FFmpeg Image Processing](../quickstart-ffmpeg-processing.md)** — Hands-on example
- **[Shared File Access Patterns](../tutorial-shared-file-access.md)** — Broader context
- **[Azure Files with Functions Concepts](./azure-files-with-functions.md)** — Setup details

**Key Takeaway:** OS mounts let you run large binaries without bloating your deployment. Upload once, share across all instances, and update independently. Perfect for ffmpeg, ImageMagick, and similar tools.
