#!/usr/bin/env sh
set -eu

OPENCODE_PORT="${OPENCODE_PORT:-4096}"
OPENCHAMBER_PORT="${OPENCHAMBER_PORT:-3000}"
OPENCODE_CONFIG_DIR="/home/opencode/.config/opencode"
OPENCHAMBER_CONFIG_DIR="/home/openchamber/.config/openchamber"

mkdir -p "$OPENCODE_CONFIG_DIR" /home/opencode/.local/share/opencode "$OPENCHAMBER_CONFIG_DIR/run" /workspace
chown -R opencode:opencode /home/opencode /workspace
chown -R openchamber:openchamber /home/openchamber /workspace

/usr/local/bin/opencode-bootstrap.sh > /tmp/opencode.log 2>&1 &
OPENCODE_PID=$!

cleanup() {
  kill "$OPENCODE_PID" 2>/dev/null || true
  kill "$OPENCHAMBER_PID" 2>/dev/null || true
  wait "$OPENCODE_PID" 2>/dev/null || true
  wait "$OPENCHAMBER_PID" 2>/dev/null || true
}

trap cleanup INT TERM EXIT

until su -s /bin/sh opencode -c "python3 -c \"import urllib.request; r=urllib.request.urlopen('http://127.0.0.1:${OPENCODE_PORT}/health', timeout=2); raise SystemExit(0 if r.status == 200 else 1)\""; do
  sleep 1
done

su -s /bin/sh openchamber -c "export OPENCHAMBER_UI_PASSWORD='${UI_PASSWORD:-}'; export OPENCHAMBER_DATA_DIR='${OPENCHAMBER_CONFIG_DIR}'; export OPENCHAMBER_HOST='0.0.0.0'; exec bun /app/packages/web/bin/cli.js serve --port ${OPENCHAMBER_PORT} --foreground" &
OPENCHAMBER_PID=$!

wait "$OPENCHAMBER_PID"
