# AgentRegistry: one agent, two runtimes

A developer-persona demo: drive the `arctl` CLI through the agent lifecycle (scaffold → build → publish), then deploy **one** published agent to **two** runtimes — Solo Enterprise for **kagent** (local kind) and **AWS Bedrock AgentCore** — by changing one line, the Deployment's `runtimeRef`. The demo itself runs in `demo.ipynb`; this README is the engineer setup you do **before** opening it.

## Prerequisites

- Docker running
- An **Anthropic API key** and a **Solo Enterprise for kagent license**
- `gcloud auth login` (Solo's Helm charts pull over OCI)
- A **bash-kernel** Jupyter ([`bash_kernel`](https://github.com/takluyver/bash_kernel)) to run the notebook
- *AgentCore add-on only:* an AWS account with an SSO profile in `~/.aws/config`

Everything else (kind, kubectl, helm, jq, gh, uv, aws CLI, enterprise `arctl`) is installed for you in step 2.

## Run it

```bash
# 1. Capture credentials (prompts for each; secrets hidden; AWS profile picker)
./scripts/setup-env.sh

# 2. Bring up the platform: kind + Keycloak + kagent + the arctl daemon (~15 min first run)
./scripts/setup.sh
```

Then open **`demo.ipynb`** and run it top to bottom. It starts with a one-cell *Connect*, then walks the lifecycle and deploys to kagent — that's the local demo, no AWS needed.

## AgentCore add-on

To also deploy the same agent to AWS (the notebook's second half):

1. In step 1 above, pick your **AWS profile** from the menu (or set `AWS_PROFILE`).
2. AgentCore clones the agent source from git, so push this branch somewhere AWS can reach (public) and set in `.env.local`:
   ```sh
   export AGENT_GIT_URL="https://github.com/<you>/agentgateway-enterprise-demo.git"
   export AGENT_GIT_BRANCH="<this-branch>"
   ```
3. Run the AWS section of the notebook (sign in → grant access → register runtime → deploy → test).

On kagent the agent uses your Anthropic key; on AgentCore it uses native Bedrock Claude via the AWS role (no key).

## One-shot alternative (no notebook)

```bash
./scripts/quick.sh up          # whole kagent path end to end
./scripts/ask.sh "summarize this: <text with a couple of links>"
./scripts/quick.sh agentcore   # add the AWS deployment (needs aws sso login)
```

## Teardown

```bash
./scripts/cleanup.sh agentcore   # AWS only
./scripts/cleanup.sh             # everything (cluster, daemon, registry, AWS)
```
