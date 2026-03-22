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

if (-not $RESOURCE_GROUP -or -not $STORAGE_ACCOUNT -or -not $FILE_SHARE -or -not $FUNCTION_APP_NAME -or -not $FUNCTION_APP_URL) {
    Write-Error "Required environment variables not set. Run 'azd provision' and 'azd deploy' first."
    exit 1
}

Write-Host "Resource Group:  $RESOURCE_GROUP"
Write-Host "Storage Account: $STORAGE_ACCOUNT"
Write-Host "File Share:      $FILE_SHARE"
Write-Host "Function App:    $FUNCTION_APP_NAME"
Write-Host "Function URL:    $FUNCTION_APP_URL"
Write-Host ""

# ---------------------------------------------------------------------------
# 2. Upload sample text files to Azure Files
# ---------------------------------------------------------------------------
Write-Host "Creating sample text files..."

$sample1 = @"
The Azure Functions Flex Consumption plan provides optimal cost-efficiency for
serverless workloads. It automatically scales based on demand and charges only
for the resources actually consumed during execution. This makes it ideal for
workloads with variable traffic patterns, batch processing jobs, and
event-driven architectures where requests can spike unpredictably.

Key benefits include per-second billing, automatic scaling to zero when idle,
and the ability to set maximum instance counts to control costs. The plan
supports multiple language runtimes including Python, Node.js, and .NET.
"@

$sample2 = @"
Durable Functions enable stateful workflows in serverless environments without
requiring developers to manage state persistence manually. The framework
provides several application patterns including function chaining, fan-out and
fan-in, async HTTP APIs, monitoring, and human interaction.

The fan-out/fan-in pattern is particularly powerful for parallel processing
tasks. An orchestrator function can dispatch work to multiple activity functions
simultaneously, wait for all of them to complete, and then aggregate the
results. This is perfect for scenarios like batch processing, map-reduce
operations, and parallel data analysis across multiple files or data sources.
"@

$sample3 = @"
Azure Files provides fully managed file shares in the cloud that are accessible
via the industry-standard SMB and NFS protocols. When mounted as OS-level
shares in Azure Functions Flex Consumption apps, they enable functions to read
and write files using standard filesystem APIs - no SDK or special client needed.

This is especially useful for scenarios that require shared state between
function instances, large binary tools like FFmpeg, or processing pipelines
that work with files on disk. The mount appears as a regular directory path
such as /mounts/data/ and supports concurrent reads from multiple instances.
"@

$sample1 | Set-Content -Path "sample1.txt" -NoNewline
$sample2 | Set-Content -Path "sample2.txt" -NoNewline
$sample3 | Set-Content -Path "sample3.txt" -NoNewline

Write-Host "Uploading sample files to Azure Files share..."
$ACCOUNT_KEY = (az storage account keys list --resource-group $RESOURCE_GROUP --account-name $STORAGE_ACCOUNT --query "[0].value" -o tsv)
az storage file upload --account-name $STORAGE_ACCOUNT --share-name $FILE_SHARE --source sample1.txt --account-key $ACCOUNT_KEY
az storage file upload --account-name $STORAGE_ACCOUNT --share-name $FILE_SHARE --source sample2.txt --account-key $ACCOUNT_KEY
az storage file upload --account-name $STORAGE_ACCOUNT --share-name $FILE_SHARE --source sample3.txt --account-key $ACCOUNT_KEY

Remove-Item -Force -ErrorAction SilentlyContinue sample1.txt, sample2.txt, sample3.txt
Write-Host "Sample text files uploaded to Azure Files."
Write-Host ""

# ---------------------------------------------------------------------------
# 3. Health check
# ---------------------------------------------------------------------------
Write-Host "Running health check..."
try {
    $response = Invoke-WebRequest -Uri $FUNCTION_APP_URL -UseBasicParsing -ErrorAction Stop
    $HTTP_CODE = $response.StatusCode
} catch {
    $HTTP_CODE = $_.Exception.Response.StatusCode.value__
    if (-not $HTTP_CODE) { $HTTP_CODE = 0 }
}

if ($HTTP_CODE -eq 200 -or $HTTP_CODE -eq 204) {
    Write-Host "  Function app is reachable (HTTP $HTTP_CODE)"
} elseif ($HTTP_CODE -eq 401) {
    Write-Host "  Function app is reachable (HTTP $HTTP_CODE - auth required, which is expected)"
} else {
    Write-Host "  Function app returned HTTP $HTTP_CODE - the host may still be starting."
    Write-Host "  Try again in a minute: Invoke-RestMethod $FUNCTION_APP_URL"
}

Write-Host ""
Write-Host "====================================="
Write-Host "Post-deployment setup complete!"
Write-Host "====================================="
Write-Host ""
Write-Host "Test the sample:"
Write-Host "  `$FUNC_KEY = (az functionapp keys list -n $FUNCTION_APP_NAME -g $RESOURCE_GROUP --query `"functionKeys.default`" -o tsv)"
Write-Host "  Invoke-RestMethod -Method Post -Uri `"$FUNCTION_APP_URL/api/start-analysis?code=`$FUNC_KEY`""
Write-Host ""
Write-Host "  Then poll the statusQueryGetUri from the response to get the analysis results."
Write-Host ""
