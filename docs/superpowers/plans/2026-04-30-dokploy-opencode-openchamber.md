# Dokploy OpenCode + OpenChamber Stack Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Dokploy-ready Docker Compose stack that runs OpenChamber against an OpenCode backend with oh-my-opencode-slim preinstalled, shared workspace storage, and `.env.example`-driven configuration.

**Architecture:** The stack uses two services in one `docker-compose.yml`: a custom-built `opencode` service and a separate `openchamber` service. OpenChamber connects to OpenCode over the compose network, both services share a workspace volume, and runtime secrets stay outside the images via environment variables.

**Tech Stack:** Docker Compose, Dockerfile, shell entrypoint/bootstrap scripts, OpenCode, oh-my-opencode-slim, OpenChamber, Dokploy

---

## File Structure Map

### Files to create

- `docker-compose.yml` — defines the two-service stack, shared volumes, env wiring, and startup behavior.
- `Dockerfile.opencode` — builds the custom OpenCode image with oh-my-opencode-slim preinstalled.
- `scripts/opencode-entrypoint.sh` — bootstraps config/plugins safely, then starts OpenCode.
- `.env.example` — lists all required and optional environment variables for Dokploy.
- `README.md` — explains local use, Dokploy deployment expectations, and required environment variables.

### Files to verify during implementation

- `docs/superpowers/specs/2026-04-30-dokploy-opencode-openchamber-design.md` — source of truth for requirements.

### Testing strategy

- Use `docker compose config` as the first structural validation.
- Use `docker compose build opencode` to verify the custom image builds.
- Use `docker compose up` smoke tests to verify service-to-service connectivity.
- Use runtime checks inside containers to verify plugin installation and shared workspace visibility.

## Task 1: Create the environment contract and compose skeleton

**Files:**
- Create: `.env.example`
- Create: `docker-compose.yml`
- Test: `docker compose config`

- [ ] **Step 1: Write the failing compose validation inputs**

Create `.env.example` with the exact variables the stack will require:

```dotenv
# OpenChamber
UI_PASSWORD=change-me
OPENCODE_HOST=http://opencode:4096
OPENCODE_SKIP_START=true

# OpenCode
OPENCODE_SERVER_PASSWORD=change-me-too
OPENCODE_SERVER_USERNAME=admin

# LLM providers (fill only what you use)
OPENAI_API_KEY=
ANTHROPIC_API_KEY=
GOOGLE_API_KEY=

# Image/runtime knobs
OPENCHAMBER_IMAGE=ghcr.io/openchamber/openchamber:main
OPENCODE_PORT=4096
OPENCHAMBER_PORT=3000
```

Create an initial `docker-compose.yml` that references the variables but intentionally omits the `opencode` build context to force the first validation failure:

```yaml
services:
  opencode:
    build:
      dockerfile: Dockerfile.opencode
    env_file:
      - .env
    environment:
      OPENCODE_SERVER_PASSWORD: ${OPENCODE_SERVER_PASSWORD}
      OPENCODE_SERVER_USERNAME: ${OPENCODE_SERVER_USERNAME}
      OPENAI_API_KEY: ${OPENAI_API_KEY}
      ANTHROPIC_API_KEY: ${ANTHROPIC_API_KEY}
      GOOGLE_API_KEY: ${GOOGLE_API_KEY}
      OPENCODE_PORT: ${OPENCODE_PORT}
    volumes:
      - opencode_config:/home/opencode/.config/opencode
      - opencode_data:/home/opencode/.local/share/opencode
      - workspace:/workspace

  openchamber:
    image: ${OPENCHAMBER_IMAGE}
    env_file:
      - .env
    environment:
      UI_PASSWORD: ${UI_PASSWORD}
      OPENCODE_HOST: ${OPENCODE_HOST}
      OPENCODE_SKIP_START: ${OPENCODE_SKIP_START}
    depends_on:
      - opencode
    ports:
      - "${OPENCHAMBER_PORT}:3000"
    volumes:
      - openchamber_config:/home/openchamber/.config/openchamber
      - workspace:/workspace

volumes:
  opencode_config:
  opencode_data:
  openchamber_config:
  workspace:
```

- [ ] **Step 2: Run validation and confirm it fails for the expected reason**

Run:

```bash
cp .env.example .env && docker compose config
```

Expected: FAIL or invalid output because `build.context` is missing for `opencode`.

- [ ] **Step 3: Write the minimal valid compose skeleton**

Replace `docker-compose.yml` with this valid version:

```yaml
services:
  opencode:
    build:
      context: .
      dockerfile: Dockerfile.opencode
    env_file:
      - .env
    environment:
      OPENCODE_SERVER_PASSWORD: ${OPENCODE_SERVER_PASSWORD}
      OPENCODE_SERVER_USERNAME: ${OPENCODE_SERVER_USERNAME}
      OPENAI_API_KEY: ${OPENAI_API_KEY}
      ANTHROPIC_API_KEY: ${ANTHROPIC_API_KEY}
      GOOGLE_API_KEY: ${GOOGLE_API_KEY}
      OPENCODE_PORT: ${OPENCODE_PORT}
    volumes:
      - opencode_config:/home/opencode/.config/opencode
      - opencode_data:/home/opencode/.local/share/opencode
      - workspace:/workspace

  openchamber:
    image: ${OPENCHAMBER_IMAGE}
    env_file:
      - .env
    environment:
      UI_PASSWORD: ${UI_PASSWORD}
      OPENCODE_HOST: ${OPENCODE_HOST}
      OPENCODE_SKIP_START: ${OPENCODE_SKIP_START}
    depends_on:
      - opencode
    ports:
      - "${OPENCHAMBER_PORT}:3000"
    volumes:
      - openchamber_config:/home/openchamber/.config/openchamber
      - workspace:/workspace

volumes:
  opencode_config:
  opencode_data:
  openchamber_config:
  workspace:
```

- [ ] **Step 4: Run validation and confirm the compose file is structurally correct**

Run:

```bash
docker compose config
```

Expected: PASS with rendered YAML output for both services and all four volumes.

- [ ] **Step 5: Commit**

```bash
git add .env.example docker-compose.yml
git commit -m "chore: add initial compose and env contract"
```

## Task 2: Build the custom OpenCode image with plugin preinstalled

**Files:**
- Create: `Dockerfile.opencode`
- Test: `docker compose build opencode`

- [ ] **Step 1: Write the failing image definition**

Create `Dockerfile.opencode` with an intentionally incomplete image that does not install the plugin yet. Note: the installable Bun package is `opencode-ai`, while the runtime binary remains `opencode`:

```dockerfile
FROM oven/bun:1

WORKDIR /app

RUN bun add -g opencode-ai

CMD ["opencode", "serve", "--hostname", "0.0.0.0", "--port", "4096"]
```

- [ ] **Step 2: Build the image and verify the plugin is missing**

Run:

```bash
docker compose build opencode && docker run --rm $(docker images -q $(basename "$PWD")-opencode | head -n 1) sh -lc 'bunx oh-my-opencode-slim@latest --help >/dev/null 2>&1; test -d /root/.bun/install/cache'
```

Expected: FAIL or insufficient evidence that `oh-my-opencode-slim` is preinstalled in the image.

- [ ] **Step 3: Write the minimal image that installs both OpenCode and oh-my-opencode-slim**

Replace `Dockerfile.opencode` with:

```dockerfile
FROM oven/bun:1

ENV HOME=/home/opencode
ENV XDG_CONFIG_HOME=/home/opencode/.config
ENV XDG_DATA_HOME=/home/opencode/.local/share
ENV PATH="/home/opencode/.bun/bin:${PATH}"

RUN useradd -m -d /home/opencode -s /bin/bash opencode

WORKDIR /app

RUN bun add -g opencode-ai oh-my-opencode-slim@latest

COPY scripts/opencode-entrypoint.sh /usr/local/bin/opencode-entrypoint.sh
RUN chmod +x /usr/local/bin/opencode-entrypoint.sh && mkdir -p /workspace /home/opencode/.config /home/opencode/.local/share && chown -R opencode:opencode /workspace /home/opencode

USER opencode
WORKDIR /workspace

ENTRYPOINT ["/usr/local/bin/opencode-entrypoint.sh"]
```

- [ ] **Step 4: Build the image and verify the plugin install layer succeeds**

Run:

```bash
docker compose build opencode
```

Expected: PASS with a completed `opencode` image build.

- [ ] **Step 5: Commit**

```bash
git add Dockerfile.opencode
git commit -m "build: add custom opencode image"
```

## Task 3: Add safe OpenCode bootstrap behavior

**Files:**
- Create: `scripts/opencode-entrypoint.sh`
- Modify: `docker-compose.yml`
- Test: `docker compose up opencode`

- [ ] **Step 1: Write the failing bootstrap script**

Create `scripts/opencode-entrypoint.sh` with a minimal startup that does not yet prepare config:

```bash
#!/usr/bin/env sh
set -eu

exec opencode serve --hostname 0.0.0.0 --port "${OPENCODE_PORT:-4096}"
```

- [ ] **Step 2: Start the backend and verify bootstrap behavior is incomplete**

Run:

```bash
docker compose up --build opencode
```

Expected: The service may start, but there is no guaranteed plugin/config bootstrap and no protection against missing config directories.

- [ ] **Step 3: Write the bootstrap script that prepares directories, preserves user state, and wires the plugin**

Replace `scripts/opencode-entrypoint.sh` with:

```bash
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

if ! command -v opencode >/dev/null 2>&1; then
  echo "opencode binary not found" >&2
  exit 1
fi

if ! command -v oh-my-opencode-slim >/dev/null 2>&1; then
  echo "oh-my-opencode-slim binary not found" >&2
  exit 1
fi

exec opencode serve --hostname 0.0.0.0 --port "${OPENCODE_PORT:-4096}"
```

- [ ] **Step 4: Wire the script into the service and verify backend startup**

Ensure `docker-compose.yml` keeps the `opencode` service on the custom image and does not override the image entrypoint. Then run:

```bash
docker compose up --build -d opencode && docker compose logs opencode --tail=50
```

Expected: PASS with logs showing OpenCode listening on port `4096` and no bootstrap failure.

- [ ] **Step 5: Commit**

```bash
git add scripts/opencode-entrypoint.sh docker-compose.yml Dockerfile.opencode
git commit -m "feat: bootstrap opencode with slim plugin"
```

## Task 4: Configure OpenChamber to use the external OpenCode backend and shared workspace

**Files:**
- Modify: `docker-compose.yml`
- Test: `docker compose up`

- [ ] **Step 1: Write the failing OpenChamber service configuration**

Temporarily remove the external backend wiring from `openchamber` in `docker-compose.yml` so the test captures the wrong behavior:

```yaml
  openchamber:
    image: ${OPENCHAMBER_IMAGE}
    env_file:
      - .env
    environment:
      UI_PASSWORD: ${UI_PASSWORD}
    depends_on:
      - opencode
    ports:
      - "${OPENCHAMBER_PORT}:3000"
    volumes:
      - openchamber_config:/home/openchamber/.config/openchamber
      - workspace:/workspace
```

- [ ] **Step 2: Start the full stack and verify the backend wiring is wrong**

Run:

```bash
docker compose up --build -d && docker compose logs openchamber --tail=100
```

Expected: FAIL or incorrect runtime behavior because OpenChamber is not explicitly pointed at `http://opencode:4096` and may try to start or assume its own backend.

- [ ] **Step 3: Write the correct OpenChamber service definition**

Update the `openchamber` service in `docker-compose.yml` to:

```yaml
  openchamber:
    image: ${OPENCHAMBER_IMAGE}
    env_file:
      - .env
    environment:
      UI_PASSWORD: ${UI_PASSWORD}
      OPENCODE_HOST: ${OPENCODE_HOST}
      OPENCODE_SKIP_START: ${OPENCODE_SKIP_START}
    depends_on:
      - opencode
    ports:
      - "${OPENCHAMBER_PORT}:3000"
    volumes:
      - openchamber_config:/home/openchamber/.config/openchamber
      - workspace:/workspace
```

- [ ] **Step 4: Start the full stack and verify service-to-service connectivity**

Run:

```bash
docker compose up --build -d && docker compose ps && docker compose logs openchamber --tail=50 && docker compose exec openchamber sh -lc 'ls -la /workspace'
```

Expected: PASS with both services running and `/workspace` visible inside `openchamber`.

- [ ] **Step 5: Commit**

```bash
git add docker-compose.yml
git commit -m "feat: connect openchamber to external opencode"
```

## Task 5: Add operator documentation and Dokploy deployment guidance

**Files:**
- Create: `README.md`
- Modify: `.env.example`
- Test: `docker compose config && docker compose up --build -d`

- [ ] **Step 1: Write the failing documentation skeleton**

Create `README.md` with only a heading so the documentation gap is explicit:

```markdown
# Dokploy OpenCode Stack
```

- [ ] **Step 2: Review the repo and confirm the documentation is insufficient**

Run:

```bash
grep -n "Dokploy\|GitHub\|workspace\|.env.example" README.md
```

Expected: FAIL or incomplete output because the README does not yet explain deployment or runtime behavior.

- [ ] **Step 3: Write the minimal complete operator documentation**

Replace `README.md` with:

```markdown
# Dokploy OpenCode Stack

This repository provides a Dokploy-ready Docker Compose stack for:

- OpenCode
- oh-my-opencode-slim
- OpenChamber

## Services

- `opencode`: custom-built backend image with `oh-my-opencode-slim` preinstalled
- `openchamber`: web UI connected to the `opencode` service

## Required environment variables

Copy `.env.example` to `.env` for local validation. In Dokploy, define the same variables in the project environment UI.

Key variables:

- `UI_PASSWORD`
- `OPENCODE_SERVER_PASSWORD`
- `OPENCODE_HOST`
- `OPENCODE_SKIP_START`
- one or more provider API keys such as `OPENAI_API_KEY` or `ANTHROPIC_API_KEY`

## Local smoke test

```bash
cp .env.example .env
docker compose config
docker compose up --build -d
docker compose ps
```

OpenChamber is exposed on port `3000` by default.

## Dokploy notes

- Deploy the repository as a Docker Compose project.
- Let Dokploy manage public routing and domains.
- Attach persistent volumes for OpenCode config/data, OpenChamber config, and the shared workspace.
- Use the OpenChamber UI to connect GitHub and clone repositories into the shared workspace.

## Shared workspace

Both services mount the same `/workspace` volume. Repositories cloned through OpenChamber should appear there and be available to OpenCode.
```

Update `.env.example` comments to clearly mark required vs optional values:

```dotenv
# Required: password for the OpenChamber web UI
UI_PASSWORD=change-me

# Required: OpenChamber must target the opencode service inside compose
OPENCODE_HOST=http://opencode:4096

# Required: keep OpenChamber from launching its own embedded backend
OPENCODE_SKIP_START=true

# Required: password for the OpenCode backend
OPENCODE_SERVER_PASSWORD=change-me-too

# Optional: backend username
OPENCODE_SERVER_USERNAME=admin

# Optional: fill the providers you actually use
OPENAI_API_KEY=
ANTHROPIC_API_KEY=
GOOGLE_API_KEY=

# Optional image/runtime knobs
OPENCHAMBER_IMAGE=ghcr.io/openchamber/openchamber:main
OPENCODE_PORT=4096
OPENCHAMBER_PORT=3000
```

- [ ] **Step 4: Run the final smoke checks**

Run:

```bash
docker compose config && docker compose up --build -d && docker compose ps
```

Expected: PASS with rendered config, successful startup, and both services in running state.

- [ ] **Step 5: Commit**

```bash
git add README.md .env.example docker-compose.yml Dockerfile.opencode scripts/opencode-entrypoint.sh
git commit -m "docs: add dokploy deployment guide"
```

## Task 6: Run end-to-end verification for plugin install, shared workspace, and persistence

**Files:**
- Modify: `README.md` (only if verification reveals missing operator guidance)
- Test: runtime verification commands only

- [ ] **Step 1: Verify the plugin binary exists in the OpenCode container**

Run:

```bash
docker compose exec opencode sh -lc 'command -v opencode && command -v oh-my-opencode-slim'
```

Expected: PASS with paths for both binaries.

- [ ] **Step 2: Verify the shared workspace is actually shared**

Run:

```bash
docker compose exec openchamber sh -lc 'mkdir -p /workspace/smoke && echo ok >/workspace/smoke/check.txt' && docker compose exec opencode sh -lc 'cat /workspace/smoke/check.txt'
```

Expected: PASS with output `ok` from the `opencode` container.

- [ ] **Step 3: Verify config persistence assumptions with a restart**

Run:

```bash
docker compose restart opencode openchamber && docker compose exec opencode sh -lc 'test -f "$XDG_CONFIG_HOME/opencode/opencode.json"' && docker compose exec openchamber sh -lc 'test -d /workspace'
```

Expected: PASS with zero exit status from all commands.

- [ ] **Step 4: Record any missing operational detail and patch the README if needed**

If verification showed an operator gap, append the missing note to `README.md` using this exact section shape:

```markdown
## Verification notes

- Confirm `oh-my-opencode-slim` is available inside the `opencode` container with `command -v oh-my-opencode-slim`.
- Confirm both services can read `/workspace` before using GitHub clone workflows.
```

If no documentation gap is found, leave `README.md` unchanged.

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "test: verify container integration"
```

## Self-Review Checklist

- Spec coverage confirmed for: two-service compose, custom OpenCode image, preinstalled plugin, external OpenChamber backend wiring, shared workspace, `.env.example`, Dokploy-friendly deployment, and GitHub-via-UI workflow.
- Placeholder scan completed: no unresolved placeholders or unnamed files/commands remain.
- Type and naming consistency checked across `docker-compose.yml`, `Dockerfile.opencode`, `.env.example`, `README.md`, and `scripts/opencode-entrypoint.sh`.

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-04-30-dokploy-opencode-openchamber.md`. Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**
