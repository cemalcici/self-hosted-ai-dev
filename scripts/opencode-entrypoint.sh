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

if [ ! -f "$PLUGIN_CONFIG_FILE" ]; then
  cat > "$PLUGIN_CONFIG_FILE" <<'EOF'
{
  "$schema": "https://unpkg.com/oh-my-opencode-slim@latest/oh-my-opencode-slim.schema.json",
  "preset": "openai",
  "presets": {
    "openai": {
      "orchestrator": { "model": "openai/gpt-5.4", "variant": "high", "skills": ["*"], "mcps": ["*", "!context7"] },
      "oracle": { "model": "openai/gpt-5.4", "variant": "high", "skills": ["simplify"], "mcps": [] },
      "librarian": { "model": "openai/gpt-5.4-mini", "variant": "low", "skills": [], "mcps": ["websearch", "context7", "grep_app"] },
      "explorer": { "model": "openai/gpt-5.4-mini", "variant": "low", "skills": [], "mcps": [] },
      "designer": { "model": "openai/gpt-5.4-mini", "variant": "medium", "skills": ["agent-browser"], "mcps": [] },
      "fixer": { "model": "openai/gpt-5.4-mini", "variant": "low", "skills": [], "mcps": [] }
    }
  },
  "showStartupToast": true,
  "disabled_mcps": []
}
EOF
fi

# Add bun global bin to PATH for user
export PATH="$HOME/.bun/bin:$PATH"

if ! command -v opencode >/dev/null 2>&1; then
  echo "opencode binary not found" >&2
  exit 1
fi

# oh-my-opencode-slim is installed via bunx in the build and accessed via bunx or direct script execution
# Verify the plugin package is available in the bun cache
if ! bunx oh-my-opencode-slim --help >/dev/null 2>&1; then
  echo "oh-my-opencode-slim package not found in bun cache" >&2
  exit 1
fi

exec opencode serve --hostname 0.0.0.0 --port "${OPENCODE_PORT:-4096}"