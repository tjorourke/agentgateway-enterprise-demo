# AgentRegistry: one agent, two runtimes

Drive the enterprise `arctl` CLI through the full agent lifecycle (scaffold, build, publish), then deploy a single published agent to **two** runtimes from the same catalog: **Solo Enterprise for kagent** in a local kind cluster, and **AWS Bedrock AgentCore**. The agent uses Anthropic Claude (`claude-haiku-4-5`) in both runtimes. The control plane is a local Docker `arctl daemon` that serves the catalog and a web UI on http://localhost:12121.

The agent is a text summarizer. It is wired to an MCP server (`textkit`, which exposes `word_count` and `extract_links` tools) and a skill (`summary-style`, the house format for summaries), so a request like "summarize this..." calls the tools and applies the format.

## What you get

- A kind cluster (`agentcore-demo`) running Solo Enterprise for kagent, with Keycloak as the OIDC issuer the controller validates against
- A standalone Docker `arctl daemon` acting as the catalog and control plane (catalog + UI on http://localhost:12121), using its embedded auto-auth IdP
- Three artifacts built with `arctl` and published to the catalog: `acme/textkit` (MCPServer), `summary-style` (Skill), and `summarizer` (Agent)
- The `summarizer` agent deployed onto a Kubernetes Runtime that lands it as kagent CRDs, reachable through the kagent A2A endpoint with OIDC enforced in front of it
- An optional add-on that registers a BedrockAgentCore Runtime and deploys the same published agent to AWS

## Prerequisites

Run the prereqs check, which installs missing CLIs on macOS (Homebrew) and validates credentials:

```bash
./scripts/quick.sh prereqs        # or: ./scripts/00-prereqs.sh
./scripts/00-prereqs.sh --check   # validate only, never install (CI-style)
```

It checks for `docker`, `kind`, `kubectl`, `helm`, `jq`, `gh`, `uv`, `curl`, `openssl`, `envsubst`, plus `aws` (AgentCore) and `gcloud` (Solo's public Helm charts), and installs/pins the enterprise `arctl`.

`arctl` is the **enterprise** build pinned to **`v2026.5.4`**. This is the latest line that still ships the local `daemon` subcommand; `v2026.6.x` dropped it in favour of a cluster-hosted server. It is installed from `https://storage.googleapis.com/agentregistry-enterprise/install.sh`. After install, add it to your shell:

```bash
export PATH=$HOME/.arctl/bin:$PATH
```

### Secrets

Two secrets are required:

- `ANTHROPIC_API_KEY` — the agent model in both runtimes
- `SOLO_LICENSE_KEY` — Solo Enterprise for kagent (set `KAGENT_ENT_LICENSE_KEY` instead if your kagent key is separate)

Pass them via environment, or point at a sourceable file:

```bash
export ANTHROPIC_API_KEY=sk-ant-...
export SOLO_LICENSE_KEY=...
# or:
SECRETS_FILE=/path/to/secrets.sh ./scripts/quick.sh up
```

The Solo public Helm charts (kagent enterprise) are pulled over OCI, so `gcloud` must be authenticated (`gcloud auth login`). The AgentCore add-on additionally needs a live AWS session.

## Quickstart

### 1. Bring up the local runtime

```bash
./scripts/quick.sh up
```

This runs the numbered steps end to end: create the kind cluster and a local OCI registry, deploy Keycloak and the `solo` realm, install Solo Enterprise for kagent (Anthropic as the default provider, OIDC wired to Keycloak), start the `arctl daemon`, scaffold-verify and build/publish the three artifacts, then register a Kubernetes Runtime and deploy the `summarizer` onto kagent.

The daemon starts standalone with `DOCKER_REPO=solo-public/agentregistry-enterprise` and `OIDC_AUTO_AUTH_ENABLED=true`, so no external Keycloak is needed for the catalog itself.

### 2. Talk to the agent

```bash
./scripts/ask.sh "summarize this: <paste text with a couple of https:// links>"
```

`ask.sh` mints `alice`'s Keycloak token (alice is in group `field-fte`, mapped to Admin so she may invoke agents) and calls the agent through the kagent A2A endpoint. Run with no prompt for a built-in sample. Open the kagent dashboard with:

```bash
./scripts/port-forward.sh          # http://localhost:8080
```

For a quick local proof before any cluster, `./scripts/test-local.sh` starts the `textkit` MCP on the host and drops you into an interactive chat with the agent via `arctl run`.

### 3. (Optional) Add the AgentCore runtime

This deploys the **same** published agent to AWS Bedrock AgentCore, alongside the kagent deployment. AgentCore cannot pull from the local registry, so the agent image is pushed to ECR, and AgentCore clones the agent source from a git repo at deploy time, so the branch must be pushed and reachable by AWS.

```bash
aws sso login --profile <your-profile>
AWS_PROFILE=<your-profile> ./scripts/quick.sh agentcore
```

This generates the AgentRegistry cross-account access CloudFormation template, deploys the stack, registers a `BedrockAgentCore` Runtime, builds and pushes the agent image to ECR (`linux/amd64`), and applies a Deployment binding the agent to that runtime. Watch it reconcile with `arctl get deployments`, then send a JSON-RPC `message/send` payload from the Bedrock AgentCore console.

### Guided walkthrough

The `demo.ipynb` notebook in this folder walks the same flow cell by cell, which is the guided way to run the demo. Run it with a bash-kernel Jupyter.

## Files

```
.
├── demo.ipynb              Guided, cell-by-cell walkthrough of the whole flow
├── scripts/
│   ├── quick.sh            Orchestrator: prereqs | up | agentcore | status | teardown
│   ├── 00-prereqs.sh       Install/validate CLIs, pin enterprise arctl, check secrets
│   ├── 01-cluster.sh       kind cluster + local OCI registry (:5001) + Gateway API CRDs
│   ├── 02-keycloak.sh      Keycloak + the shared `solo` realm (alice/bob/carol)
│   ├── 03-kagent.sh        Solo Enterprise for kagent (Anthropic provider, OIDC)
│   ├── 04-daemon.sh        Start the standalone arctl daemon (catalog + UI on :12121)
│   ├── 05-scaffold.sh      Verify the scaffolded artifact projects (shows the init commands)
│   ├── 06-build-publish.sh Build/push the MCP + agent images, publish all three artifacts
│   ├── 07-runtime-deploy.sh Register the Kubernetes Runtime, deploy the agent to kagent
│   ├── 08-agentcore.sh     Add-on: register a BedrockAgentCore Runtime, deploy to AWS
│   ├── ask.sh              Call the hosted agent through kagent A2A (mints a user token)
│   ├── test-local.sh       Run the agent + MCP locally with `arctl run`, no cluster
│   ├── port-forward.sh     kagent dashboard on http://localhost:8080
│   ├── cleanup.sh          Tear down everything, or AWS bits only
│   └── lib.sh              Shared helpers, version pins, and env defaults
├── artifacts/
│   ├── textkit/            MCPServer: word_count + extract_links (FastMCP, Python)
│   ├── summary-style/      Skill: the house format for summaries (SKILL.md)
│   └── summarizer/         Agent: ADK + Anthropic, wired to textkit + summary-style
├── yaml/                   Deployment, Runtime, and Keycloak manifests
└── kind/                   kind cluster config
```

## Teardown

```bash
./scripts/cleanup.sh             # everything: AWS AgentCore bits, then kind cluster,
                                 #   arctl daemon, registry container, and .agentcore/
./scripts/cleanup.sh agentcore   # AWS only (leaves the local cluster running)
```

`cleanup.sh` no-ops cleanly when there is no live AWS session, so the full teardown is safe even if you never deployed to AgentCore. `./scripts/quick.sh teardown` removes the local cluster, daemon, and registry only.
