# Decision: Replace AVM web/site module with direct resource for Flex Consumption

**Author:** Kaylee (Cloud Dev)
**Date:** 2026-03-10
**Status:** Implemented

## Context

The AVM module `br/public:avm/res/web/site:0.15.1` accepts a `functionAppConfig` parameter but does NOT propagate it to the deployed `Microsoft.Web/sites` resource. For Flex Consumption function apps, `functionAppConfig` is mandatory — it configures deployment storage, runtime, and scaling. Without it, the app deploys as a regular function app and all deployment attempts fail with 403 (storage inaccessible).

Additionally, the AVM module `br/public:avm/res/storage/storage-account:0.8.3` defaults to `publicNetworkAccess: None` with `defaultAction: Deny`, which blocks function app access to its own storage.

## Decision

1. **Use direct `Microsoft.Web/sites@2024-04-01` resource** instead of AVM `web/site` module for all Flex Consumption function apps. This gives full control over `functionAppConfig`.
2. **Explicitly set storage network access** to `publicNetworkAccess: 'Enabled'` and `networkAcls: { defaultAction: 'Allow', bypass: 'AzureServices' }` when using the AVM storage module.
3. **Apply same fix to ffmpeg-image-processing** sample for consistency (if it's still using the AVM web/site module).

## Impact

Both sample infra templates should use direct resources for function apps. AVM modules can still be used for simpler resources (storage, identity, monitoring, plan).
