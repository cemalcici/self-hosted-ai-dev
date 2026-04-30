#!/usr/bin/env sh
# Bootstrap wrapper: runs as root to fix volume ownership, then drops
# to the openchamber user before launching the server.
#
# Docker named volumes attach as root:root.  The openchamber server
# (running as UID 1000) needs to write to the mounted config directory,
# so this script repairs ownership before the server starts.
set -e

CONFIG_DIR="/home/openchamber/.config/openchamber"
USER="openchamber"
OPENCHAMBER_DATA_DIR="/home/openchamber/.config/openchamber"
export OPENCHAMBER_DATA_DIR

# Create the 'run' subdirectory that the openchamber server requires,
# and fix the entire config tree ownership so UID 1000 can use it.
mkdir -p "$CONFIG_DIR/run"
chown -R 1000:1000 "$CONFIG_DIR"

# Also ensure the workspace volume is writable by the openchamber user
chown -R 1000:1000 /workspace 2>/dev/null || true

# Verify the openchamber user exists
id "$USER" >/dev/null 2>&1 || { echo "error: user $USER does not exist" >&2; exit 1; }

# Build the serve command.  --foreground is critical:
#   Without it, serve daemonizes and spawns a detached child that survives
#   docker-compose restart, holding port 3000 and causing
#   "OpenChamber is already running on port 3000 (PID: N)" on the next start.
#   With --foreground the server stays as PID 1 inside the container so
#   docker compose restart sends SIGTERM directly to it and it exits cleanly.
OPENCHAMBER_PORT="${OPENCHAMBER_PORT:-3000}"
OPENCHAMBER_HOST="${OPENCHAMBER_HOST:-0.0.0.0}"
export OPENCHAMBER_HOST

CMD="bun packages/web/bin/cli.js serve --port $OPENCHAMBER_PORT --foreground"

# Pass --ui-password if the environment variable is set
if [ -n "${UI_PASSWORD:-}" ]; then
  # Also export so cli.js can pick it up via env
  export OPENCHAMBER_UI_PASSWORD="$UI_PASSWORD"
fi

# shellcheck disable=SC2086
exec runuser -u "$USER" -- sh -c "exec $CMD"
