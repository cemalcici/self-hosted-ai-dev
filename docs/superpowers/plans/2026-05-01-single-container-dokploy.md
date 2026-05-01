# Single-Container Dokploy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current two-service Compose deployment with a single Dokploy-targeted Dockerfile/container that runs OpenCode, OpenChamber, and oh-my-opencode-slim together with deterministic startup and shared in-container config locality.

**Architecture:** Build one runtime image that contains both OpenCode and OpenChamber, then start them under one repo-owned supervisor script. OpenCode starts first and must pass a localhost health check before OpenChamber starts, while existing repo-managed preset syncing and persistent runtime directories continue to work inside the single container.

**Tech Stack:** Dockerfile multi-stage builds, Bun, OpenCode, OpenChamber, oh-my-opencode-slim, POSIX shell supervisor, Dokploy single-container deployment

---

## Planned File Structure

- **Create:** `Dockerfile.single-container`
  - Single source of truth image for Dokploy imperative deployment.
- **Create:** `scripts/single-container-entrypoint.sh`
  - Supervisor/startup script that prepares config, starts OpenCode, waits for health, then starts OpenChamber and forwards signals.
- **Modify:** `scripts/opencode-entrypoint.sh`
  - Reduce to reusable bootstrap/start command logic or extract shared setup so the single-container entrypoint can call it without duplicating config sync behavior.
- **Modify:** `scripts/openchamber-entrypoint-wrapper.sh`
  - Reduce to reusable OpenChamber start command logic or fold into the new single-container entrypoint.
- **Modify:** `README.md`
  - Replace Compose-first instructions with Dokploy single-container instructions.
- **Modify:** `.env.example`
  - Keep only variables relevant to single-container Dokploy deployment.
- **Modify:** `docs/superpowers/specs/2026-05-01-single-container-dokploy-design.md`
  - Only if tiny clarifications are needed while implementing; otherwise no change.
- **Deprecate/Retain temporarily:** `docker-compose.yml`, `Dockerfile.opencode`, `Dockerfile.openchamber`
  - Keep only if needed for local transition testing; final direction should clearly mark them as legacy or remove them.

---

### Task 1: Build the unified runtime image

**Files:**
- Create: `Dockerfile.single-container`
- Modify: `README.md:1-68`

- [ ] **Step 1: Write the failing verification command for the missing single-image path**

Run:

```bash
docker build -f Dockerfile.single-container .
```

Expected: FAIL with `failed to read dockerfile` because `Dockerfile.single-container` does not exist yet.

- [ ] **Step 2: Create the initial unified Dockerfile**

Create `Dockerfile.single-container` with this initial structure:

```dockerfile
# syntax=docker/dockerfile:1
FROM oven/bun:1 AS openchamber-deps
WORKDIR /app
COPY openchamber/package.json openchamber/bun.lock ./
COPY openchamber/packages/ui/package.json ./packages/ui/
COPY openchamber/packages/web/package.json ./packages/web/
COPY openchamber/packages/desktop/package.json ./packages/desktop/
COPY openchamber/packages/vscode/package.json ./packages/vscode/
COPY openchamber/packages/electron/package.json ./packages/electron/
RUN bun install --frozen-lockfile --ignore-scripts

FROM openchamber-deps AS openchamber-builder
WORKDIR /app
COPY openchamber/. .
RUN sed -i 's/const mdExists = !!mdPath;/const mdExists = !!mdPath \&\& fs.existsSync(mdPath);/' packages/web/server/lib/opencode/skills.js
RUN bun run build:web

FROM oven/bun:1 AS runtime
WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
  bash \
  ca-certificates \
  git \
  less \
  nodejs \
  npm \
  openssh-client \
  python3 \
  runit \
  && rm -rf /var/lib/apt/lists/*

RUN useradd -m -d /home/opencode -s /bin/bash opencode \
  && useradd -m -d /home/openchamber -s /bin/bash openchamber

ENV OPENCODE_HOME=/home/opencode
ENV OPENCHAMBER_HOME=/home/openchamber
ENV XDG_CONFIG_HOME=/home/opencode/.config
ENV XDG_DATA_HOME=/home/opencode/.local/share
ENV BUN_INSTALL=/home/opencode/.bun
ENV PATH=/home/opencode/.bun/bin:/home/openchamber/.npm-global/bin:${PATH}

RUN bun add -g opencode-ai && bunx oh-my-opencode-slim@latest install --no-tui
RUN npm config set prefix /home/openchamber/.npm-global && mkdir -p /home/openchamber/.npm-global && npm install -g opencode-ai

COPY config/oh-my-opencode-slim.jsonc /app/config/oh-my-opencode-slim.jsonc
COPY scripts/opencode-entrypoint.sh /usr/local/bin/opencode-bootstrap.sh
COPY scripts/openchamber-entrypoint-wrapper.sh /usr/local/bin/openchamber-bootstrap.sh
COPY scripts/single-container-entrypoint.sh /usr/local/bin/single-container-entrypoint.sh

COPY --from=openchamber-deps /app/node_modules /app/node_modules
COPY --from=openchamber-deps /app/packages/web/node_modules /app/packages/web/node_modules
COPY --from=openchamber-builder /app/package.json /app/package.json
COPY --from=openchamber-builder /app/packages/web/package.json /app/packages/web/package.json
COPY --from=openchamber-builder /app/packages/web/bin /app/packages/web/bin
COPY --from=openchamber-builder /app/packages/web/server /app/packages/web/server
COPY --from=openchamber-builder /app/packages/web/dist /app/packages/web/dist

RUN chmod +x /usr/local/bin/opencode-bootstrap.sh /usr/local/bin/openchamber-bootstrap.sh /usr/local/bin/single-container-entrypoint.sh \
  && mkdir -p /workspace /home/opencode/.config /home/opencode/.local/share /home/openchamber/.config /home/openchamber/.local /home/openchamber/.ssh \
  && chown -R opencode:opencode /workspace /home/opencode \
  && chown -R openchamber:openchamber /home/openchamber

EXPOSE 3000 4096

ENTRYPOINT ["/usr/local/bin/single-container-entrypoint.sh"]
```

- [ ] **Step 3: Run the build to verify the image structure is valid**

Run:

```bash
docker build -f Dockerfile.single-container .
```

Expected: PASS, producing a local image without Dockerfile syntax or missing-path failures.

- [ ] **Step 4: Commit the image scaffold**

Run:

```bash
git add Dockerfile.single-container
git commit -m "build: add single-container runtime image"
```

---

### Task 2: Add the single-container supervisor and localhost startup flow

**Files:**
- Create: `scripts/single-container-entrypoint.sh`
- Modify: `scripts/opencode-entrypoint.sh`
- Modify: `scripts/openchamber-entrypoint-wrapper.sh`

- [ ] **Step 1: Write the failing runtime verification command**

Run:

```bash
docker run --rm -e UI_PASSWORD=change-me -e OPENCODE_PORT=4096 $(docker build -q -f Dockerfile.single-container .)
```

Expected: FAIL because the unified entrypoint script does not exist yet or does not orchestrate both processes.

- [ ] **Step 2: Create the supervisor entrypoint**

Create `scripts/single-container-entrypoint.sh` with this exact initial logic:

```sh
#!/usr/bin/env sh
set -eu

OPENCODE_PORT="${OPENCODE_PORT:-4096}"
OPENCHAMBER_PORT="${OPENCHAMBER_PORT:-3000}"
OPENCODE_CONFIG_DIR="/home/opencode/.config/opencode"
OPENCHAMBER_CONFIG_DIR="/home/openchamber/.config/openchamber"

mkdir -p "$OPENCODE_CONFIG_DIR" /home/opencode/.local/share/opencode "$OPENCHAMBER_CONFIG_DIR/run" /workspace
chown -R opencode:opencode /home/opencode /workspace
chown -R openchamber:openchamber /home/openchamber /workspace

/usr/local/bin/opencode-bootstrap.sh > /tmp/opencode.log 2>&1 &
OPENCODE_PID=$!

cleanup() {
  kill "$OPENCODE_PID" 2>/dev/null || true
  kill "$OPENCHAMBER_PID" 2>/dev/null || true
  wait "$OPENCODE_PID" 2>/dev/null || true
  wait "$OPENCHAMBER_PID" 2>/dev/null || true
}

trap cleanup INT TERM EXIT

until su -s /bin/sh opencode -c "python3 -c \"import urllib.request; r=urllib.request.urlopen('http://127.0.0.1:${OPENCODE_PORT}/health', timeout=2); raise SystemExit(0 if r.status == 200 else 1)\""; do
  sleep 1
done

su -s /bin/sh openchamber -c "export OPENCHAMBER_UI_PASSWORD='${UI_PASSWORD:-}'; export OPENCHAMBER_DATA_DIR='${OPENCHAMBER_CONFIG_DIR}'; export OPENCHAMBER_HOST='0.0.0.0'; exec bun /app/packages/web/bin/cli.js serve --port ${OPENCHAMBER_PORT} --foreground" &
OPENCHAMBER_PID=$!

wait "$OPENCHAMBER_PID"
```

- [ ] **Step 3: Refactor the existing bootstrap scripts into reusable helpers**

Update `scripts/opencode-entrypoint.sh` so it becomes a reusable helper that bootstraps config and then `exec`s OpenCode only when called directly. The core body should follow this structure:

```sh
#!/usr/bin/env sh
set -eu

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
OPENCODE_CONFIG_DIR="$CONFIG_HOME/opencode"
PLUGIN_CONFIG_FILE="$OPENCODE_CONFIG_DIR/oh-my-opencode-slim.jsonc"
CONFIG_FILE="$OPENCODE_CONFIG_DIR/opencode.json"
REPO_PLUGIN_CONFIG_TEMPLATE="/app/config/oh-my-opencode-slim.jsonc"

mkdir -p "$OPENCODE_CONFIG_DIR" "$DATA_HOME/opencode" /workspace

if [ ! -f "$CONFIG_FILE" ]; then
  cat > "$CONFIG_FILE" <<'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "plugin": ["oh-my-opencode-slim"],
  "agent": {
    "explore": { "disable": true },
    "general": { "disable": true }
  },
  "lsp": true
}
EOF
fi

cp "$REPO_PLUGIN_CONFIG_TEMPLATE" "$PLUGIN_CONFIG_FILE"
command -v opencode >/dev/null 2>&1 || { echo "opencode binary not found" >&2; exit 1; }
bunx_output=$(bunx oh-my-opencode-slim --help 2>&1) || { echo "$bunx_output" >&2; exit 1; }

exec opencode serve --hostname 0.0.0.0 --port "${OPENCODE_PORT:-4096}"
```

Update `scripts/openchamber-entrypoint-wrapper.sh` so it is either removed from the runtime path or reduced to a small reusable helper comment block, but it must no longer be the container's main ENTRYPOINT.

- [ ] **Step 4: Run the runtime verification**

Run:

```bash
docker build -q -f Dockerfile.single-container . > /tmp/single-image-id.txt
docker run --rm -e UI_PASSWORD=change-me -e OPENCODE_PORT=4096 -p 3000:3000 "$(cat /tmp/single-image-id.txt)"
```

Expected: PASS, with logs showing OpenCode starts first, health wait completes, then OpenChamber starts.

- [ ] **Step 5: Commit the supervisor flow**

Run:

```bash
git add scripts/single-container-entrypoint.sh scripts/opencode-entrypoint.sh scripts/openchamber-entrypoint-wrapper.sh Dockerfile.single-container
git commit -m "feat: run opencode and openchamber in one container"
```

---

### Task 3: Replace Compose-oriented deployment docs and env contract

**Files:**
- Modify: `README.md`
- Modify: `.env.example`
- Modify: `docker-compose.yml`

- [ ] **Step 1: Write the failing contract check**

Run:

```bash
grep -nE 'docker compose|docker-compose|depends_on|opencode:' README.md docker-compose.yml .env.example
```

Expected: FAIL by showing Compose-oriented deployment guidance still exists.

- [ ] **Step 2: Update README for imperative Dokploy deployment**

Rewrite the deployment sections of `README.md` so they reflect this structure:

```md
## Deployment model

This stack is designed for Dokploy single-container deployment from one Dockerfile, not Docker Compose orchestration.

## Required environment variables

- `UI_PASSWORD`
- `OPENAI_API_KEY` / `ANTHROPIC_API_KEY` / `GOOGLE_API_KEY` as needed
- `OPENCODE_PORT` if overriding the default internal backend port

## Dokploy notes

- Deploy from `Dockerfile.single-container`
- Route public traffic to internal port `3000`
- Mount persistent storage for OpenCode config/data, OpenChamber config, and workspace
- The container starts OpenCode first, waits for health, then starts OpenChamber
```

- [ ] **Step 3: Update `.env.example` for single-container deployment**

Change `.env.example` to this exact baseline:

```dotenv
# Required: password for the OpenChamber web UI
UI_PASSWORD=change-me

# Optional: internal OpenCode port inside the container
OPENCODE_PORT=4096

# Optional: fill the providers you actually use
OPENAI_API_KEY=
ANTHROPIC_API_KEY=
GOOGLE_API_KEY=
```

- [ ] **Step 4: Deprecate Compose from the main path**

Replace `docker-compose.yml` contents with a deprecation stub that makes the transition explicit instead of leaving the old architecture silently authoritative:

```yaml
services: {}
```

and add a top comment block:

```yaml
# Deprecated: the active deployment model is Dokploy single-container deployment
# from Dockerfile.single-container. This file is intentionally no longer the
# primary deployment entrypoint.
```

- [ ] **Step 5: Run the documentation contract check again**

Run:

```bash
grep -nE 'Dockerfile.single-container|single-container|Route public traffic to internal port 3000' README.md .env.example docker-compose.yml
```

Expected: PASS, showing the new imperative deployment wording.

- [ ] **Step 6: Commit the deployment contract change**

Run:

```bash
git add README.md .env.example docker-compose.yml
git commit -m "docs: switch deployment guidance to single-container dokploy"
```

---

### Task 4: Verify the full single-container startup path

**Files:**
- Test: `Dockerfile.single-container`
- Test: `scripts/single-container-entrypoint.sh`
- Test: `README.md`
- Test: `.env.example`

- [ ] **Step 1: Write the failing end-to-end verification command**

Run:

```bash
docker build -f Dockerfile.single-container .
```

Expected before final fixes: FAIL at least once during implementation until all runtime paths align.

- [ ] **Step 2: Run the final image build**

Run:

```bash
docker build -t self-hosted-ai-dev-single -f Dockerfile.single-container .
```

Expected: PASS.

- [ ] **Step 3: Run the final local runtime test**

Run:

```bash
docker run --rm \
  -e UI_PASSWORD=change-me \
  -e OPENAI_API_KEY= \
  -e ANTHROPIC_API_KEY= \
  -e GOOGLE_API_KEY= \
  -e OPENCODE_PORT=4096 \
  -p 3000:3000 \
  self-hosted-ai-dev-single
```

Expected: logs show OpenCode healthy first, then OpenChamber starts, with no orphan/restart-loop behavior.

- [ ] **Step 4: Run live health probes against the running container**

Run in another shell:

```bash
curl -f http://127.0.0.1:3000/health
```

Expected: PASS with HTTP 200.

Run in the container shell:

```bash
python3 -c "import urllib.request; print(urllib.request.urlopen('http://127.0.0.1:4096/health').status)"
```

Expected: PASS printing `200`.

- [ ] **Step 5: Verify repo-managed preset sync still works**

Run:

```bash
docker exec "$(docker ps -q --filter ancestor=self-hosted-ai-dev-single | head -n1)" sh -lc 'grep -n "preset" /home/opencode/.config/opencode/oh-my-opencode-slim.jsonc'
```

Expected: PASS with the repo-managed preset visible in the runtime config path.

- [ ] **Step 6: Commit the final architecture transition**

Run:

```bash
git add Dockerfile.single-container scripts/single-container-entrypoint.sh scripts/opencode-entrypoint.sh scripts/openchamber-entrypoint-wrapper.sh README.md .env.example docker-compose.yml
git commit -m "feat: move dokploy deployment to single-container runtime"
```

---

## Self-Review

### Spec Coverage

- Single Dockerfile deployment: covered by Tasks 1 and 4
- Single-container runtime with both products: covered by Tasks 1 and 2
- OpenCode-first readiness sequencing: covered by Tasks 2 and 4
- Persistent filesystem separation with same-container locality: covered by Tasks 2 and 3
- Repo-authoritative preset sync retained: covered by Tasks 2 and 4
- Dokploy imperative deployment docs: covered by Task 3

No spec gaps found.

### Placeholder Scan

- No `TBD`
- No `TODO`
- No “implement later” markers
- All steps contain concrete commands or code blocks

### Type / Naming Consistency

- New Dockerfile name is consistently `Dockerfile.single-container`
- Supervisor script is consistently `scripts/single-container-entrypoint.sh`
- Runtime health target is consistently OpenCode on `127.0.0.1:${OPENCODE_PORT:-4096}`
- Public service target is consistently OpenChamber on internal port `3000`
