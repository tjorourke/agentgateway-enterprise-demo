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

1. **AWS profile** — in step 1, pick yours from the menu (or set `AWS_PROFILE`).
2. **An agent-source repo** — AgentCore builds the agent from source, so it clones a git repo at deploy time. You need one. `setup-env.sh` offers to create it for you with the `gh` CLI (using your GitHub login), or run the helper directly:
   ```sh
   ./scripts/create-agent-repo.sh                 # private repo, gh-derived name, pushes the agent source
   REPO_VISIBILITY=public ./scripts/create-agent-repo.sh   # public (simplest — no token needed)
   ```
   It sets `AGENT_GIT_URL`, `AGENT_GIT_BRANCH`, `AGENT_GIT_SUBFOLDER` in `.env.local` for you.
   - **Private repo:** the registry needs a token to clone it — the notebook/scripts embed your `gh auth token` in the clone URL automatically.
   - **Public repo:** clones with no token. The agent code is non-sensitive demo code, so public is the simplest choice.
3. Run the AWS section of the notebook (sign in → grant access → register runtime → deploy → test).

On kagent the agent uses your Anthropic key; on AgentCore it uses native Bedrock Claude via the AWS role (no key).

## One-shot alternative (no notebook)

```bash
./scripts/quick.sh up          # whole kagent path end to end
./scripts/ask.sh "summarize this: <text with a couple of links>"
./scripts/quick.sh agentcore   # add the AWS deployment (needs aws sso login)
```

## Reset / teardown

```bash
./scripts/reset.sh               # back to start: remove the scaffold, deployments,
                                 #   catalog entries, AWS runtimes/stack/ECR — but
                                 #   KEEP the platform up so you can re-run the demo
./scripts/cleanup.sh agentcore   # AWS bits only
./scripts/cleanup.sh             # full teardown (cluster, daemon, registry, AWS)
```

Run `./scripts/reset.sh` between demo runs; `cleanup.sh` when you're done with the cluster.
