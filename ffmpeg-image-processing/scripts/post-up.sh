#!/bin/bash
set -e

echo ""
echo "====================================="
echo "Post-deployment setup"
echo "====================================="
echo ""

# ---------------------------------------------------------------------------
# 1. Load azd environment values
# ---------------------------------------------------------------------------
RESOURCE_GROUP=$(azd env get-value AZURE_RESOURCE_GROUP)
STORAGE_ACCOUNT=$(azd env get-value AZURE_STORAGE_ACCOUNT_NAME)
FILE_SHARE=$(azd env get-value AZURE_STORAGE_FILE_SHARE_NAME)
FUNCTION_APP_NAME=$(azd env get-value AZURE_FUNCTION_APP_NAME)
FUNCTION_APP_URL=$(azd env get-value AZURE_FUNCTION_APP_URL)
EVENTGRID_TOPIC_NAME=$(azd env get-value AZURE_EVENTGRID_TOPIC_NAME)

if [ -z "$RESOURCE_GROUP" ] || [ -z "$STORAGE_ACCOUNT" ] || [ -z "$FILE_SHARE" ] || [ -z "$FUNCTION_APP_NAME" ] || [ -z "$FUNCTION_APP_URL" ]; then
    echo "❌ Error: Required environment variables not set."
    echo "   Run 'azd provision' and 'azd deploy' first."
    exit 1
fi

echo "📦 Resource Group:  $RESOURCE_GROUP"
echo "💾 Storage Account: $STORAGE_ACCOUNT"
echo "📁 File Share:      $FILE_SHARE"
echo "⚡ Function App:    $FUNCTION_APP_NAME"
echo "🌐 Function URL:    $FUNCTION_APP_URL"
echo ""

# ---------------------------------------------------------------------------
# 2. Download and upload ffmpeg binary to Azure Files
# ---------------------------------------------------------------------------
echo "⬇️  Downloading ffmpeg static build..."
FFMPEG_URL="https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz"
FFMPEG_ARCHIVE="ffmpeg-static.tar.xz"

curl -L -o "$FFMPEG_ARCHIVE" "$FFMPEG_URL"

echo "📦 Extracting ffmpeg binary..."
tar -xf "$FFMPEG_ARCHIVE" --strip-components=1 "*/ffmpeg"

echo "⬆️  Uploading ffmpeg to Azure Files share..."
az storage file upload \
  --account-name "$STORAGE_ACCOUNT" \
  --share-name "$FILE_SHARE" \
  --source ./ffmpeg \
  --path ffmpeg \
  --auth-mode key

rm -f "$FFMPEG_ARCHIVE" ffmpeg
echo "✅ ffmpeg uploaded to Azure Files."
echo ""

# ---------------------------------------------------------------------------
# 3. Create EventGrid subscription (requires deployed function code)
# ---------------------------------------------------------------------------
echo "🔗 Setting up EventGrid subscription..."

# Get storage account resource ID
STORAGE_RESOURCE_ID=$(az storage account show \
  --name "$STORAGE_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --query "id" -o tsv)

# Determine system topic name — use Bicep output if available, otherwise derive
if [ -z "$EVENTGRID_TOPIC_NAME" ]; then
    echo "⚠️  AZURE_EVENTGRID_TOPIC_NAME not set; looking up existing system topic..."
    EVENTGRID_TOPIC_NAME=$(az eventgrid system-topic list \
      --resource-group "$RESOURCE_GROUP" \
      --query "[?source=='${STORAGE_RESOURCE_ID}'].name | [0]" -o tsv)
fi

if [ -z "$EVENTGRID_TOPIC_NAME" ]; then
    echo "❌ Error: Could not determine EventGrid system topic name."
    exit 1
fi

echo "   System topic: $EVENTGRID_TOPIC_NAME"

# Get the blobs_extension system key (exists only after code is deployed)
echo "🔑 Retrieving blobs_extension system key..."
MAX_RETRIES=6
RETRY_DELAY=10
BLOBS_KEY=""

for i in $(seq 1 $MAX_RETRIES); do
    BLOBS_KEY=$(az functionapp keys list \
      -n "$FUNCTION_APP_NAME" \
      -g "$RESOURCE_GROUP" \
      --query "systemKeys.blobs_extension" -o tsv 2>/dev/null || true)

    if [ -n "$BLOBS_KEY" ] && [ "$BLOBS_KEY" != "null" ]; then
        break
    fi
    echo "   Waiting for function host to register system keys (attempt $i/$MAX_RETRIES)..."
    sleep $RETRY_DELAY
done

if [ -z "$BLOBS_KEY" ] || [ "$BLOBS_KEY" = "null" ]; then
    echo "❌ Error: Could not retrieve blobs_extension system key."
    echo "   Ensure function code is deployed and the host has started."
    exit 1
fi
echo "   ✅ blobs_extension key retrieved."

# Build the correct blob trigger webhook endpoint
WEBHOOK_ENDPOINT="${FUNCTION_APP_URL}/runtime/webhooks/blobs?functionName=Host.Functions.process_image_blob&code=${BLOBS_KEY}"

SUBSCRIPTION_NAME="blob-created-subscription"

# Create (or update) the EventGrid subscription
echo "📡 Creating EventGrid subscription: $SUBSCRIPTION_NAME..."
az eventgrid system-topic event-subscription create \
  --name "$SUBSCRIPTION_NAME" \
  --system-topic-name "$EVENTGRID_TOPIC_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --endpoint-type webhook \
  --endpoint "$WEBHOOK_ENDPOINT" \
  --included-event-types "Microsoft.Storage.BlobCreated" \
  --subject-begins-with "/blobServices/default/containers/images-input/" \
  --event-delivery-schema eventgridschema \
  --output none

echo "✅ EventGrid subscription created."
echo ""

# ---------------------------------------------------------------------------
# 4. Health check
# ---------------------------------------------------------------------------
echo "🩺 Running health check..."
HEALTH_URL="${FUNCTION_APP_URL}/api/health"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$HEALTH_URL" || echo "000")

if [ "$HTTP_CODE" = "200" ]; then
    echo "   ✅ Health check passed (HTTP $HTTP_CODE)"
    curl -s "$HEALTH_URL" | head -20
elif [ "$HTTP_CODE" = "503" ]; then
    echo "   ⚠️  Health check returned degraded (HTTP $HTTP_CODE)"
    echo "   ffmpeg may not be mounted yet. RBAC propagation can take 1-2 minutes."
    curl -s "$HEALTH_URL" | head -20
else
    echo "   ⚠️  Health check returned HTTP $HTTP_CODE — the function host may still be starting."
    echo "   Try again in a minute: curl $HEALTH_URL"
fi

echo ""
echo "====================================="
echo "✅ Post-deployment setup complete!"
echo "====================================="
echo ""
echo "🚀 Test the sample:"
echo "   az storage blob upload \\"
echo "     --account-name $STORAGE_ACCOUNT \\"
echo "     --container-name images-input \\"
echo "     --name test-image.jpg \\"
echo "     --file <local-image-path> \\"
echo "     --auth-mode login"
echo ""
echo "   The blob trigger fires within a few seconds."
echo "   Check 'images-output' for the processed image."
echo ""
