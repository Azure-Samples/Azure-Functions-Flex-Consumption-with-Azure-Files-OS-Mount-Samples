"""Durable Functions orchestrator — fan-out/fan-in text analysis.

The orchestrator reads a list of text files from the Azure Files OS mount,
then fans out to analyse each file in parallel.  Once all activity tasks
complete, it calls an aggregation activity to merge per-file results into
a single summary.
"""

import azure.functions as func
import azure.durable_functions as df

bp = df.Blueprint()


@bp.orchestration_trigger(context_name="context")
def text_analysis_orchestrator(context: df.DurableOrchestrationContext):
    """Fan-out/fan-in orchestrator for text file analysis."""

    input_data = context.get_input()
    mount_path = input_data.get("mount_path", "/mounts/data/")

    # Step 1 — List all text files on the mount.
    file_list: list[str] = yield context.call_activity(
        "list_text_files",
        {"mount_path": mount_path},
    )

    if not file_list:
        return {"error": "No text files found", "mount_path": mount_path}

    # Step 2 — Fan out: analyse each file in parallel.
    #
    # Durable Functions replays the orchestrator deterministically, so
    # context.task_all is safe even for large fan-outs.
    analysis_tasks = [
        context.call_activity(
            "analyse_text_file",
            {"file_path": file_path},
        )
        for file_path in file_list
    ]
    per_file_results: list[dict] = yield context.task_all(analysis_tasks)

    # Step 3 — Aggregate all per-file results into a summary.
    summary: dict = yield context.call_activity(
        "aggregate_results",
        {"results": per_file_results},
    )

    return summary
