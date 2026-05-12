#!/usr/bin/env sh
set -e

OPENCODE_PORT="${OPENCODE_PORT:-4096}"
OPENCHAMBER_PORT="${OPENCHAMBER_PORT:-3000}"
OPENCODE_CONFIG_DIR="/home/aidev/.config/opencode"
OPENCHAMBER_CONFIG_DIR="/home/aidev/.config/openchamber"

export PATH="/home/aidev/.bun/bin:${PATH}"

mkdir -p "$OPENCODE_CONFIG_DIR" /home/aidev/.local/share/opencode "$OPENCHAMBER_CONFIG_DIR/run" /workspace /home/aidev/.ssh
chown -R aidev:aidev /home/aidev /workspace

/usr/local/bin/opencode-bootstrap.sh > /tmp/opencode.log 2>&1 &
OPENCODE_PID=$!

cleanup() {
  kill "$OPENCODE_PID" 2>/dev/null || true
  kill "$OPENCHAMBER_PID" 2>/dev/null || true
  wait "$OPENCODE_PID" 2>/dev/null || true
  wait "$OPENCHAMBER_PID" 2>/dev/null || true
}

trap cleanup INT TERM EXIT

MAX_RETRIES=60
retries=0
until python3 -c "import urllib.request; r=urllib.request.urlopen('http://127.0.0.1:${OPENCODE_PORT}/global/health', timeout=2); raise SystemExit(0 if r.status == 200 else 1)"; do
  retries=$((retries+1))
  if [ $retries -ge $MAX_RETRIES ]; then
    echo "OpenCode failed to become reachable after $MAX_RETRIES retries" >&2
    cat /tmp/opencode.log >&2
    exit 1
  fi
  sleep 1
done

echo "OpenCode is healthy, starting OpenChamber..."

/usr/local/bin/openchamber-bootstrap.sh &
OPENCHAMBER_PID=$!

wait "$OPENCHAMBER_PID"