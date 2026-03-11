# Decision: Azure Files SMB Mount Authentication Mechanism

**Date:** 2026-03-12
**Author:** Kaylee (Cloud Dev)
**Status:** Decided (verified against infrastructure)

## Context

The tutorial (`docs/tutorial-shared-file-access.md`) and both quickstart docs claimed that Azure Files OS mounts on Flex Consumption use **managed identity** with the `Storage File Data SMB Share Contributor` RBAC role. Thiago flagged this as incorrect.

## Investigation

Examined both sample `mounts.bicep` files (`durable-text-analysis/infra/app/mounts.bicep` and `ffmpeg-image-processing/infra/app/mounts.bicep`). Both use identical auth:

```bicep
var storageAccountKey = storage.listKeys().keys[0].value

// ...
accessKey: storageAccountKey
```

The `rbac.bicep` files only assign Blob, Queue, and Table data-plane roles — no `Storage File Data SMB Share *` roles anywhere.

## Decision

**Azure Files OS mounts on Azure Functions (Flex Consumption) use storage account access keys.** Managed identity is NOT supported for SMB mount authentication on Azure Functions.

The two auth models in our samples are:
1. **OS mounts (SMB protocol)** → Storage account access key (configured in `azureStorageAccounts` site config)
2. **AzureWebJobsStorage (Blob/Queue/Table REST)** → Managed identity + RBAC (configured in `function.bicep` app settings)

The `Storage File Data SMB Share Contributor` RBAC role is designed for Azure AD–based SMB access scenarios (e.g., domain-joined VMs), which Azure Functions does not support for OS mounts.

## Changes Made

- `docs/tutorial-shared-file-access.md` — 4 corrections (security section, multi-app guidance, best practices rewrite, architecture diagram)
- `docs/quickstart-durable-text-analysis.md` — Troubleshooting section corrected
- `docs/quickstart-ffmpeg-processing.md` — Troubleshooting section corrected

## Follow-Up Needed

The concept docs also contain the same incorrect managed identity claims for SMB mounts:
- `docs/concepts/flex-consumption-os-mounts.md` — Lines 66-85 (mounting process), lines 147-152 (architecture diagram), line 239 (NOTE callout)
- `docs/concepts/azure-files-with-functions.md` — Step 4 RBAC section, Bicep example with `accessKey: ''`, troubleshooting, key takeaway

These are in Inara's domain but need the same factual corrections. Flagging for team.
