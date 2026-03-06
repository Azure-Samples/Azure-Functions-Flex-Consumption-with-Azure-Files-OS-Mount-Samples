# Durable Text Analysis — Azure Functions Flex Consumption + Azure Files

This sample shows how to use **Durable Functions (Python v2)** on Azure Functions
**Flex Consumption** to orchestrate parallel text-file analysis. The text files
live on an **Azure Files share** that is OS-mounted into the function app at
`/mounts/data/`.

## What it does

1. An **HTTP-triggered starter** accepts a POST and kicks off a Durable
   Functions orchestration.
2. The **orchestrator** fans out to analyse each `.txt` file on the mount in
   parallel.
3. Per-file **activity functions** compute word count, line count, character
   frequency, and average word length.
4. An **aggregation activity** merges the results into a single summary
   returned as the orchestration output.

## Architecture

```
HTTP POST ──► Starter ──► Orchestrator ──┬──► Analyse File A ──┐
                                         ├──► Analyse File B ──┤
                                         └──► Analyse File C ──┘
                                                      │
                                                      ▼
                                              Aggregate Results
```

## Prerequisites

| Tool | Version |
|------|---------|
| Python | 3.10+ |
| Azure Functions Core Tools | 4.x |
| Azure CLI | 2.60+ |
| Azurite (for local dev) | latest |

## Quickstart — local development

```bash
# 1. Copy the example settings
cp local.settings.json.example local.settings.json

# 2. Install dependencies
pip install -r requirements.txt

# 3. Create a local mount directory and add sample text files
mkdir -p /tmp/mounts/data
echo "Hello world. This is a sample text file." > /tmp/mounts/data/sample1.txt
echo "Azure Functions Flex Consumption is great." > /tmp/mounts/data/sample2.txt

# 4. Update MOUNT_PATH in local.settings.json to point at the local dir
#    "MOUNT_PATH": "/tmp/mounts/data/"

# 5. Start Azurite (in a separate terminal)
azurite --silent

# 6. Start the function app
func start

# 7. Trigger the orchestration
curl -X POST http://localhost:7071/api/start-analysis
```

The response contains a `statusQueryGetUri` you can poll to watch progress.

## Deploy to Azure

Use the shared infrastructure in `../../infra/` to deploy:

```bash
# From the repo root
bash infra/scripts/deploy-sample.sh durable-text-analysis
```

Or deploy manually — see `../../infra/README.md` for details.

## Project structure

| File | Purpose |
|------|---------|
| `function_app.py` | App entry point; HTTP starter and status endpoint |
| `orchestrator.py` | Durable orchestrator (fan-out/fan-in) |
| `activities.py` | Activity functions (list, analyse, aggregate) |
| `host.json` | Durable Functions extension configuration |
| `requirements.txt` | Python dependencies |
| `local.settings.json.example` | Template for local settings (copy to `local.settings.json`) |

## Configuration

| Setting | Description | Default |
|---------|-------------|---------|
| `MOUNT_PATH` | Filesystem path where the Azure Files share is mounted | `/mounts/data/` |
| `AzureWebJobsStorage` | Storage connection for Durable Functions state | (required) |

## License

MIT — see [LICENSE](../../LICENSE) in the repository root.
