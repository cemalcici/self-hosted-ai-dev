# Dokploy OpenCode Stack

This repository provides a single-container Dokploy image that packages OpenCode, oh-my-opencode-slim, and OpenChamber into one runtime.

## Primary deployment (compose-first)

```bash
git submodule update --init
cp .env.example .env
docker compose up --build -d
```

### Dokploy notes

`docker-compose.yml` is the primary deployment contract. It declares host-mounted `./data/...` paths for all persistent storage — use it as the source of truth for volume configuration.

- **Persistence:** In Dokploy, bind-mount the host paths listed below to the container paths. The `./data/` directory on the host is the persistence anchor.
- **Routing:** No host `ports:` mapping is required in this design. Dokploy/Traefik should route public traffic directly to the container's internal port `3000` (OpenChamber).
- **Persistent storage paths (host → container):**
  - `./data/opencode/config` → `/home/aidev/.config/opencode` — OpenCode runtime config, session state, and credentials
  - `./data/opencode/share` → `/home/aidev/.local/share/opencode` — OpenCode persistent data
  - `./data/openchamber` → `/home/aidev/.config/openchamber` — OpenChamber config
  - `./data/workspace` → `/workspace` — workspace state, cloned repositories, and generated files
  - `./data/ssh` → `/home/aidev/.ssh` — SSH keys and known hosts

Without these mounts, sessions, provider credentials, runtime config, and workspace state are lost on container restart.

### Backup-worthy paths

Back up these host directories to preserve user data:

- `./data/opencode/config`
- `./data/opencode/share`
- `./data/openchamber`
- `./data/workspace`
- `./data/ssh`

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

## Operator workflow

### Entering the container

```bash
docker compose exec -u aidev aidev sh
```

### Verifying persistence paths

```bash
ls -la /home/aidev/.config/opencode
ls -la /home/aidev/.config/openchamber
```

### Authenticating providers

Inside the container as `aidev`, use the OpenCode CLI to authenticate:

```bash
opencode auth login
```

### Editing the runtime preset

The `oh-my-opencode-slim` preset file is repo-managed and bind-mounted into the container.
Edit it on the host:

```bash
nano ./config/oh-my-opencode-slim.jsonc
```

Then restart the service to apply changes:

```bash
docker compose restart aidev
```

### Installing skills or plugins

```bash
docker compose exec -u aidev aidev sh
# Inside the container, use opencode to install
opencode skills install <skill-name>
# Or install a plugin
opencode plugin install <plugin-url>
```

### Verifying persistence after restart

```bash
docker compose exec -u aidev aidev sh
ls -la /home/aidev/.config/opencode
ls -la /home/aidev/.config/openchamber
```

All runtime state — config, credentials, installed plugins, and skills — persists across restarts as long as the `./data/` host directory is preserved.
