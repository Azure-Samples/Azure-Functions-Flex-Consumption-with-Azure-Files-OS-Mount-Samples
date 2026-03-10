"""Azure Functions Flex Consumption - ffmpeg Image Processing Sample.

Uses an EventGrid trigger to receive blob-created notifications, downloads
the source blob via the Azure SDK, processes it with ffmpeg (mounted via
Azure Files), and uploads the result to an output container.
"""

import logging
import os
from urllib.parse import urlparse

import azure.functions as func
from azure.identity import ManagedIdentityCredential
from azure.storage.blob import BlobServiceClient

from process_image import process_with_ffmpeg

app = func.FunctionApp()
logger = logging.getLogger(__name__)

_blob_service_client = None


def _get_blob_service_client() -> BlobServiceClient:
    """Create or return a cached BlobServiceClient using managed identity."""
    global _blob_service_client
    if _blob_service_client is None:
        account_name = os.environ.get("AzureWebJobsStorage__accountName", "")
        client_id = os.environ.get("AzureWebJobsStorage__clientId", None)
        credential = ManagedIdentityCredential(client_id=client_id)
        _blob_service_client = BlobServiceClient(
            account_url=f"https://{account_name}.blob.core.windows.net",
            credential=credential,
        )
    return _blob_service_client


@app.event_grid_trigger(arg_name="event")
def process_image_blob(event: func.EventGridEvent) -> None:
    """Process an uploaded image when EventGrid fires a BlobCreated event."""
    logger.info("EventGrid event: type=%s subject=%s", event.event_type, event.subject)

    if event.event_type != "Microsoft.Storage.BlobCreated":
        logger.info("Ignoring event type: %s", event.event_type)
        return

    data = event.get_json()
    blob_url = data.get("url", "")

    # Parse the blob URL to extract container and blob name
    parsed = urlparse(blob_url)
    path_parts = parsed.path.lstrip("/").split("/", 1)
    if len(path_parts) != 2:
        logger.error("Could not parse blob path from URL: %s", blob_url)
        return

    container_name, blob_name = path_parts

    input_container = os.environ.get("INPUT_CONTAINER", "images-input")
    if container_name != input_container:
        logger.info("Ignoring blob in container %s (expected %s)", container_name, input_container)
        return

    ffmpeg_path = os.environ.get("FFMPEG_PATH", "/mounts/tools/ffmpeg")
    output_width = int(os.environ.get("OUTPUT_WIDTH", "800"))
    output_format = os.environ.get("OUTPUT_FORMAT", "png")
    output_container = os.environ.get("OUTPUT_CONTAINER", "images-output")

    client = _get_blob_service_client()

    # Download the input blob
    input_blob = client.get_blob_client(container=container_name, blob=blob_name)
    image_bytes = input_blob.download_blob().readall()
    logger.info("Downloaded %d bytes from %s/%s", len(image_bytes), container_name, blob_name)

    if not image_bytes:
        logger.warning("Empty blob: %s/%s", container_name, blob_name)
        return

    # Process with ffmpeg
    result_bytes = process_with_ffmpeg(
        image_bytes,
        ffmpeg_path=ffmpeg_path,
        output_width=output_width,
        output_format=output_format,
    )

    # Upload to output container
    output_blob = client.get_blob_client(container=output_container, blob=blob_name)
    output_blob.upload_blob(result_bytes, overwrite=True)
    logger.info("Wrote %d bytes to %s/%s", len(result_bytes), output_container, blob_name)


@app.route(route="health", methods=["GET"], auth_level=func.AuthLevel.ANONYMOUS)
def health_check(req: func.HttpRequest) -> func.HttpResponse:
    """Return 200 if the function app is running and ffmpeg is reachable."""
    import json

    ffmpeg_path = os.environ.get("FFMPEG_PATH", "/mounts/tools/ffmpeg")
    ffmpeg_exists = os.path.isfile(ffmpeg_path) and os.access(ffmpeg_path, os.X_OK)

    status = {
        "status": "healthy" if ffmpeg_exists else "degraded",
        "ffmpeg_path": ffmpeg_path,
        "ffmpeg_available": ffmpeg_exists,
    }
    code = 200 if ffmpeg_exists else 503
    return func.HttpResponse(json.dumps(status, indent=2), mimetype="application/json", status_code=code)
