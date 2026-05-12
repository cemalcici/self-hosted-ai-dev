# Persistent runtime data

This directory stores host-mounted persistent data for the single-container stack.

- `opencode/config` — OpenCode config and plugin state
- `opencode/share` — OpenCode share/state data
- `openchamber` — OpenChamber config and runtime state
- `workspace` — user workspace files
- `ssh` — SSH keys/config used from inside the container

These paths are runtime-owned by the `aidev` user inside the container.