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

# Create the 'run' subdirectory that the openchamber server requires,
# and fix the entire config tree ownership so UID 1000 can use it.
mkdir -p "$CONFIG_DIR/run"
chown -R 1000:1000 "$CONFIG_DIR"

# Also ensure the workspace volume is writable by the openchamber user
chown -R 1000:1000 /workspace 2>/dev/null || true

# Verify the openchamber user exists
id "$USER" >/dev/null 2>&1 || { echo "error: user $USER does not exist" >&2; exit 1; }

# Delegate to the real entrypoint as the openchamber user.
# runuser (no -l) avoids login-shell setup that can fail in some environments.
# Using --session-command to pass the script path avoids shell parsing issues.
exec runuser -u "$USER" -- sh /home/openchamber/openchamber-entrypoint.sh "$@"
