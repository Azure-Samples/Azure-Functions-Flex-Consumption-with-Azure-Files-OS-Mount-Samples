# Decision: Flex Consumption Bicep Infrastructure Rewrite

**Author:** Kaylee (Cloud Dev)  
**Date:** 2026-03-06  
**Status:** Implemented

## Context

Our Bicep infrastructure modules did not correctly create a Flex Consumption function app. The critical issue was the **missing `functionAppConfig` property** — without it, the app deploys as a regular consumption plan, not Flex Consumption. Additionally, we used connection-string-based auth instead of managed identity, and set legacy app settings (`FUNCTIONS_WORKER_RUNTIME`, `FUNCTIONS_EXTENSION_VERSION`, `linuxFxVersion`) that don't apply to Flex Consumption.

Reference: [Azure Functions Flex Consumption Samples](https://github.com/Azure-Samples/azure-functions-flex-consumption-samples)

## Decision

Rewrote `function-app.bicep`, `storage-account.bicep`, and `monitoring.bicep` to match the official Flex Consumption reference patterns:

### function-app.bicep
- Added `functionAppConfig` with `deployment.storage` (blob container + SystemAssignedIdentity auth), `scaleAndConcurrency`, and `runtime` config
- Enabled system-assigned managed identity
- Replaced `AzureWebJobsStorage` connection string with identity-based `AzureWebJobsStorage__credential: 'managedidentity'` plus separate blob/queue/table URIs
- Removed `linuxFxVersion`, `FUNCTIONS_WORKER_RUNTIME`, `FUNCTIONS_EXTENSION_VERSION`, `AzureWebJobsFeatureFlags`, `APPINSIGHTS_INSTRUMENTATIONKEY`
- Added `APPLICATIONINSIGHTS_AUTHENTICATION_STRING: 'Authorization=AAD'`
- Outputs `principalId` for RBAC assignments

### storage-account.bicep
- Added `deploymentContainerName` param and blob container resource for Flex Consumption deployment packages
- Added queue and table service resources
- Changed outputs from `connectionString` → `primaryBlobEndpoint`, `blobServiceUri`, `queueServiceUri`, `tableServiceUri`
- Added `allowSharedKeyAccess` param (defaults true — needed for Azure Files mount account keys)

### monitoring.bicep
- Added `DisableLocalAuth: true` on App Insights
- Removed deprecated `instrumentationKey` output

### deploy-sample.sh
- Updated to pass new storage endpoint params
- Added RBAC role assignments (Storage Blob Data Owner, Storage Queue Data Contributor, Storage Table Data Contributor)

### Cleanup
- Deleted stale compiled JSON files for rewritten modules

## Rationale

1. `functionAppConfig` is the **only way** to create a true Flex Consumption app — it's not optional
2. Managed identity is the recommended auth pattern; shared key connection strings are deprecated for AzureWebJobsStorage
3. Deployment via blob container (not zip) is how Flex Consumption works
4. `linuxFxVersion` is a legacy property; Flex Consumption uses `functionAppConfig.runtime`

## Constraints Respected

- Kept modular structure (`infra/modules/`) — did not collapse into single main.bicep
- Did NOT modify `azure-files-mount.bicep` or `azure-files-mounts.bicep` (mount modules untouched)
- Did NOT import AVM modules — replicated correct properties in standalone resources
- `allowSharedKeyAccess` defaults to true because Azure Files mounts require account keys
- `setup-azure-files.sh` unchanged (still uses `az storage account keys list` which works)

## Impact

- **Inara:** Docs referencing infra should note managed identity and `functionAppConfig`. No more `FUNCTIONS_WORKER_RUNTIME` in Bicep examples.
- **Zoe:** All 67 tests pass. Bicep validation tests confirm compilation. New tests could verify `functionAppConfig` presence in the template.
- **Mal:** Ready for re-review. The infra now matches the official reference.
