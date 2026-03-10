# Decision: Both samples use direct Microsoft.Web/sites (no AVM web/site)

**Date:** 2026-03-10
**Author:** Kaylee (Cloud Dev)
**Status:** Applied

## Context

AVM `br/public:avm/res/web/site:0.15.1` silently drops the `functionAppConfig` property, which is mandatory for Flex Consumption function apps. Without it, deployment storage auth fails with 403 and the app doesn't run as Flex Consumption.

## Decision

Both `durable-text-analysis/infra/app/function.bicep` and `ffmpeg-image-processing/infra/app/function.bicep` now use a direct `Microsoft.Web/sites@2024-04-01` resource instead of the AVM module. This ensures `functionAppConfig` is always present in the ARM output.

## Implications

- If AVM fixes this in a future version, we could migrate back — but there's no benefit since the direct resource is simple and correct.
- Any new samples in this repo should follow the same pattern (copy either function.bicep as a starting point).
- The two function.bicep files are now structurally identical — same params, same outputs, same resource shape.
