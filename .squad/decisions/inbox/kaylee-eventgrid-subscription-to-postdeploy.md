# Decision: Move EventGrid Subscription to Post-Deploy Script

**Author:** Kaylee (Cloud Dev)  
**Date:** 2026-03-07  
**Status:** Implemented

## Context

The `eventgrid.bicep` module used `listKeys()` to fetch the `blobs_extension` system key from the function app at provision time. But system keys only exist after function code is deployed and the host starts — creating a chicken-and-egg failure on first `azd up`.

Additionally, the webhook URL was wrong: it pointed to the EventGrid extension webhook (`/runtime/webhooks/EventGrid`) instead of the blob extension webhook (`/runtime/webhooks/blobs`) required by `@app.blob_trigger(source="EventGrid")`.

## Decision

- **Deleted** `infra/app/eventgrid.bicep` and removed its module call from `main.bicep`.
- **Kept** the EventGrid system topic in Bicep (it has no dependency on function code).
- **Moved** EventGrid subscription creation to `scripts/post-up.sh` (runs as `postdeploy` hook in `azure.yaml`).
- The script retrieves `blobs_extension` system key via `az functionapp keys list` with retry logic, then creates the subscription via `az eventgrid system-topic event-subscription create`.

## Consequences

- `azd up` now works end-to-end without manual intervention.
- EventGrid subscription uses the correct blob extension webhook endpoint.
- Slight increase in post-deploy script complexity, but eliminates a hard deployment failure.
