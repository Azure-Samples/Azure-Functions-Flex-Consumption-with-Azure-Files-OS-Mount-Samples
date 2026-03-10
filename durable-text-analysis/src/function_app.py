"""Azure Functions Flex Consumption — Durable Text Analysis Sample.

Demonstrates fan-out/fan-in orchestration over text files stored on an
Azure Files OS mount.  The HTTP-triggered starter kicks off a Durable
Functions orchestration that:
  1. Lists text files on the mount.
  2. Fans out to analyse each file in parallel.
  3. Aggregates the per-file results into a single summary.
"""

import azure.functions as func
import azure.durable_functions as df
import json

# The single app object used by the Azure Functions v2 programming model.
app = func.FunctionApp(http_auth_level=func.AuthLevel.FUNCTION)

# Register the Durable Functions blueprint so the orchestrator and
# activities in the companion modules are discoverable by the host.
from orchestrator import bp as orchestrator_bp  # noqa: E402
from activities import bp as activities_bp       # noqa: E402

app.register_functions(orchestrator_bp)
app.register_functions(activities_bp)


# ---------------------------------------------------------------------------
# HTTP starter — kicks off the orchestration and returns a status URL.
# ---------------------------------------------------------------------------
@app.route(route="start-analysis", methods=["POST"])
@app.durable_client_input(client_name="client")
async def start_analysis(req: func.HttpRequest, client) -> func.HttpResponse:
    """Start a new text-analysis orchestration.

    Optionally accepts a JSON body with ``{"mount_path": "/mounts/data/"}``
    to override the default mount location.
    """
    try:
        body = req.get_json()
    except ValueError:
        body = {}

    # Allow callers to override the mount path; fall back to the app setting.
    import os
    mount_path = body.get("mount_path", os.environ.get("MOUNT_PATH", "/mounts/data/"))

    instance_id = await client.start_new(
        "text_analysis_orchestrator",
        client_input={"mount_path": mount_path},
    )

    response = client.create_check_status_response(req, instance_id)
    return response


# ---------------------------------------------------------------------------
# HTTP endpoint to query the status of a running orchestration.
# ---------------------------------------------------------------------------
@app.route(route="status/{instance_id}", methods=["GET"])
@app.durable_client_input(client_name="client")
async def get_status(req: func.HttpRequest, client) -> func.HttpResponse:
    """Return the current status of an orchestration instance."""
    instance_id = req.route_params.get("instance_id", "")
    if not instance_id:
        return func.HttpResponse("Missing instance_id", status_code=400)

    status = await client.get_status(instance_id)
    if status is None:
        return func.HttpResponse("Instance not found", status_code=404)

    return func.HttpResponse(
        json.dumps(
            {
                "instanceId": status.instance_id,
                "runtimeStatus": status.runtime_status.value
                if status.runtime_status
                else None,
                "output": status.output,
            }
        ),
        mimetype="application/json",
    )
