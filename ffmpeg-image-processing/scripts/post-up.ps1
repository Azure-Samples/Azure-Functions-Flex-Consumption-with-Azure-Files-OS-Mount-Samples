$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "====================================="
Write-Host "Post-deployment setup"
Write-Host "====================================="
Write-Host ""

# ---------------------------------------------------------------------------
# 1. Load azd environment values
# ---------------------------------------------------------------------------
$RESOURCE_GROUP = (azd env get-value AZURE_RESOURCE_GROUP)
$STORAGE_ACCOUNT = (azd env get-value AZURE_STORAGE_ACCOUNT_NAME)
$FILE_SHARE = (azd env get-value AZURE_STORAGE_FILE_SHARE_NAME)
$FUNCTION_APP_NAME = (azd env get-value AZURE_FUNCTION_APP_NAME)
$FUNCTION_APP_URL = (azd env get-value AZURE_FUNCTION_APP_URL)
$EVENTGRID_TOPIC_NAME = (azd env get-value AZURE_EVENTGRID_TOPIC_NAME)

if (-not $RESOURCE_GROUP -or -not $STORAGE_ACCOUNT -or -not $FILE_SHARE -or -not $FUNCTION_APP_NAME -or -not $FUNCTION_APP_URL) {
    Write-Error "Required environment variables not set. Run 'azd provision' and 'azd deploy' first."
    exit 1
}

Write-Host "📦 Resource Group:  $RESOURCE_GROUP"
Write-Host "💾 Storage Account: $STORAGE_ACCOUNT"
Write-Host "📁 File Share:      $FILE_SHARE"
Write-Host "⚡ Function App:    $FUNCTION_APP_NAME"
Write-Host "🌐 Function URL:    $FUNCTION_APP_URL"
Write-Host ""

# ---------------------------------------------------------------------------
# 2. Download and upload ffmpeg binary to Azure Files
# ---------------------------------------------------------------------------
Write-Host "Downloading ffmpeg static build..."
$FFMPEG_URL = "https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz"
$FFMPEG_ARCHIVE = "ffmpeg-static.tar.xz"

curl -L -o $FFMPEG_ARCHIVE $FFMPEG_URL

Write-Host "Extracting ffmpeg binary..."
$extractDir = "ffmpeg-extract"
New-Item -ItemType Directory -Force -Path $extractDir | Out-Null
tar -xf $FFMPEG_ARCHIVE -C $extractDir
$ffmpegBin = Get-ChildItem -Path $extractDir -Recurse -Filter "ffmpeg" -File | Select-Object -First 1
if (-not $ffmpegBin) {
    Write-Error "Could not find ffmpeg binary in extracted archive."
    exit 1
}
Copy-Item $ffmpegBin.FullName -Destination "./ffmpeg" -Force
Remove-Item -Recurse -Force $extractDir

if (-not (Test-Path "./ffmpeg")) {
    Write-Error "ffmpeg binary not found after extraction."
    exit 1
}

Write-Host "Uploading ffmpeg to Azure Files share..."
$ACCOUNT_KEY = (az storage account keys list --resource-group $RESOURCE_GROUP --account-name $STORAGE_ACCOUNT --query "[0].value" -o tsv)
$env:AZURE_STORAGE_CONNECTION_TIMEOUT = "300"
$maxRetries = 3
for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
    az storage file upload `
      --account-name $STORAGE_ACCOUNT `
      --share-name $FILE_SHARE `
      --source "./ffmpeg" `
      --account-key $ACCOUNT_KEY `
      --timeout 300
    if ($LASTEXITCODE -eq 0) { break }
    if ($attempt -lt $maxRetries) {
        Write-Host "  Upload attempt $attempt failed, retrying in 10 seconds..."
        Start-Sleep -Seconds 10
    }
}
$env:AZURE_STORAGE_CONNECTION_TIMEOUT = $null
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to upload ffmpeg to Azure Files after $maxRetries attempts."
    exit 1
}

Remove-Item -Force -ErrorAction SilentlyContinue $FFMPEG_ARCHIVE, "./ffmpeg"
Write-Host "✅ ffmpeg uploaded to Azure Files."
Write-Host ""

# ---------------------------------------------------------------------------
# 3. Create EventGrid subscription (requires deployed function code)
# ---------------------------------------------------------------------------
Write-Host "Setting up EventGrid subscription..."

# Get storage account resource ID
$STORAGE_RESOURCE_ID = (az storage account show `
  --name $STORAGE_ACCOUNT `
  --resource-group $RESOURCE_GROUP `
  --query "id" -o tsv)

# Determine system topic name — use Bicep output if available, otherwise derive
if (-not $EVENTGRID_TOPIC_NAME) {
    Write-Host "  AZURE_EVENTGRID_TOPIC_NAME not set; looking up existing system topic..."
    $EVENTGRID_TOPIC_NAME = (az eventgrid system-topic list `
      --resource-group $RESOURCE_GROUP `
      --query "[?source=='$STORAGE_RESOURCE_ID'].name | [0]" -o tsv)
}

if (-not $EVENTGRID_TOPIC_NAME) {
    Write-Error "Could not determine EventGrid system topic name."
    exit 1
}

Write-Host "  System topic: $EVENTGRID_TOPIC_NAME"

# Get the blobs_extension system key (exists only after code is deployed)
Write-Host "Retrieving blobs_extension system key..."
$MAX_RETRIES = 6
$RETRY_DELAY = 10
$BLOBS_KEY = $null

for ($i = 1; $i -le $MAX_RETRIES; $i++) {
    $BLOBS_KEY = (az functionapp keys list `
      -n $FUNCTION_APP_NAME `
      -g $RESOURCE_GROUP `
      --query "systemKeys.blobs_extension" -o tsv 2>$null)

    if ($BLOBS_KEY -and $BLOBS_KEY -ne "null") {
        break
    }
    Write-Host "  Waiting for function host to register system keys (attempt $i/$MAX_RETRIES)..."
    Start-Sleep -Seconds $RETRY_DELAY
}

if (-not $BLOBS_KEY -or $BLOBS_KEY -eq "null") {
    Write-Error "Could not retrieve blobs_extension system key. Ensure function code is deployed and the host has started."
    exit 1
}
Write-Host "  blobs_extension key retrieved."

# Build the correct blob trigger webhook endpoint
$WEBHOOK_ENDPOINT = "$FUNCTION_APP_URL/runtime/webhooks/blobs?functionName=Host.Functions.process_image_blob&code=$BLOBS_KEY"

$SUBSCRIPTION_NAME = "blob-created-subscription"

# Wait for function host to be ready before creating EventGrid subscription
Write-Host "Waiting for function host to be ready..."
for ($i = 1; $i -le 6; $i++) {
    try {
        $resp = Invoke-WebRequest -Uri "$FUNCTION_APP_URL/admin/host/status?code=$BLOBS_KEY" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        if ($resp.StatusCode -eq 200) {
            Write-Host "  Function host is ready."
            break
        }
    } catch { }
    Write-Host "  Host not ready yet (attempt $i/6), waiting 15 seconds..."
    Start-Sleep -Seconds 15
}

# Create (or update) the EventGrid subscription with retry
Write-Host "Creating EventGrid subscription: $SUBSCRIPTION_NAME..."
$subscriptionCreated = $false
for ($attempt = 1; $attempt -le 3; $attempt++) {
    az eventgrid system-topic event-subscription create `
      --name $SUBSCRIPTION_NAME `
      --system-topic-name $EVENTGRID_TOPIC_NAME `
      --resource-group $RESOURCE_GROUP `
      --endpoint-type webhook `
      --endpoint "$WEBHOOK_ENDPOINT" `
      --included-event-types "Microsoft.Storage.BlobCreated" `
      --subject-begins-with "/blobServices/default/containers/images-input/" `
      --event-delivery-schema eventgridschema `
      --output none
    if ($LASTEXITCODE -eq 0) {
        $subscriptionCreated = $true
        break
    }
    if ($attempt -lt 3) {
        Write-Host "  Webhook validation failed (attempt $attempt/3), retrying in 20 seconds..."
        Start-Sleep -Seconds 20
    }
}
if (-not $subscriptionCreated) {
    Write-Host "  WARNING: EventGrid subscription creation failed. You may need to create it manually after the function host is fully warmed up."
}
Write-Host ""

# ---------------------------------------------------------------------------
# 4. Health check
# ---------------------------------------------------------------------------
Write-Host "Running health check..."
$HEALTH_URL = "$FUNCTION_APP_URL/api/health"
try {
    $response = Invoke-WebRequest -Uri $HEALTH_URL -UseBasicParsing -ErrorAction Stop
    $HTTP_CODE = $response.StatusCode
} catch {
    $HTTP_CODE = $_.Exception.Response.StatusCode.value__
    if (-not $HTTP_CODE) { $HTTP_CODE = 0 }
}

if ($HTTP_CODE -eq 200) {
    Write-Host "  Health check passed (HTTP $HTTP_CODE)"
    (Invoke-RestMethod -Uri $HEALTH_URL -ErrorAction SilentlyContinue) | Select-Object -First 20
} elseif ($HTTP_CODE -eq 503) {
    Write-Host "  Health check returned degraded (HTTP $HTTP_CODE)"
    Write-Host "  ffmpeg may not be mounted yet. RBAC propagation can take 1-2 minutes."
} else {
    Write-Host "  Health check returned HTTP $HTTP_CODE - the function host may still be starting."
    Write-Host "  Try again in a minute: Invoke-RestMethod $HEALTH_URL"
}

Write-Host ""
Write-Host "====================================="
Write-Host "Post-deployment setup complete!"
Write-Host "====================================="
Write-Host ""
Write-Host "Test the sample:"
Write-Host "  az storage blob upload ``"
Write-Host "    --account-name $STORAGE_ACCOUNT ``"
Write-Host "    --container-name images-input ``"
Write-Host "    --name test-image.jpg ``"
Write-Host "    --file <local-image-path> ``"
Write-Host "    --auth-mode login"
