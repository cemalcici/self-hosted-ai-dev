# Single-Container Compose Persistence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore `docker-compose.yml` as the primary Dokploy deployment contract while keeping the current single-container runtime so persistence is explicitly declared and restart-safe.

**Architecture:** Keep one image built from the root `Dockerfile` and one container running both OpenCode and OpenChamber. Reintroduce Compose only as the deployment/persistence contract: one service, four persistent mounts, single-container env contract, and docs that direct operators to deploy through Compose instead of imperative Dockerfile-only mode.

**Tech Stack:** Docker Compose, Dokploy, OpenCode, OpenChamber, oh-my-opencode-slim, shell entrypoint scripts, Markdown docs

---

## File Structure

- Create: `docker-compose.yml` — canonical single-service Dokploy deployment contract with explicit persistent mounts
- Modify: `.env.example` — compose-first single-container env contract
- Modify: `README.md` — operator flow changes from imperative Dockerfile deploy to compose-first deployment
- Verify only: `Dockerfile`, `scripts/single-container-entrypoint.sh` — confirm the single-container runtime assumptions still match the new Compose contract without changing runtime behavior unless strictly necessary

---

### Task 1: Restore a real single-service docker-compose contract

**Files:**
- Create: `docker-compose.yml`
- Verify: `Dockerfile`

- [ ] **Step 1: Write the failing contract check**

Run:

```bash
test -f docker-compose.yml && python3 - <<'PY'
from pathlib import Path
text = Path('docker-compose.yml').read_text()
required = ['services:', 'volumes:', '/home/opencode/.config/opencode', '/home/opencode/.local/share/opencode', '/home/openchamber/.config/openchamber', '/workspace']
missing = [item for item in required if item not in text]
raise SystemExit(0 if not missing else 1)
PY
```

Expected: FAIL because the current repo does not yet have a real compose contract with the required persistence paths.

- [ ] **Step 2: Create the single-service compose file**

Write `docker-compose.yml` with one service built from the root `Dockerfile`, the current env contract, and four named volume mounts:

```yaml
services:
  aidev:
    build:
      context: .
      dockerfile: Dockerfile
    environment:
      UI_PASSWORD: ${UI_PASSWORD}
      OPENCODE_PORT: ${OPENCODE_PORT}
      OPENCHAMBER_PORT: ${OPENCHAMBER_PORT}
      OPENAI_API_KEY: ${OPENAI_API_KEY}
      ANTHROPIC_API_KEY: ${ANTHROPIC_API_KEY}
      GOOGLE_API_KEY: ${GOOGLE_API_KEY}
    volumes:
      - opencode_config:/home/opencode/.config/opencode
      - opencode_data:/home/opencode/.local/share/opencode
      - openchamber_config:/home/openchamber/.config/openchamber
      - workspace:/workspace

volumes:
  opencode_config:
  opencode_data:
  openchamber_config:
  workspace:
```

Keep this intentionally single-service. Do not reintroduce separate `opencode` / `openchamber` services.

- [ ] **Step 3: Run compose validation**

Run:

```bash
docker compose config
```

Expected: PASS with one rendered service and four declared volumes.

- [ ] **Step 4: Commit the compose contract**

```bash
git add docker-compose.yml
git commit -m "build: restore single-service compose deployment contract"
```

---

### Task 2: Align env contract and operator docs to compose-first deployment

**Files:**
- Modify: `.env.example`
- Modify: `README.md`

- [ ] **Step 1: Write the failing doc/env check**

Run:

```bash
python3 - <<'PY'
from pathlib import Path
env_text = Path('.env.example').read_text()
readme_text = Path('README.md').read_text()
checks = [
    'docker compose up --build -d' in readme_text,
    'Mount persistent storage' in readme_text,
    'docker-compose.yml' in readme_text,
    'UI_PASSWORD=' in env_text,
    'OPENCODE_PORT=' in env_text,
    'OPENCHAMBER_PORT=' in env_text,
]
raise SystemExit(0 if all(checks) else 1)
PY
```

Expected: FAIL because the current docs still present the imperative Dockerfile deployment as primary.

- [ ] **Step 2: Update `.env.example` for compose-first usage**

Keep only the single-container variables and make the comments Compose/Dokploy oriented:

```dotenv
# Required: password for the OpenChamber web UI
UI_PASSWORD=change-me

# Optional: internal OpenCode health-check and serve port inside the container
OPENCODE_PORT=4096

# Optional: internal OpenChamber listen port inside the container
OPENCHAMBER_PORT=3000

# Optional: fill the providers you actually use
OPENAI_API_KEY=
ANTHROPIC_API_KEY=
GOOGLE_API_KEY=
```

Do not reintroduce `OPENCODE_HOST` or `OPENCODE_SKIP_START`.

- [ ] **Step 3: Rewrite README deployment flow to compose-first**

Update `README.md` so the primary operator flow becomes:

```md
## Primary deployment

Deploy through `docker-compose.yml` — the canonical Dokploy deployment contract for the single-container runtime.

```bash
git submodule update --init
cp .env.example .env
docker compose up --build -d
```

## Dokploy notes

- Deploy the repo as a Compose project.
- Build from the root `Dockerfile` via `docker-compose.yml`.
- Route public traffic to internal port `3000` (OpenChamber).
- Attach persistent storage for:
  - `/home/opencode/.config/opencode`
  - `/home/opencode/.local/share/opencode`
  - `/home/openchamber/.config/openchamber`
  - `/workspace`
```

Also explicitly explain that missing these mounts causes loss of sessions, provider credentials, runtime config, and workspace state across restarts.

- [ ] **Step 4: Run doc/env verification**

Run:

```bash
python3 - <<'PY'
from pathlib import Path
env_text = Path('.env.example').read_text()
readme_text = Path('README.md').read_text()
assert 'OPENCODE_HOST' not in env_text
assert 'OPENCODE_SKIP_START' not in env_text
assert 'docker compose up --build -d' in readme_text
assert '/home/opencode/.config/opencode' in readme_text
assert '/home/opencode/.local/share/opencode' in readme_text
assert '/home/openchamber/.config/openchamber' in readme_text
assert '/workspace' in readme_text
print('docs-ok')
PY
```

Expected: PASS printing `docs-ok`.

- [ ] **Step 5: Commit the doc/env alignment**

```bash
git add .env.example README.md
git commit -m "docs: make compose the primary single-container deployment path"
```

---

### Task 3: Verify persistence-oriented compose startup end to end

**Files:**
- Verify: `docker-compose.yml`
- Verify: `Dockerfile`
- Verify: `scripts/single-container-entrypoint.sh`

- [ ] **Step 1: Write the failing runtime test**

Run:

```bash
docker compose down -v && docker compose up -d && sleep 5 && docker compose ps
```

Expected: before the fix, this path is either impossible or not aligned with the intended compose-first persistence contract.

- [ ] **Step 2: Run the final startup verification**

Run:

```bash
docker compose down -v && docker compose up --build -d && sleep 35 && docker compose ps && docker compose exec aidev python3 -c "import urllib.request; print('OG', urllib.request.urlopen('http://127.0.0.1:4096/global/health', timeout=5).status); print('CH', urllib.request.urlopen('http://127.0.0.1:3000/health', timeout=5).status)"
```

Expected:
- service `aidev` is Up
- OpenCode `/global/health` returns `200`
- OpenChamber `/health` returns `200`

- [ ] **Step 3: Verify the compose file mounts the required persistence paths**

Run:

```bash
docker compose exec aidev sh -lc 'mount | grep -E "/home/opencode/.config/opencode|/home/opencode/.local/share/opencode|/home/openchamber/.config/openchamber|/workspace"'
```

Expected: output includes all four target paths.

- [ ] **Step 4: Verify restart preserves runtime state**

Run:

```bash
docker compose exec aidev sh -lc 'test -f /home/opencode/.config/opencode/oh-my-opencode-slim.jsonc && test -d /home/openchamber/.config/openchamber && test -d /workspace' && docker compose restart aidev && sleep 20 && docker compose exec aidev sh -lc 'test -f /home/opencode/.config/opencode/oh-my-opencode-slim.jsonc && test -d /home/openchamber/.config/openchamber && test -d /workspace'
```

Expected: PASS both before and after restart.

- [ ] **Step 5: Commit verification-only follow-up if docs or config needed small correction**

If no files change, do **not** create an empty commit. If verification requires a small real follow-up, commit only that delta:

```bash
git add <affected-files>
git commit -m "test: verify compose-first single-container persistence"
```

---

## Self-Review

- Spec coverage:
  - real `docker-compose.yml` again → Task 1
  - single service only → Task 1
  - four persistent paths mounted → Task 1 + Task 3
  - build from root `Dockerfile` → Task 1 + Task 3
  - compose-first docs/env → Task 2
  - restart-safe persistence contract → Task 3
- Placeholder scan: no TBD/TODO markers, all commands and file paths explicit
- Type/term consistency: consistently uses `aidev` as the single compose service name, `Dockerfile` as canonical image definition, and the four required mount paths exactly as named in the approved spec
