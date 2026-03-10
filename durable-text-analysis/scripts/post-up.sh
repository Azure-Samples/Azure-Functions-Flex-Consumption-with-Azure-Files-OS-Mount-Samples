#!/bin/bash
set -e

echo ""
echo "====================================="
echo "Post-deployment setup"
echo "====================================="
echo ""

# Get environment variables from azd
RESOURCE_GROUP=$(azd env get-value AZURE_RESOURCE_GROUP)
STORAGE_ACCOUNT=$(azd env get-value AZURE_STORAGE_ACCOUNT_NAME)
FILE_SHARE=$(azd env get-value AZURE_STORAGE_FILE_SHARE_NAME)

if [ -z "$RESOURCE_GROUP" ] || [ -z "$STORAGE_ACCOUNT" ] || [ -z "$FILE_SHARE" ]; then
    echo "❌ Error: Required environment variables not set"
    exit 1
fi

echo "📦 Resource Group: $RESOURCE_GROUP"
echo "💾 Storage Account: $STORAGE_ACCOUNT"
echo "📁 File Share: $FILE_SHARE"
echo ""

# Create sample text files in the Azure Files share
echo "📝 Creating sample text files in Azure Files share..."

# Create sample files
cat > sample1.txt << 'EOF'
The Azure Functions Flex Consumption plan provides optimal cost-efficiency.
It automatically scales based on demand and charges only for resources used.
This makes it ideal for workloads with variable traffic patterns.
EOF

cat > sample2.txt << 'EOF'
Durable Functions enable stateful workflows in serverless environments.
The fan-out/fan-in pattern is perfect for parallel processing tasks.
Azure Files integration provides persistent storage for function apps.
EOF

cat > sample3.txt << 'EOF'
The Python programming model for Azure Functions is intuitive and powerful.
It supports both HTTP triggers and durable orchestrations.
Azure Verified Modules simplify infrastructure deployment.
EOF

# Upload files to Azure Files
echo "⬆️  Uploading sample files..."
az storage file upload --account-name "$STORAGE_ACCOUNT" --share-name "$FILE_SHARE" --source sample1.txt --path sample1.txt --auth-mode key
az storage file upload --account-name "$STORAGE_ACCOUNT" --share-name "$FILE_SHARE" --source sample2.txt --path sample2.txt --auth-mode key
az storage file upload --account-name "$STORAGE_ACCOUNT" --share-name "$FILE_SHARE" --source sample3.txt --path sample3.txt --auth-mode key

# Clean up local files
rm sample1.txt sample2.txt sample3.txt

echo ""
echo "✅ Post-deployment setup complete!"
echo ""
echo "🚀 Next steps:"
echo "   1. Test the function app:"
echo "      FUNC_URL=\$(azd env get-value AZURE_FUNCTION_APP_URL)"
echo "      curl -X POST \"\${FUNC_URL}/api/start-analysis?code=<function-key>\""
echo ""
echo "   2. Check the orchestration status using the statusQueryGetUri from the response"
echo ""
