"""Azure Functions Flex Consumption — ffmpeg Image Processing Sample.

Demonstrates using a large binary (ffmpeg) stored on an Azure Files OS mount
to process images.  A Blob-triggered function detects new image uploads in a
storage container, then shells out to the mounted ffmpeg binary to resize and
convert the image.  Processed results are written back to a separate container.

Key concept: Flex Consumption OS mounts let you place large tools like ffmpeg
on a shared file system instead of bundling them in the deployment package.
"""

import json
import logging
import os

import azure.functions as func

from process_image import process_with_ffmpeg

app = func.FunctionApp()
logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Blob-triggered function — fires when a new image lands in the input
# container.  Uses the storage connection defined in app settings.
# ---------------------------------------------------------------------------

# NOTE: The Blob trigger on Flex Consumption uses an event-based trigger
# (Event Grid) by default, which gives near-instant response.  Make sure
# the "source" property is set to "EventGrid" in the binding.
@app.blob_trigger(
    arg_name="inputblob",
    path="images-input/{name}",
    connection="AzureWebJobsStorage",
    source="EventGrid",
)
@app.blob_output(
    arg_name="$return",
    path="images-output/{name}",
    connection="AzureWebJobsStorage",
)
def process_image_blob(inputblob: func.InputStream) -> bytes:
    """Process an uploaded image with ffmpeg and write the result to the
    output container.

    The function:
      1. Reads the image bytes from the blob trigger.
      2. Calls ffmpeg (on the OS mount) to resize and convert the image.
      3. Returns the processed bytes, which the output binding writes to
         ``images-output/{name}``.
    """
    blob_name = inputblob.name or "unknown"
    blob_size = inputblob.length or 0
    logger.info("Processing blob: %s (%d bytes)", blob_name, blob_size)

    # Read the entire input image into memory.
    image_bytes = inputblob.read()
    if not image_bytes:
        logger.warning("Empty blob received: %s", blob_name)
        return b""

    # Resolve ffmpeg binary path from app settings.
    # On Flex Consumption the binary lives on the OS-mounted Azure Files share.
    ffmpeg_path = os.environ.get("FFMPEG_PATH", "/mounts/tools/ffmpeg")
    output_width = int(os.environ.get("OUTPUT_WIDTH", "800"))
    output_format = os.environ.get("OUTPUT_FORMAT", "png")

    try:
        result_bytes = process_with_ffmpeg(
            image_bytes,
            ffmpeg_path=ffmpeg_path,
            output_width=output_width,
            output_format=output_format,
        )
        logger.info(
            "Processed %s → %d bytes (%s, width=%d)",
            blob_name,
            len(result_bytes),
            output_format,
            output_width,
        )
        return result_bytes
    except Exception:
        logger.exception("Failed to process %s", blob_name)
        raise


# ---------------------------------------------------------------------------
# HTTP health-check endpoint — useful for smoke-testing the deployment and
# verifying that the ffmpeg binary is accessible on the mount.
# ---------------------------------------------------------------------------
@app.route(route="health", methods=["GET"], auth_level=func.AuthLevel.ANONYMOUS)
def health_check(req: func.HttpRequest) -> func.HttpResponse:
    """Return 200 if the function app is running and ffmpeg is reachable."""
    ffmpeg_path = os.environ.get("FFMPEG_PATH", "/mounts/tools/ffmpeg")
    ffmpeg_exists = os.path.isfile(ffmpeg_path) and os.access(ffmpeg_path, os.X_OK)

    status = {
        "status": "healthy" if ffmpeg_exists else "degraded",
        "ffmpeg_path": ffmpeg_path,
        "ffmpeg_available": ffmpeg_exists,
    }
    code = 200 if ffmpeg_exists else 503
    return func.HttpResponse(json.dumps(status), mimetype="application/json", status_code=code)
