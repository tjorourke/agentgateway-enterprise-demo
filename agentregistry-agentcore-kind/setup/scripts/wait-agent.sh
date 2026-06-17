#!/usr/bin/env bash
# wait-agent.sh [name] — poll until the kagent Agent is Ready (the real signal;
# the registry Deployment can sit at "deploying" even once the agent is serving).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"
set +e   # polling expects non-zero exits (grep no-match, not-Ready yet)
NAME="${1:-agentdemo}"; TIMEOUT="${2:-300}"
end=$(( $(date +%s) + TIMEOUT ))
while :; do
  A="$(kc -n kagent get agents.kagent.dev -o name 2>/dev/null | grep -i "$NAME" | head -1)"
  if [[ -n "$A" ]]; then
    st="$(kc -n kagent get "${A#*/}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)"
    echo "  ${A##*/}: ready=${st:-...}"
    [[ "$st" == "True" ]] && { ok "agent is Ready"; break; }
  else
    echo "  waiting for kagent agent matching '$NAME'..."
  fi
  [[ $(date +%s) -ge $end ]] && { warn "not Ready in ${TIMEOUT}s — check: kubectl -n kagent get agent,pods"; break; }
  sleep 5
done
kc -n kagent get agents,pods 2>/dev/null | grep -viE 'controller|postgres|kagent-tools|kmcp-enterprise' | sed 's/^/  /'
