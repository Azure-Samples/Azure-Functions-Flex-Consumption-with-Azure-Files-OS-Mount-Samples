# Concepts: Flex Consumption & OS Mounts

This guide explains **what** Flex Consumption is, **what** OS mounts are, and **how they work together**.

## What is Azure Functions Flex Consumption?

**Flex Consumption** is a hosting plan for Azure Functions that combines:
- **Pay-per-execution pricing** (like Consumption) — You only pay for the time your code runs
- **Premium performance** — Better CPU and memory allocations than Consumption
- **Persistent resources** — Dedicated storage and networking that persist between invocations

It's ideal for workloads that are bursty or require more performance than standard Consumption but don't justify always-on Premium.

### How Flex Consumption Works

```
Request arrives → Function container spins up → Code executes → Results returned → Container idles
                  (cold start ~1-2 sec)     (milliseconds)                      (can scale down)
```

Each invocation runs in a dedicated Linux container. Multiple instances spin up to handle concurrent requests.

### Flex Consumption vs. Other Plans

| Feature | Consumption | Flex Consumption | Premium | App Service |
|---------|-------------|------------------|---------|------------|
| Pricing | Per execution | Per execution | Per hour (app plan) | Per hour |
| Cold start | ~3-4 sec | ~1-2 sec | ~100 ms | Instant |
| OS mounts | ❌ Not supported | ✅ Supported | ✅ Supported | ✅ Supported |
| Guaranteed runtime | 5 min | 30 min | Unlimited | Unlimited |
| Scalability | Highly elastic | Elastic | Semi-elastic | Manual |
| Storage quota | Temporary | Persistent | Persistent | Persistent |

**When to choose Flex Consumption:**
- Bursty workloads with occasional large requests
- Need OS mounts but don't need Premium's guaranteed runtime
- Cost-sensitive but performance-sensitive
- Example: Scheduled batch processing, on-demand image conversion, data pipeline triggers

## What Are OS Mounts?

An **OS mount** is a **network file system mounted into the function container's file system** as if it were a local directory.

### How OS Mounts Work

```
Your Function Code
       ↓
  sys.open("/mnt/data/file.txt", "r")
       ↓
  Linux Kernel (VFS)
       ↓
  SMB Client (in container)
       ↓
  SMB Protocol (over TCP)
       ↓
  Azure Files Share
       ↓
  Storage Account
```

From your code's perspective, `/mnt/data/` is a normal directory. Under the hood, every file operation is translated via SMB (Server Message Block) to the remote Azure Files share.

### Mounting Process

1. **At container startup** — Azure Functions initializes the mount using managed identity credentials
2. **Authentication** — The function app's managed identity proves its identity to the storage account
3. **Authorization** — The storage account checks if the identity has permission (RBAC role)
4. **Mount establishment** — If authorized, the SMB share is mounted at the specified path
5. **At container runtime** — Code uses standard file APIs; the OS handles network I/O transparently

```
Container Startup
    ├─ Load managed identity token
    ├─ Connect to storage account (HTTPS)
    ├─ Authenticate: "I am [managed-identity] from [resource-group]"
    ├─ Check RBAC: "Do I have permission to access this share?"
    ├─ Establish SMB mount: /mnt/filedata → \\storageaccount.file.core.windows.net\sharename
    └─ Return to app runtime

Runtime
    ├─ Code: open("/mnt/filedata/data.json", "r")
    ├─ OS translates to SMB READ on share
    └─ File content returned to code
```

## Flex Consumption + OS Mounts: The Combination

When you use Flex Consumption with OS mounts, you get:

### ✅ Advantages

1. **Direct file access** — No need to download from Blob Storage every time
2. **Shared access** — All instances of your function app mount the same share
3. **POSIX semantics** — Standard Python file APIs (`open()`, `os.listdir()`, etc.)
4. **Large files** — Mount 4 TiB files; no size limits on downloads
5. **Large binaries** — Deploy executables (ffmpeg, ImageMagick) on the mount, not in your package
6. **Fast cold starts** — Deployment package is smaller (no large binaries)

### ⚠️ Trade-Offs

1. **Network latency** — SMB is slower than local disk. Expect 10-50ms additional latency per file operation
2. **Not for tiny data** — For megabytes of transient data, Blob Storage bindings may be faster
3. **Authentication overhead** — First mount setup adds ~200-500ms to cold start
4. **Regional** — Mounts work best in the same region as your function app
5. **Consistency** — Eventual consistency for writes; multiple writers need coordination

### ❌ Limitations

- **Consumption Plan** — Can't use mounts on standard Consumption (only Flex and Premium)
- **Windows containers** — OS mounts currently work on Linux containers in Flex Consumption
- **Cross-subscription** — Mount requires the storage account to be in the same subscription
- **Performance** — Not suitable for real-time streaming or very high-throughput file I/O

## Architecture: Flex Consumption with Mounts

```
┌──────────────────────────────────────────────────────────┐
│ Your Application Logic                                   │
│ (Python code using standard file APIs)                   │
└──────────────────────────────────────────────────────────┘
                          ↓
┌──────────────────────────────────────────────────────────┐
│ Flex Consumption Function App                            │
│                                                          │
│  Instance 1      Instance 2      Instance 3            │
│  ┌─────────┐     ┌─────────┐     ┌─────────┐           │
│  │ trigger │     │ trigger │     │ trigger │           │
│  │   ↓     │     │   ↓     │     │   ↓     │           │
│  │ /mnt    │     │ /mnt    │     │ /mnt    │           │
│  └────┬────┘     └────┬────┘     └────┬────┘           │
│       └──────────┬────────────────┬───┘                  │
│                  │                │                      │
│    ┌─────────────▼────────────────▼──────────┐          │
│    │ Shared OS Mount (SMB over TCP)          │          │
│    │ Local Path: /mnt/filedata               │          │
│    └─────────────┬────────────────┬──────────┘          │
└────────────────┼────────────────┼────────────────────────┘
                 │                │
        ┌────────▼────────────────▼─────────┐
        │   Azure Files SMB Protocol        │
        │   \\storageaccount.file.core...   │
        └────────────┬─────────────────────┘
                     │
        ┌────────────▼─────────────┐
        │  Storage Account         │
        │  (Managed Identity auth) │
        │  (RBAC enforcement)      │
        └──────────────────────────┘
```

All instances see `/mnt/filedata` as if it's a local directory. The mount is established at container startup using the function app's managed identity.

## Performance Characteristics

### Latency

- **First file operation**: ~50-100ms (mount cache miss)
- **Subsequent operations**: ~10-30ms (cached in OS)
- **Binary launches**: ~500ms first time, then fast (OS caches executable)

### Throughput

- **Sequential read**: Up to 60 MB/s (standard storage)
- **Sequential write**: Up to 60 MB/s (standard storage)
- **Premium storage**: Up to 100+ MB/s

### Concurrency

- **Multiple readers**: High concurrency, no locking needed
- **Multiple writers**: SMB handles it, but consider file locks for coordination

## Configuration on Flex Consumption

To enable a mount on your Flex Consumption function app, you configure:

1. **Mount path** (in container) — e.g., `/mnt/filedata`
2. **Storage account** — Which account to connect to
3. **Share name** — Which share within the account
4. **Read/Write or Read-Only** — Permissions for the mount

### Via Bicep

```bicep
resource functionApp 'Microsoft.Web/sites@2022-03-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: flexPlan.id
    httpsOnly: true
    storageAccountRequired: true
    
    // Mount configuration
    siteConfig: {
      linuxFxVersion: 'PYTHON|3.11'
      azureStorageAccounts: {
        dataMount: {
          type: 'AzureFiles'
          accountName: storageAccount.name
          shareName: 'myshare'
          mountPath: '/mnt/filedata'
          accessKey: storageAccount.listKeys().keys[0].value
        }
      }
    }
  }
}
```

### Via Azure Portal

1. Open your function app → **Settings > Configuration**
2. Select **Path Mappings** tab
3. Add a new Azure Files mount:
   - **Local path**: `/mnt/filedata`
   - **Storage account**: Select your account
   - **Share name**: Select your share
   - **Access key**: (populated from storage account)
   - **Read/Write** or **Read-Only**: Choose

### Via Azure CLI

```bash
az functionapp config appsettings set \
  --resource-group $RESOURCE_GROUP \
  --name $FUNCTION_APP_NAME \
  --settings \
    WEBSITE_MOUNT_ENABLED=true \
    WEBSITE_MOUNT_PATH=/mnt/filedata \
    WEBSITE_MOUNT_SHARE_NAME=myshare \
    WEBSITE_MOUNT_ACCOUNT_NAME=$STORAGE_ACCOUNT
```

> [!NOTE]
> For production, use managed identity instead of storage account keys. See [Azure Files with Functions Concepts](./azure-files-with-functions.md#managed-identity-setup) for details.

## When to Use Flex Consumption + OS Mounts

### ✅ Good Fit

- **Shared reference data** (ML models, lookup tables, corpus)
- **Large binary execution** (ffmpeg, ImageMagick, custom tools)
- **Parallel batch processing** with shared inputs
- **Cost-sensitive workloads** with occasional bursts
- **Bursty I/O workloads** (read-heavy, write-occasional)

### ❌ Bad Fit

- **Real-time streaming** (EventHubs, Kafka are better)
- **Sub-millisecond latency requirements** (local disk only)
- **Highly transactional workflows** (database is better)
- **Multi-tenant with strong isolation** (container isolation is limited)

---

## Key Takeaways

1. **Flex Consumption** = pay-per-execution + better performance than standard Consumption
2. **OS mounts** = network file system mounted as local directory via SMB
3. **Together** = cost-effective shared file access with POSIX semantics
4. **Best for** = shared binaries, large files, batch processing
5. **Trade-off** = network latency vs. simplicity and direct file access

Next, learn how to [set up Azure Files with Functions](./azure-files-with-functions.md).
