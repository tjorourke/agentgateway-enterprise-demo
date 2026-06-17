# AgentRegistry: one agent, two runtimes — engineer setup

A developer-persona demo: drive `arctl` through the agent lifecycle (scaffold → build → publish), then deploy **one** agent to **two** runtimes — Solo Enterprise for **kagent** (local kind) and **AWS Bedrock AgentCore** — by changing one line, the Deployment's `runtimeRef`. The demo runs in **`demo.ipynb`**; this is the one-time setup you do first.

**Layout:** only `demo.ipynb` (and the runtime-scaffolded `agentdemo/`) sit at the top — everything else is here in `setup/`, so you can't accidentally open `.env.local` in front of a customer. Run the commands below from the demo folder (the parent of `setup/`).

## Prerequisites
- Docker running; an **Anthropic API key** and a **Solo Enterprise for kagent license**
- `gcloud auth login` (Solo Helm charts pull over OCI)
- *AgentCore add-on only:* an AWS account with an SSO profile in `~/.aws/config`

Everything else (kind, kubectl, helm, jq, gh, uv, aws, `arctl`) is installed by step 2.

## Run it

```bash
# 1. Capture credentials (prompts for each; secrets hidden; AWS profile picker)
./setup/scripts/setup-env.sh

# 2. Bring up the platform: kind + Keycloak + kagent + arctl daemon (~15 min first run)
./setup/scripts/setup.sh

# 3. Start the notebook's Jupyter server (so Cursor can run the Bash cells)
./setup/scripts/notebook-server.sh
```

Then open **`demo.ipynb`** and run it top to bottom.

### Connecting the kernel in Cursor / VS Code
Cursor's built-in Jupyter can't reliably launch a fresh Bash kernel, so connect to the server from step 3:

> Select Kernel → **Existing Jupyter Server…** → paste `http://127.0.0.1:8889/?token=solodemo` → pick **Bash**.

## AgentCore add-on
To also deploy to AWS (the notebook's second half):
1. In step 1, pick your **AWS profile** from the menu.
2. AgentCore clones the agent source, so it needs a git repo. `setup-env.sh` offers to create one with `gh` (or run `./setup/scripts/create-agent-repo.sh`). Private repos clone via your `gh` token automatically; public is simplest.

On kagent the agent uses your Anthropic key; on AgentCore it runs native Bedrock Claude via the AWS role (no key).

## Reset / teardown

```bash
./setup/scripts/reset.sh      # back to start: clears agentdemo/, deployments, AWS bits; platform stays up
./setup/scripts/cleanup.sh    # full teardown (cluster, daemon, registry, AWS)
```

Run `reset.sh` between demo runs; `cleanup.sh` when you're done with the cluster.
