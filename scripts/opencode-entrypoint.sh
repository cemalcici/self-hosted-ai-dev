#!/usr/bin/env sh
set -eu

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
OPENCODE_CONFIG_DIR="$CONFIG_HOME/opencode"
PLUGIN_CONFIG_FILE="$OPENCODE_CONFIG_DIR/oh-my-opencode-slim.jsonc"
CONFIG_FILE="$OPENCODE_CONFIG_DIR/opencode.json"

mkdir -p "$OPENCODE_CONFIG_DIR" "$DATA_HOME/opencode" /workspace

if [ ! -f "$CONFIG_FILE" ]; then
  cat > "$CONFIG_FILE" <<'EOF'
{
  "plugins": ["oh-my-opencode-slim"]
}
EOF
fi

REPO_PLUGIN_CONFIG_TEMPLATE="/app/config/oh-my-opencode-slim.jsonc"

cp "$REPO_PLUGIN_CONFIG_TEMPLATE" "$PLUGIN_CONFIG_FILE"

# Add bun global bin to PATH for user
export PATH="$HOME/.bun/bin:$PATH"

if ! command -v opencode >/dev/null 2>&1; then
  echo "opencode binary not found" >&2
  exit 1
fi

# oh-my-opencode-slim is installed via bunx in the build and accessed via bunx or direct script execution
# Verify the plugin package is available in the bun cache
# Use output capture (not redirect) to avoid shell state issues with >/dev/null 2>&1
bunx_output=$(bunx oh-my-opencode-slim --help 2>&1) || {
  echo "oh-my-opencode-slim check failed:" >&2
  echo "$bunx_output" >&2
  echo "oh-my-opencode-slim package not found in bun cache" >&2
  exit 1
}

exec opencode serve --hostname 0.0.0.0 --port "${OPENCODE_PORT:-4096}"
