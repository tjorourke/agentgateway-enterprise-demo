#!/usr/bin/env bash
# 08-agentcore.sh — deploy the SAME published agent to AWS Bedrock AgentCore,
# alongside the kagent deployment from 07. Steps (all via the local arctl
# daemon + the AWS CLI):
#
#   1. preflight: a live AWS session (aws sso login) + the agent in the catalog
#   2. arctl runtime setup bedrock-agent-core  -> a CloudFormation template that
#      grants AgentRegistry a cross-account role, plus an External ID
#   3. deploy that CF stack, read back the role ARN
#   4. register a BedrockAgentCore Runtime pointing at your AWS account
#   5. build + push the agent image to ECR (AgentCore can't pull localhost:5001)
#   6. apply a Deployment binding the agent to the AgentCore runtime
#
# AgentCore clones the agent source from a git repo at deploy time and pulls the
# image from ECR, so both must be reachable from AWS. Configure via env below.
#
# Usage:
#   aws sso login --profile <profile>
#   AWS_PROFILE=<profile> ./scripts/08-agentcore.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

require aws; require docker; require jq; require arctl
# Only the agent model key is needed here — no Solo/kagent license (AgentCore
# doesn't touch the cluster). ANTHROPIC_API_KEY rides into the AgentCore container.
load_secrets
[[ -n "${ANTHROPIC_API_KEY:-}" ]] || die "ANTHROPIC_API_KEY required (export it, set it in .env.local, or point SECRETS_FILE at a file with it)"
cd "$LAB_ROOT"
arctl_token

# ── config (override via env) ────────────────────────────────────────────────
export AWS_REGION="${AWS_REGION:-us-east-1}"
AGENT_NAME="${AGENT_NAME:-summarizer}"
AWS_RUNTIME_ID="${AWS_RUNTIME_ID:-aws-agentcore}"
STACK_NAME="${STACK_NAME:-AgentRegistryAccess}"
ROLE_NAME="${ROLE_NAME:-AgentRegistryAccessRole-agentcore-demo}"
IMAGE_TAG="${IMAGE_TAG:-0.0.1}"
ECR_REPO_NAME="${ECR_REPO_NAME:-$AGENT_NAME}"
# Git source AgentCore clones at deploy time. Defaults to this repo's origin.
AGENT_GIT_URL="${AGENT_GIT_URL:-$(git -C "$LAB_ROOT" remote get-url origin 2>/dev/null | sed 's#git@github.com:#https://github.com/#;s#\.git$##').git}"
AGENT_GIT_BRANCH="${AGENT_GIT_BRANCH:-$(git -C "$LAB_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)}"
AGENT_GIT_SUBFOLDER="${AGENT_GIT_SUBFOLDER:-agentregistry-agentcore-kind/artifacts/summarizer}"

# ── 1. preflight ─────────────────────────────────────────────────────────────
step "AWS preflight"
ident="$(aws sts get-caller-identity 2>/dev/null)" \
  || die "no live AWS session. Run: aws sso login --profile <your-profile>  (then re-export AWS_PROFILE)"
AWS_ACCOUNT_ID="$(echo "$ident" | jq -r .Account)"
ok "AWS account ${AWS_ACCOUNT_ID} / region ${AWS_REGION}"
arctl get agent "$AGENT_NAME" >/dev/null 2>&1 \
  || die "agent '$AGENT_NAME' not in the catalog — run ./scripts/06-build-publish.sh first"
ok "agent '$AGENT_NAME' is in the catalog"

# The daemon container is what assumes the cross-account role to manage AgentCore,
# so it needs AWS credentials. Its compose forwards AWS_* from the env at daemon
# start — but step 04 started it before you logged in to AWS, so the vars are
# empty. Resolve creds from the live session and restart the daemon so it picks
# them up (the catalog persists in postgres across the restart).
step "Giving the daemon AWS credentials"
creds="$(aws configure export-credentials --format env 2>/dev/null)" \
  || die "could not export AWS credentials from the current session"
eval "$creds"; export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_REGION
DC="$(docker ps --filter publish=12121 --format '{{.Names}}' | head -1)"
if [[ -z "$(docker exec "$DC" printenv AWS_ACCESS_KEY_ID 2>/dev/null)" ]]; then
  arctl daemon stop >/dev/null 2>&1; arctl daemon start >/dev/null 2>&1 || die "daemon restart failed"
  DC="$(docker ps --filter publish=12121 --format '{{.Names}}' | head -1)"
  docker network connect kind "$DC" >/dev/null 2>&1 || true   # restart drops the kind-net join
  end=$(( $(date +%s) + 60 )); until curl -sf "${ARCTL_API_BASE_URL}/" >/dev/null 2>&1; do [[ $(date +%s) -ge $end ]] && break; sleep 2; done
  arctl_token
  ok "daemon restarted with AWS credentials"
else
  ok "daemon already has AWS credentials"
fi

# ── 2. CloudFormation template + External ID ─────────────────────────────────
step "Generating the AgentRegistry access CloudFormation template"
CF_YAML="$LAB_ROOT/.agentcore/cf.yaml"; mkdir -p "$LAB_ROOT/.agentcore"
# `runtime setup` prints the template on stdout (-> CF_YAML) and the External ID
# on stderr (-> tee'd to a file so we can parse it).
arctl runtime setup bedrock-agent-core \
  --aws-account-id "$AWS_ACCOUNT_ID" --role-name "$ROLE_NAME" \
  2> >(tee "$LAB_ROOT/.agentcore/setup.stderr" >&2) > "$CF_YAML" \
  || die "arctl runtime setup bedrock-agent-core failed (token? daemon? account id?)"
# The External ID is a base64url token (e.g. MxME5geCNG46U3Qpk_VREBe...), not a
# UUID — match the full [A-Za-z0-9_-] charset.
AWS_EXTERNAL_ID="$(grep -ioE 'External ID:[[:space:]]*[A-Za-z0-9_-]+' "$LAB_ROOT/.agentcore/setup.stderr" | awk '{print $NF}' | head -1)"
[[ -n "$AWS_EXTERNAL_ID" ]] || die "could not parse External ID from runtime setup output ($LAB_ROOT/.agentcore/setup.stderr)"
ok "CF template -> $CF_YAML ; External ID ${AWS_EXTERNAL_ID}"

# ── 3. deploy the CF stack, read the role ARN ────────────────────────────────
step "Deploying CloudFormation stack '$STACK_NAME' (cross-account IAM role)"
if aws cloudformation describe-stacks --stack-name "$STACK_NAME" >/dev/null 2>&1; then
  ok "stack '$STACK_NAME' already exists — reusing"
else
  aws cloudformation create-stack --stack-name "$STACK_NAME" \
    --template-body "file://$CF_YAML" --capabilities CAPABILITY_NAMED_IAM >/dev/null
  log "waiting for stack create to complete..."
  aws cloudformation wait stack-create-complete --stack-name "$STACK_NAME"
  ok "stack created"
fi
AWS_ROLE_ARN="$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" \
  --query 'Stacks[0].Outputs[?OutputKey==`RoleArn`].OutputValue' --output text)"
[[ -n "$AWS_ROLE_ARN" && "$AWS_ROLE_ARN" != "None" ]] || die "no RoleArn output on stack '$STACK_NAME'"
ok "role ARN ${AWS_ROLE_ARN}"

# ── 4. register the BedrockAgentCore Runtime ─────────────────────────────────
step "Registering the BedrockAgentCore Runtime '$AWS_RUNTIME_ID'"
RT_YAML="$(mktemp)"
cat > "$RT_YAML" <<EOF
apiVersion: ar.dev/v1alpha1
kind: Runtime
metadata:
  name: ${AWS_RUNTIME_ID}
spec:
  type: BedrockAgentCore
  config:
    roleArn: "${AWS_ROLE_ARN}"
    externalId: "${AWS_EXTERNAL_ID}"
    region: "${AWS_REGION}"
EOF
arctl apply -f "$RT_YAML"; rm -f "$RT_YAML"
arctl get runtimes 2>/dev/null | sed 's/^/  /' >&2 || true
ok "runtime '$AWS_RUNTIME_ID' registered"

# ── 5. build + push the agent image to ECR ───────────────────────────────────
step "Ensuring ECR repo '$ECR_REPO_NAME' and pushing the agent image (linux/amd64)"
aws ecr describe-repositories --repository-names "$ECR_REPO_NAME" >/dev/null 2>&1 \
  || aws ecr create-repository --repository-name "$ECR_REPO_NAME" >/dev/null
ECR_HOST="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
ECR_IMAGE="${ECR_HOST}/${ECR_REPO_NAME}:${IMAGE_TAG}"
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$ECR_HOST" >/dev/null
# AgentCore expects an amd64 layer set; force the platform on Apple Silicon.
arctl build "./$ARTIFACTS_DIR/$AGENT_NAME" --push --platform linux/amd64 --image "$ECR_IMAGE"
ok "pushed ${ECR_IMAGE}"

# ── 6. update the catalog Agent's source + deploy to AgentCore ───────────────
step "Pointing the Agent at the ECR image + git source, re-publishing"
AGENT_YAML="$(mktemp)"
cat > "$AGENT_YAML" <<EOF
apiVersion: ar.dev/v1alpha1
kind: Agent
metadata:
  name: ${AGENT_NAME}
spec:
  description: Summarizes pasted text in the house format, using textkit MCP tools.
  modelName: claude-haiku-4-5
  modelProvider: anthropic
  source:
    image: ${ECR_IMAGE}
    repository:
      url: ${AGENT_GIT_URL}
      branch: ${AGENT_GIT_BRANCH}
      subfolder: ${AGENT_GIT_SUBFOLDER}
EOF
arctl apply -f "$AGENT_YAML"; rm -f "$AGENT_YAML"
log "git source AgentCore will clone: ${AGENT_GIT_URL}@${AGENT_GIT_BRANCH}/${AGENT_GIT_SUBFOLDER}"
log "(that branch must be pushed and reachable by AWS before the deploy succeeds)"

step "Deploying '$AGENT_NAME' onto AgentCore"
DEPLOY_YAML="$(mktemp)"
cat > "$DEPLOY_YAML" <<EOF
apiVersion: ar.dev/v1alpha1
kind: Deployment
metadata:
  name: ${AGENT_NAME}-agentcore
spec:
  targetRef:
    kind: Agent
    name: ${AGENT_NAME}
  runtimeRef:
    kind: Runtime
    name: ${AWS_RUNTIME_ID}
  runtimeConfig:
    region: ${AWS_REGION}
  env:
    ANTHROPIC_API_KEY: "${ANTHROPIC_API_KEY}"
EOF
arctl apply -f "$DEPLOY_YAML"; rm -f "$DEPLOY_YAML"
ok "deployment '${AGENT_NAME}-agentcore' applied — status streams below"
arctl get deployments 2>/dev/null | sed 's/^/  /' >&2 || true

step "AgentCore deploy submitted"
cat >&2 <<EOF

  Watch it reconcile:   arctl get deployments
  Test in AWS console:  Bedrock AgentCore -> your runtime -> send a JSON-RPC
                        message/send payload (see the notebook for one).
  Tear down AWS bits:   ./scripts/cleanup.sh agentcore
EOF
