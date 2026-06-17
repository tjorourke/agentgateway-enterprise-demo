# AgentRegistry: one agent, two runtimes — engineer runbook

A demo for a **developer** persona: drive the enterprise `arctl` CLI through the full agent lifecycle (scaffold → build → publish), then deploy **one** published agent to **two** runtimes from the same catalog — **Solo Enterprise for kagent** in a local kind cluster, and **AWS Bedrock AgentCore** — by changing one line, the Deployment's `runtimeRef`. On kagent the agent runs Anthropic Claude (`claude-haiku-4-5`); on AgentCore it runs native Bedrock Claude via the AWS role (no API key). The agent is a text summarizer wired to an MCP tool server (`textkit`: `word_count`, `extract_links`) and a skill (`summary-style`, the house format).

The work splits in two:

- **Setup (you, the engineer — before the demo):** install tooling, capture credentials, bring up the platform. Scripted; never shown to the audience.
- **The demo (the notebook `demo.ipynb`):** starts at the agent lifecycle and runs each `arctl` command live. This is what the audience watches.

---

## Part 1 — Setup (do this before the demo)

### Step 0 — Prerequisites you provide

- **Docker** running (Desktop or engine with `buildx`).
- An **Anthropic API key** and a **Solo Enterprise for kagent license**.
- **gcloud** authenticated (`gcloud auth login`) — Solo's public Helm charts are pulled over OCI.
- For the AgentCore add-on only: an **AWS account** with an SSO profile in `~/.aws/config`, and access to push this branch to a **public** git repo (AgentCore clones the agent source at deploy time).

Everything else (kind, kubectl, helm, jq, gh, uv, aws CLI, and the enterprise `arctl`) is installed/validated for you in Step 2.

### Step 1 — Capture credentials

```bash
./scripts/setup-env.sh
```

Prompts for each value and writes a gitignored `.env.local` (chmod 600). Secrets are read hidden; existing values are kept on Enter. For AWS it shows a **numbered picker of your profiles** (from `aws configure list-profiles`) — pick a number, or `0`/blank to skip AgentCore.

It captures:

| Variable | For | Notes |
|----------|-----|-------|
| `ANTHROPIC_API_KEY` | kagent path | the agent's model on kagent |
| `SOLO_LICENSE_KEY` | kagent path | Solo Enterprise for kagent |
| `AWS_PROFILE` | AgentCore add-on | your SSO profile; blank to skip |
| `AWS_REGION` | AgentCore add-on | defaults to `us-east-1` |

> Already keep Solo creds in an env file? Add `export SECRETS_FILE=/path/to/it` to `.env.local` — the scripts and notebook source it too.

### Step 2 — Bring up the platform (~15 min, first run)

```bash
./scripts/setup.sh
```

Installs/validates the CLIs (pins enterprise `arctl` to **v2026.5.4** — the latest line that still ships the local `daemon`; v2026.6.x moved the server onto a cluster), then stands up everything the agent runs on:

1. **kind cluster** `agentcore-demo` + a local OCI registry on `localhost:5001` + Gateway API CRDs
2. **Keycloak** with the `solo` realm (the OIDC issuer the kagent controller validates against)
3. **Solo Enterprise for kagent** (Anthropic provider, OIDC wired to Keycloak)
4. the **`arctl daemon`** — the catalog + control plane (web UI on http://localhost:12121), standalone with its embedded auth

Idempotent — re-run if a step fails. When it finishes, the platform is live and the demo is ready.

### Step 3 — (AgentCore add-on only) make the agent source reachable

AgentCore clones the agent source from git at deploy time, so push this branch somewhere AWS can reach (public):

```bash
git push <your-fork-remote> <this-branch>
```

Then set these in `.env.local` so the notebook points AgentCore at it:

```sh
export AGENT_GIT_URL="https://github.com/<you>/agentgateway-enterprise-demo.git"
export AGENT_GIT_BRANCH="<this-branch>"
export AGENT_GIT_SUBFOLDER="agentregistry-agentcore-kind/artifacts/summarizer"
```

---

## Part 2 — The demo (`demo.ipynb`)

Open `demo.ipynb` in a **bash-kernel** Jupyter ([`bash_kernel`](https://github.com/takluyver/bash_kernel)) and run top to bottom. It starts with a one-cell **Connect** (loads `.env.local`, mints the arctl token), then:

1. **Scaffold** the MCP server, skill, and agent with `arctl init`
2. **Prove locally** with `arctl run` (interactive; in a terminal)
3. **Build + publish** the images to the catalog (`arctl build --push`, `arctl apply`)
4. **Register** a Kubernetes **Runtime** pointing at the cluster
5. **Deploy** the agent onto kagent (runtime #1)
6. **Talk to it** through the OIDC-protected kagent A2A endpoint (`./scripts/ask.sh`)

Then the AgentCore add-on (one-line `runtimeRef` change):

7. **Sign in to AWS** (also hands creds to the daemon so it can assume the cross-account role)
8. **Grant access** — generate + deploy the CloudFormation cross-account role
9. **Register** the `BedrockAgentCore` Runtime
10. **Push** the image to ECR + re-publish the Agent as `modelProvider: bedrock`
11. **Deploy** the same agent to AgentCore (runtime #2)
12. **Test** it — invoke the AWS-hosted runtime and see the reply

You can also drive any step from the terminal — every notebook cell maps to a script under `scripts/`.

---

## Files

```
.
├── demo.ipynb              The demo — starts at the agent lifecycle (audience-facing)
├── env.example             Template for .env.local
├── scripts/
│   ├── setup-env.sh        Interactive .env.local (hidden secrets + AWS profile picker)
│   ├── setup.sh            Engineer pre-demo: prereqs + kind + Keycloak + kagent + daemon
│   ├── 00-prereqs.sh       Install/validate CLIs, pin enterprise arctl
│   ├── 01-cluster.sh       kind cluster + local OCI registry + Gateway API
│   ├── 02-keycloak.sh      Keycloak + the `solo` realm
│   ├── 03-kagent.sh        Solo Enterprise for kagent (Anthropic, OIDC)
│   ├── 04-daemon.sh        Start the standalone arctl daemon
│   ├── 05-scaffold.sh      Verify the scaffolded artifact projects
│   ├── 06-build-publish.sh Build/push images, publish all three artifacts
│   ├── 07-runtime-deploy.sh Register the Kubernetes Runtime, deploy to kagent
│   ├── 08-agentcore.sh     AgentCore add-on: CF role, BedrockAgentCore runtime, ECR, deploy
│   ├── ask.sh              Call the hosted agent via kagent A2A (mints a user token)
│   ├── test-local.sh       Run the agent + MCP locally with `arctl run`
│   ├── port-forward.sh     kagent dashboard on http://localhost:8080
│   ├── cleanup.sh          Tear down everything, or AWS bits only
│   ├── quick.sh            Orchestrator: setup-env | setup | prereqs | up | agentcore | status | teardown
│   └── lib.sh              Shared helpers, version pins, env defaults
├── artifacts/
│   ├── textkit/            MCPServer: word_count + extract_links (FastMCP, Python)
│   ├── summary-style/      Skill: the house format (SKILL.md)
│   └── summarizer/         Agent: ADK; model from MODEL_PROVIDER (anthropic | bedrock)
├── yaml/                   Deployment + Keycloak manifests
└── kind/                   kind cluster config
```

`quick.sh` is the one-shot alternative to the notebook: `./scripts/quick.sh up` runs the whole kagent path end to end; `./scripts/quick.sh agentcore` adds the AWS deployment.

## Teardown

```bash
./scripts/cleanup.sh agentcore   # AWS only (CloudFormation stack, runtime, ECR repo, deployment)
./scripts/cleanup.sh             # everything: AWS bits, then kind cluster, daemon, registry
```

`cleanup.sh` no-ops cleanly with no live AWS session, so the full teardown is safe even if you skipped AgentCore.
