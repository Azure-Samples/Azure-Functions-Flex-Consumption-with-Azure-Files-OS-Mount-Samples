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

# Download ffmpeg static build
echo "⬇️  Downloading ffmpeg static build..."
FFMPEG_URL="https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz"
FFMPEG_ARCHIVE="ffmpeg-static.tar.xz"

curl -L -o "$FFMPEG_ARCHIVE" "$FFMPEG_URL"

# Extract ffmpeg binary
echo "📦 Extracting ffmpeg binary..."
tar -xf "$FFMPEG_ARCHIVE" --strip-components=1 "*/ffmpeg"

# Upload ffmpeg to Azure Files
echo "⬆️  Uploading ffmpeg to Azure Files share..."
az storage file upload \
  --account-name "$STORAGE_ACCOUNT" \
  --share-name "$FILE_SHARE" \
  --source ./ffmpeg \
  --path ffmpeg \
  --auth-mode login

# Clean up local files
rm -f "$FFMPEG_ARCHIVE" ffmpeg

echo ""
echo "✅ Post-deployment setup complete!"
echo ""
echo "🚀 Next steps:"
echo "   1. Upload an image to the 'images-input' container:"
echo "      az storage blob upload \\"
echo "        --account-name $STORAGE_ACCOUNT \\"
echo "        --container-name images-input \\"
echo "        --name test-image.jpg \\"
echo "        --file <local-image-path> \\"
echo "        --auth-mode login"
echo ""
echo "   2. The function will automatically process the image via EventGrid"
echo ""
echo "   3. Check the 'images-output' container for processed images"
echo ""
