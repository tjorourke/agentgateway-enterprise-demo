#!/usr/bin/env bash
# notebook-server.sh — start a Jupyter server with a Bash kernel for the demo
# notebook, and print the URL to connect Cursor/VS Code to.
#
# Why: Cursor's bundled Jupyter extension can't reliably raw-launch a fresh
# non-Python (Bash) kernel — it errors and disposes the kernel ("Run does
# nothing"). Connecting to a real Jupyter server side-steps that entirely.
#
#   ./setup/scripts/notebook-server.sh
#   # then in Cursor: Select Kernel -> Existing Jupyter Server... -> paste the URL -> Bash
#
# Self-contained: creates a Python venv (stable 3.13) with jupyterlab + bash_kernel
# on first run and registers the Bash kernelspec.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"   # where demo.ipynb lives
VENV="${BASHKERNEL_VENV:-$HOME/.venvs/bashkernel313}"
PORT="${JUPYTER_PORT:-8889}"
TOKEN="${JUPYTER_TOKEN:-solodemo}"

PY="$(command -v python3.13 || command -v python3 || true)"
[ -n "$PY" ] || { echo "python3 required"; exit 1; }
if [ ! -x "$VENV/bin/jupyter" ]; then
  echo "Creating Jupyter venv at $VENV (one-time)..."
  "$PY" -m venv "$VENV"
  "$VENV/bin/pip" install -q --upgrade pip
  "$VENV/bin/pip" install -q jupyterlab bash_kernel
  "$VENV/bin/python" -m bash_kernel.install --user
fi

pkill -f "jupyter.*--port=$PORT" 2>/dev/null || true; sleep 1
echo "Starting Jupyter server on http://127.0.0.1:$PORT ..."
nohup "$VENV/bin/jupyter" lab --no-browser --ip=127.0.0.1 --port="$PORT" \
  --ServerApp.token="$TOKEN" --ServerApp.password='' --ServerApp.disable_check_xsrf=True \
  --notebook-dir="$DEMO_ROOT" >/tmp/agentcore-demo-jupyter.log 2>&1 &
sleep 5
if curl -sf "http://127.0.0.1:$PORT/api?token=$TOKEN" >/dev/null 2>&1; then
  cat <<EOF

  Jupyter server is up. In Cursor / VS Code:
    Select Kernel  ->  Existing Jupyter Server...  ->  paste:

      http://127.0.0.1:$PORT/?token=$TOKEN

    then choose the  Bash  kernel and run demo.ipynb.

  (log: /tmp/agentcore-demo-jupyter.log)
EOF
else
  echo "Server did not come up — see /tmp/agentcore-demo-jupyter.log"; exit 1
fi
