#!/usr/bin/env sh
set -eu

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
OPENCODE_CONFIG_DIR="$CONFIG_HOME/opencode"
CONFIG_FILE="$OPENCODE_CONFIG_DIR/opencode.json"

mkdir -p "$OPENCODE_CONFIG_DIR" "$DATA_HOME/opencode" /workspace

if [ ! -f "$CONFIG_FILE" ]; then
  cat > "$CONFIG_FILE" <<'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "plugin": ["oh-my-opencode-slim"]
}
EOF
else
  # Migrate legacy "plugins" key to "plugin" if present
  if grep -q '"plugins"' "$CONFIG_FILE" && ! grep -q '"plugin"' "$CONFIG_FILE"; then
    sed -i 's/"plugins"/"plugin"/g' "$CONFIG_FILE"
  fi
fi

export PATH="$HOME/.bun/bin:$PATH"

if ! command -v opencode >/dev/null 2>&1; then
  echo "opencode binary not found" >&2
  exit 1
fi

bunx_output=$(bunx oh-my-opencode-slim --help 2>&1) || {
  echo "oh-my-opencode-slim check failed:" >&2
  echo "$bunx_output" >&2
  echo "oh-my-opencode-slim package not found in bun cache" >&2
  exit 1
}

exec runuser -u aidev -- opencode serve --hostname 0.0.0.0 --port "${OPENCODE_PORT:-4096}"
