"""Azure Functions Flex Consumption - ffmpeg Image Processing Sample.

Uses a blob trigger with EventGrid source to automatically process images
uploaded to Azure Blob Storage. The ffmpeg binary is mounted via an Azure
Files OS share on Flex Consumption.
"""

import logging
import os

import azure.functions as func

from process_image import process_with_ffmpeg

app = func.FunctionApp()
logger = logging.getLogger(__name__)


@app.blob_trigger(
    arg_name="input_blob",
    path="images-input/{name}",
    connection="AzureWebJobsStorage",
    source="EventGrid",
    data_type=func.DataType.BINARY,
)
@app.blob_output(
    arg_name="$return",
    path="images-output/{name}",
    connection="AzureWebJobsStorage",
    data_type=func.DataType.BINARY,
)
def process_image_blob(input_blob: func.InputStream) -> bytes:
    """Process an uploaded image by resizing it with ffmpeg."""
    blob_name = input_blob.name
    logger.info("Processing blob: %s (%d bytes)", blob_name, input_blob.length)

    image_bytes = input_blob.read()
    if not image_bytes:
        logger.warning("Empty blob: %s", blob_name)
        return None

    ffmpeg_path = os.environ.get("FFMPEG_PATH", "/mounts/tools/ffmpeg")
    output_width = int(os.environ.get("OUTPUT_WIDTH", "800"))
    output_format = os.environ.get("OUTPUT_FORMAT", "png")

    result_bytes = process_with_ffmpeg(
        image_bytes,
        ffmpeg_path=ffmpeg_path,
        output_width=output_width,
        output_format=output_format,
    )

    logger.info("Processed %s: %d → %d bytes", blob_name, len(image_bytes), len(result_bytes))
    return result_bytes


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
