#!/usr/bin/env sh
set -e

CONFIG_DIR="/home/aidev/.config/openchamber"
USER="aidev"
OPENCHAMBER_DATA_DIR="/home/aidev/.config/openchamber"
export OPENCHAMBER_DATA_DIR

mkdir -p "$CONFIG_DIR/run" "$CONFIG_DIR/logs"
chown -R "$USER:$USER" "$CONFIG_DIR"
chown -R "$USER:$USER" /workspace 2>/dev/null || true

id "$USER" >/dev/null 2>&1 || { echo "error: user $USER does not exist" >&2; exit 1; }

OPENCHAMBER_PORT="${OPENCHAMBER_PORT:-3000}"
OPENCHAMBER_HOST="${OPENCHAMBER_HOST:-0.0.0.0}"
export OPENCHAMBER_HOST

CMD="bun packages/web/bin/cli.js serve --port $OPENCHAMBER_PORT --foreground"

if [ -n "${UI_PASSWORD:-}" ]; then
  export OPENCHAMBER_UI_PASSWORD="$UI_PASSWORD"
fi

exec runuser -u "$USER" -- sh -c "
  PID_FILE=\"$OPENCHAMBER_DATA_DIR/run/openchamber-$OPENCHAMBER_PORT.pid\"
  rm -f \"\$PID_FILE\"
  exec $CMD
"