# Tutorial: Shared File Access Patterns with Azure Files OS Mounts

This tutorial explores **when, how, and why** to use Azure Files OS mounts with Azure Functions Flex Consumption. You'll learn the trade-offs between mounts, storage bindings, and external coordination, and see patterns for real-world scenarios.

## The Problem: Sharing Files Between Functions

When you need to share data between function instances, you have three main options:

| Approach | Pros | Cons | Best For |
|----------|------|------|----------|
| **Storage Bindings** | Simple, cloud-native, secure | Network overhead, eventual consistency | Moving data to/from cloud services (queues, blobs) |
| **External Database** | Flexible, transactional | Network calls, complexity | Structured data, complex queries |
| **OS Mount (Azure Files)** | Direct file access, POSIX semantics, large binaries | Slower than local disk, requires Flex Consumption | Large files, shared executables, frequent access |

This tutorial focuses on **OS mounts** — when they're the right choice, and how to use them safely.

## Concept: What is an OS Mount?

An OS mount is a **network file share mounted as if it were a local directory**. When you mount an Azure Files share on your function app, the path appears in the function container's file system:

```
Your Function Code
    ↓
/mnt/mydata/  (appears as local directory)
    ↓
Azure Files Share (via SMB protocol over network)
    ↓
Storage Account
```

Your code uses standard Python file APIs (`open()`, `os.listdir()`, etc.) without knowing it's talking to the network. This is the **POSIX semantics** — your code looks like local file I/O.

## Scenario 1: Parallel Analysis of Shared Files

**Use case:** You have 1000 analysis tasks that all need to read from the same set of reference data files (e.g., ML models, lookup tables, corpus data).

### The Problem

Without mounts, you have two bad options:

1. **Package the reference files with your function** → Huge deployment artifact, slow cold starts, storage redundancy
2. **Download from Blob Storage each time** → Network latency on every function invocation, wasted bandwidth

### The Mount Solution

```
Function Instance 1 ┐
Function Instance 2 ├→ /mnt/models/  (shared OS mount) → Azure Files Share
Function Instance 3 ┘
```

All instances read from the mounted share directly. No network overhead (after mount), no redundant storage.

### Implementation Pattern

```python
import os
from pathlib import Path

MOUNT_PATH = "/mnt/models"

def analyze_data(item: str) -> dict:
    """Activity function: reads from shared mount."""
    model_path = Path(MOUNT_PATH) / "model.pkl"
    
    # Direct file I/O — no SDK call, no network overhead
    with open(model_path, "rb") as f:
        model = pickle.load(f)
    
    result = model.predict(item)
    return {"item": item, "score": result}
```

**Key points:**
- All instances of your function app see the same mount
- File reads are POSIX-compliant — use standard Python file APIs
- No need to authenticate per read (mount is authenticated once at startup)
- Changes written by one instance are visible to others immediately

### Security Considerations

1. **Managed Identity** — The function app's managed identity must have **Storage File Data SMB Share Contributor** role on the storage account
2. **Read-Only Option** — If your workload doesn't need to write, restrict the mount to read-only (e.g., `ro` mount option in CIFS)
3. **Quotas** — Set Azure Files share quotas to prevent runaway costs if instances write large files

## Scenario 2: Shared Executables (FFmpeg, ImageMagick, etc.)

**Use case:** You need to run a large third-party binary (500+ MB) on every instance, but you don't want to package it with your function code.

### The Problem

Without mounts:

1. **Package binary in deployment artifact** → 500+ MB per instance, slow deployment, wasted bandwidth
2. **Download from Blob on each invocation** → Network call on every execution, slower than local

### The Mount Solution

Upload the binary once to Azure Files. All instances access it from the mount. Boom.

```
Deployment Package: 10 MB (just your code)
    ↓
Mount: /mnt/binaries/ffmpeg (500 MB, shared, downloaded once)
    ↓
Execution: subprocess.run(["/mnt/binaries/ffmpeg", ...])
```

### Implementation Pattern

```python
import subprocess
from pathlib import Path

FFMPEG_PATH = "/mnt/binaries/ffmpeg"
TEMP_PATH = "/mnt/binaries/temp"

def process_video(video_file: str) -> str:
    """Activity function: calls ffmpeg from mount."""
    input_file = Path(TEMP_PATH) / video_file
    output_file = Path(TEMP_PATH) / f"{video_file}.mp4"
    
    # Call binary from mount
    result = subprocess.run(
        [FFMPEG_PATH, "-i", str(input_file), "-codec", "libx264", str(output_file)],
        capture_output=True,
        timeout=300
    )
    
    if result.returncode != 0:
        raise Exception(f"FFmpeg error: {result.stderr.decode()}")
    
    return str(output_file)
```

**Key points:**
- Binary is mounted, not packaged
- Deployment artifact stays small
- Cold starts are faster (less to unzip)
- All instances can call the same binary concurrently

### Performance Implications

- **First execution:** SMB mount initialization adds ~200-500ms
- **Subsequent executions:** Direct file access, minimal overhead
- **Binary caching:** The OS caches the binary in memory, reducing repeated disk reads

> [!TIP]
> For frequently-called binaries, the performance overhead is negligible after the first few invocations.

## Scenario 3: Data Sharing Between Multiple Function Apps

**Use case:** You have App A (data producer) and App B (data consumer) running in the same region. App A writes processed data; App B reads it.

### Without Mounts

You'd use:
- Azure Blob Storage (decoupled, but network overhead)
- Azure Queue Storage + message passing (eventual consistency)
- Cosmos DB or SQL Database (overkill for simple file sharing)

### With Mounts

Both apps mount the same Azure Files share. App A writes; App B reads. No message passing, no eventual consistency.

```
App A (Consumer) ┐
App B (Producer) ├→ /mnt/shared/  → Azure Files Share (single source of truth)
```

### Implementation Pattern

**App A (Producer):**

```python
from pathlib import Path
import json

MOUNT_PATH = "/mnt/shared"

def write_results(data: dict) -> None:
    """Write results to shared mount."""
    output_file = Path(MOUNT_PATH) / "latest_results.json"
    with open(output_file, "w") as f:
        json.dump(data, f)
```

**App B (Consumer):**

```python
from pathlib import Path
import json

MOUNT_PATH = "/mnt/shared"

def read_results() -> dict:
    """Read results from shared mount."""
    results_file = Path(MOUNT_PATH) / "latest_results.json"
    if not results_file.exists():
        return {}
    with open(results_file, "r") as f:
        return json.load(f)
```

**Key points:**
- Both apps need their own managed identity with the appropriate role
- Use file locks (e.g., `fcntl` on Linux) to prevent read/write race conditions
- Azure Files supports concurrent reads; writes should be sequential or locked

> [!WARNING]
> Azure Files does NOT provide database-level transactions. If you need atomic writes and reads, consider Cosmos DB or SQL Database instead.

## Best Practices

### 1. Use Managed Identity, Not Keys

```python
# Bad: Storing connection strings
connection_string = os.getenv("STORAGE_CONNECTION_STRING")

# Good: Let Azure SDK use managed identity
from azure.storage.fileshare import ShareServiceClient

account_url = f"https://{storage_account}.file.core.windows.net"
share_client = ShareServiceClient(account_url=account_url).get_share_client(share_name)
```

### 2. Set Mount Quotas

Prevent runaway storage costs by setting a quota on your Azure Files share:

```bash
az storage share-rm update \
  --resource-group $RESOURCE_GROUP \
  --storage-account $STORAGE_ACCOUNT \
  --name myshare \
  --quota 100  # 100 GB limit
```

### 3. Monitor File Access

Enable diagnostics on your storage account to see mount access patterns:

```bash
az monitor metrics list \
  --resource /subscriptions/.../storageAccounts/$STORAGE_ACCOUNT/fileServices/default \
  --metric Transactions
```

### 4. Use Read-Only Mounts When Possible

If your function only reads from the mount, configure it as read-only:

```bicep
// In your Bicep template, set mount as read-only
"mountPath": "/mnt/data",
"shareName": "data",
"storageAccountName": storageAccountName,
"readOnly": true  // ← Prevents accidental writes
```

### 5. Clean Up Temporary Files

If your functions write to the mount, implement cleanup:

```python
from pathlib import Path
import shutil

MOUNT_PATH = "/mnt/temp"
TEMP_THRESHOLD = 24 * 60 * 60  # 24 hours

def cleanup_old_files():
    """Remove temp files older than 24 hours."""
    cutoff_time = time.time() - TEMP_THRESHOLD
    for file_path in Path(MOUNT_PATH).iterdir():
        if file_path.stat().st_mtime < cutoff_time:
            file_path.unlink()
```

## Limitations and When NOT to Use Mounts

### ❌ Don't Use Mounts For:

1. **Small transient data** — Use Azure Queue Storage or Blob Storage bindings instead
2. **Frequent small reads/writes** — SMB overhead > direct HTTP. Use CosmosDB or Redis
3. **Real-time streaming** — Mounts aren't designed for continuous streaming. Use Event Hubs or IoT Hub
4. **Cross-region data sharing** — Mounts are best in the same region. For multi-region, use Blob Storage replication
5. **Consumption Plan functions** — Only Flex Consumption and App Service support OS mounts

### Mount Limits

| Limit | Value |
|-------|-------|
| Share size | Up to 100 TiB |
| File size | Up to 4 TiB |
| Throughput | ~60 MB/s (standard), ~100+ MB/s (premium) |
| Concurrency | Many (SMB handles it), but writes serialize |

See [Azure Files scale targets](https://learn.microsoft.com/azure/storage/files/storage-files-scale-targets).

## Comparison: Mounts vs. Bindings vs. External Storage

### Example: Processing 1000 images stored in a reference folder

**Option A: Blob Binding (with download)**
```python
# Download reference folder before processing
files = container_client.list_blobs(name_starts_with="reference/")
for blob in files:
    stream = container_client.download_blob(blob.name)
    # ... process ...
    # Cost: 1000 GET requests × 1 MB = high bandwidth cost + latency
```

**Option B: OS Mount (read from share)**
```python
# Mount is already available
for file_path in Path("/mnt/reference").iterdir():
    with open(file_path, "rb") as f:
        # ... process ...
    # Cost: One mount setup + local reads, minimal bandwidth
```

**Option C: External Database (CosmosDB)**
```python
# Query reference data via SDK
reference_data = container.query_items(
    query="SELECT * FROM reference WHERE id IN (...)"
)
# Cost: Query RUs + network latency, good for structured data
```

**Winner for large shared files:** Option B (mounts)

---

## Architecture Diagram (Conceptual)

```
┌─────────────────────────────────────────────────────────┐
│ Azure Functions Flex Consumption                        │
│                                                         │
│  ┌──────────────────────────────────────────────┐      │
│  │ Function Instance 1         Function Instance 2      │
│  │  code → /mnt/myshare/data   code → /mnt/myshare/data│
│  │          (local POSIX I/O)         (local POSIX I/O) │
│  │  ↓                                 ↓                 │
│  │  SMB Mount                    SMB Mount              │
│  └───────────────────┬──────────────────────────┘      │
│                      │                                  │
│  ┌──────────────────────────────────────────────┐      │
│  │ OS-Level Networking (SMB over TCP)          │      │
│  └───────────────────┬──────────────────────────┘      │
│                      │                                  │
└──────────────────────┼──────────────────────────────────┘
                       │
        ┌──────────────┴──────────────┐
        │                             │
    ┌───▼─────────────────┐  ┌───────▼───┐
    │ Azure Files Share   │  │ Firewall  │
    │ (SMB Protocol)      │  └───────────┘
    └─────────────────────┘
                 │
                 ▼
    ┌─────────────────────┐
    │ Storage Account     │
    │ (Managed Identity   │
    │  auth + RBAC)       │
    └─────────────────────┘
```

---

## Next Steps

- **[Quickstart: Durable Text Analysis](../quickstart-durable-text-analysis.md)** — Try a real example with mounts
- **[Quickstart: FFmpeg Image Processing](../quickstart-ffmpeg-processing.md)** — Run a large binary via mounts
- **[Flex Consumption & OS Mounts Concepts](./flex-consumption-os-mounts.md)** — Understand the platform deeper
- **[Azure Files with Functions Concepts](./azure-files-with-functions.md)** — Setup and configuration

---

**Key Takeaway:** OS mounts are perfect when you need to share large files or executables between function instances. They're simple, fast, and don't require external coordination logic.
