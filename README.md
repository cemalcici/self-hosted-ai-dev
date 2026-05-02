# Dokploy OpenCode Stack

This repository provides a single-container Dokploy image that packages OpenCode, oh-my-opencode-slim, and OpenChamber into one runtime.

## Primary deployment (compose-first)

```bash
git submodule update --init
cp .env.example .env
docker compose up --build -d
```

### Dokploy notes

`docker-compose.yml` is the primary deployment contract. It already declares named volumes for all persistent paths — use it as the source of truth for volume configuration.

- **Persistence:** In Dokploy, map persistence to the container paths listed below, or preserve the named volumes declared by Compose (`opencode_config`, `opencode_data`, `openchamber_config`, `workspace`).
- **Routing:** No host `ports:` mapping is required in this design. Dokploy/Traefik should route public traffic directly to the container's internal port `3000` (OpenChamber).
- **Persistent storage paths:**
  - `/home/opencode/.config/opencode` — OpenCode runtime config, session state, and credentials
  - `/home/opencode/.local/share/opencode` — OpenCode persistent data
  - `/home/openchamber/.config/openchamber` — OpenChamber config
  - `/workspace` — workspace state, cloned repositories, and generated files

Without these mounts, sessions, provider credentials, runtime config, and workspace state are lost on container restart.

## Prerequisites

Before deploying, ensure the `openchamber` git submodule is present:

```bash
git submodule update --init
```

This is required because `docker compose build` copies from the `openchamber/` source tree. Without the submodule checked out, the build will fail.

## Environment variables

Copy `.env.example` to `.env` for local validation. In Dokploy, define the same variables in the project environment UI.

Key variables:

- `UI_PASSWORD` — required; password for the OpenChamber web UI
- `OPENCODE_PORT` — optional; defaults to 4096 inside the container; the internal OpenCode health-check and serve port
- `OPENCHAMBER_PORT` — optional; defaults to 3000 inside the container; the internal listen port inside the container (not a host publish setting — routing is handled by Dokploy/Traefik to container port 3000)
- One or more provider API keys such as `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, or `GOOGLE_API_KEY`

## Startup sequence

The container starts OpenCode first, waits for its localhost health check on port 4096, then starts OpenChamber on port 3000.

## Workspace directory

The `/workspace` directory is shared by both services inside the container. Repositories cloned through OpenChamber are available to OpenCode without any additional volume configuration.

## oh-my-opencode-slim agents in OpenChamber

`oh-my-opencode-slim` does not create native OpenCode agent files under `~/.config/opencode/agents/`. Because of that, OpenChamber's agent picker is expected to show the native OpenCode agents such as `build` and `plan`, not the plugin's internal specialist roles.

The plugin specialists (`orchestrator`, `oracle`, `librarian`, `explorer`, `designer`, `fixer`) are plugin-managed roles. Use them through the orchestrator flow or by mentioning them in chat when the client supports that pattern, rather than expecting them to appear as standalone OpenChamber agent cards.

## Editing the oh-my-opencode-slim preset

The repo-managed source file for the default preset is `config/oh-my-opencode-slim.jsonc`. To change the shipped preset, edit that file in the repo and rebuild/redeploy the stack.

**Automatic sync on every start:** the entrypoint script copies `config/oh-my-opencode-slim.jsonc` into the persistent OpenCode config directory as `~/.config/opencode/oh-my-opencode-slim.jsonc` on every container start. This means any preset changes committed to the repo are automatically applied when the container restarts or the stack is redeployed—no manual volume edits or file deletion required.
