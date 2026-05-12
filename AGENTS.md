# AGENTS.md

## Purpose

This repository packages **OpenCode**, **oh-my-opencode-slim**, and **OpenChamber** into a **single-container** runtime for Dokploy-style deployments.

The current deployment model is:
- **compose-first** via `docker-compose.yml`
- **one service**: `aidev`
- **one runtime user**: `aidev`
- **one shared home root**: `/home/aidev`

## Current Architecture

- `docker-compose.yml` is the primary deployment contract.
- `Dockerfile` builds the runtime image.
- OpenCode listens internally on `OPENCODE_PORT` (default `4096`).
- OpenChamber listens internally on `OPENCHAMBER_PORT` (default `3000`).
- Dokploy/Traefik should route public traffic to container port `3000`.


## Key Files

- `docker-compose.yml` — single-service deployment definition, persistence mounts
- `Dockerfile` — unified runtime image build

- `scripts/single-container-entrypoint.sh` — top-level startup sequencing (OpenCode first, then OpenChamber)
- `scripts/opencode-entrypoint.sh` — OpenCode bootstrap/config preparation
- `scripts/openchamber-entrypoint-wrapper.sh` — OpenChamber startup helper and runtime ownership/pid handling
- `README.md` — operator-facing deployment guide

## Runtime and Persistence Rules

These container paths are persisted via host-mounted `./data/...` directories:

- `/home/aidev/.config/opencode` — mounted from `./data/opencode/config`
- `/home/aidev/.local/share/opencode` — mounted from `./data/opencode/share`
- `/home/aidev/.config/openchamber` — mounted from `./data/openchamber`
- `/home/aidev/.ssh` — mounted from `./data/ssh`
- `/workspace` — mounted from `./data/workspace`

Runtime config, credentials, installed plugins, and skills are user-managed inside the persistent container filesystem. There is no preset auto-copy or repo-managed source of truth for config at runtime.

## OpenChamber / oh-my-opencode-slim Notes

- `oh-my-opencode-slim` specialist roles such as `orchestrator`, `oracle`, `librarian`, `explorer`, `designer`, and `fixer` are **plugin-internal roles**.
- OpenChamber's visible native agent list is expected to show OpenCode-native agents such as `build` and `plan`.
- Do **not** assume plugin specialist roles will appear as standalone OpenChamber agent cards.

## Safe Modification Rules

- Prefer updating the **root** `Dockerfile`, not reviving older multi-container patterns.
- Treat `docker-compose.yml` as the deployment source of truth.
- Do not reintroduce old two-container variables such as `OPENCODE_HOST` or `OPENCODE_SKIP_START` into the mainline single-container contract.
- Do not add OpenCode username/password auth back unless explicitly requested; current design assumes OpenCode is internal-only behind OpenChamber.
- Do not modify files inside `openchamber/` unless the change is intentional and necessary; prefer repo-side wrappers or build-time patching when possible.

## Verification Expectations

Before claiming deployment changes work, verify with fresh evidence:

```bash
docker compose config
docker compose up --build -d
docker compose ps
```

For health checks:

```bash
docker compose exec aidev python3 -c "import urllib.request; print(urllib.request.urlopen('http://127.0.0.1:4096/global/health').status)"
docker compose exec aidev python3 -c "import urllib.request; print(urllib.request.urlopen('http://127.0.0.1:3000/health').status)"
```

For submodule-dependent builds, ensure:

```bash
git submodule update --init
```
