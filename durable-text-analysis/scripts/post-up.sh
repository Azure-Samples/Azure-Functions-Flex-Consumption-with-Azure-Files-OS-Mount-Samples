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
# 2. Upload sample text files to Azure Files
# ---------------------------------------------------------------------------
echo "📝 Creating sample text files..."

cat > sample1.txt << 'EOF'
The Azure Functions Flex Consumption plan provides optimal cost-efficiency for
serverless workloads. It automatically scales based on demand and charges only
for the resources actually consumed during execution. This makes it ideal for
workloads with variable traffic patterns, batch processing jobs, and
event-driven architectures where requests can spike unpredictably.

Key benefits include per-second billing, automatic scaling to zero when idle,
and the ability to set maximum instance counts to control costs. The plan
supports multiple language runtimes including Python, Node.js, and .NET.
EOF

cat > sample2.txt << 'EOF'
Durable Functions enable stateful workflows in serverless environments without
requiring developers to manage state persistence manually. The framework
provides several application patterns including function chaining, fan-out and
fan-in, async HTTP APIs, monitoring, and human interaction.

The fan-out/fan-in pattern is particularly powerful for parallel processing
tasks. An orchestrator function can dispatch work to multiple activity functions
simultaneously, wait for all of them to complete, and then aggregate the
results. This is perfect for scenarios like batch processing, map-reduce
operations, and parallel data analysis across multiple files or data sources.
EOF

cat > sample3.txt << 'EOF'
Azure Files provides fully managed file shares in the cloud that are accessible
via the industry-standard SMB and NFS protocols. When mounted as OS-level
shares in Azure Functions Flex Consumption apps, they enable functions to read
and write files using standard filesystem APIs — no SDK or special client needed.

This is especially useful for scenarios that require shared state between
function instances, large binary tools like FFmpeg, or processing pipelines
that work with files on disk. The mount appears as a regular directory path
such as /mounts/data/ and supports concurrent reads from multiple instances.
EOF

echo "⬆️  Uploading sample files to Azure Files share..."
ACCOUNT_KEY=$(az storage account keys list \
  --resource-group "$RESOURCE_GROUP" \
  --account-name "$STORAGE_ACCOUNT" \
  --query "[0].value" -o tsv)

az storage file upload --account-name "$STORAGE_ACCOUNT" --share-name "$FILE_SHARE" --source sample1.txt --account-key "$ACCOUNT_KEY"
az storage file upload --account-name "$STORAGE_ACCOUNT" --share-name "$FILE_SHARE" --source sample2.txt --account-key "$ACCOUNT_KEY"
az storage file upload --account-name "$STORAGE_ACCOUNT" --share-name "$FILE_SHARE" --source sample3.txt --account-key "$ACCOUNT_KEY"

rm -f sample1.txt sample2.txt sample3.txt
echo "✅ Sample text files uploaded to Azure Files."
echo ""

# ---------------------------------------------------------------------------
# 3. Health check
# ---------------------------------------------------------------------------
echo "🩺 Running health check..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$FUNCTION_APP_URL" || echo "000")

if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "204" ]; then
    echo "   ✅ Function app is reachable (HTTP $HTTP_CODE)"
elif [ "$HTTP_CODE" = "401" ]; then
    echo "   ✅ Function app is reachable (HTTP $HTTP_CODE — auth required, which is expected)"
else
    echo "   ⚠️  Function app returned HTTP $HTTP_CODE — the host may still be starting."
    echo "   Try again in a minute: curl $FUNCTION_APP_URL"
fi

echo ""
echo "====================================="
echo "✅ Post-deployment setup complete!"
echo "====================================="
echo ""
echo "🚀 Test the sample:"
echo "   FUNC_KEY=\$(az functionapp keys list -n $FUNCTION_APP_NAME -g $RESOURCE_GROUP --query \"functionKeys.default\" -o tsv)"
echo "   curl -s -X POST \"${FUNCTION_APP_URL}/api/start-analysis?code=\${FUNC_KEY}\" | jq ."
echo ""
echo "   Then poll the statusQueryGetUri from the response to get the analysis results."
echo ""
