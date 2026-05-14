# Hybrid Preset Bind-Mount Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `oh-my-opencode-slim` preset repo-managed again via a single-file bind mount while keeping the rest of `/home/aidev/.config/opencode` runtime-managed and persistent.

**Architecture:** Keep the directory-level bind mount `./data/opencode/config:/home/aidev/.config/opencode`, then add a second file-level bind mount for `./config/oh-my-opencode-slim.jsonc` onto `/home/aidev/.config/opencode/oh-my-opencode-slim.jsonc`. The plugin will prefer `.jsonc`, while all sibling runtime files (`opencode.json`, `skills/`, `agents/`, `node_modules/`) continue to live in the persistent `./data/opencode/config` directory.

**Tech Stack:** Docker Compose, Dockerfile, POSIX shell entrypoints, Python regression checks, Markdown docs.

---

## File Structure

- **Create:** `config/oh-my-opencode-slim.jsonc` — repo-managed preset file that operators edit frequently.
- **Modify:** `docker-compose.yml` — add one file-level bind mount for the preset.
- **Modify:** `README.md` — document the new preset workflow: edit on host, restart container.
- **Modify:** `AGENTS.md` — describe the hybrid model clearly so future changes do not remove it accidentally.
- **Modify:** `tests/runtime_user_regression.py` — add regression coverage that the preset file exists in repo and compose mounts it as `.jsonc` while preserving runtime-managed directory persistence.

### Task 1: Capture the hybrid contract in a failing regression test

**Files:**
- Modify: `tests/runtime_user_regression.py`
- Test: `tests/runtime_user_regression.py`

- [ ] **Step 1: Write the failing test**

Add these tests to `tests/runtime_user_regression.py`:

```python
def test_repo_managed_preset_exists_as_jsonc() -> None:
    assert exists("config/oh-my-opencode-slim.jsonc"), (
        "The hybrid model requires a repo-managed .jsonc preset file"
    )


def test_compose_bind_mounts_repo_preset_file() -> None:
    compose = read("docker-compose.yml")
    assert "./config/oh-my-opencode-slim.jsonc:/home/aidev/.config/opencode/oh-my-opencode-slim.jsonc" in compose, (
        "Compose must bind-mount the repo-managed preset file into the runtime config directory"
    )
```

Also remove or replace any prior assertions that required the repo preset file to be absent.

- [ ] **Step 2: Run the test to verify it fails**

Run: `python3 tests/runtime_user_regression.py`

Expected: FAIL because the repo preset file does not exist yet and compose does not mount it.

- [ ] **Step 3: Do not touch production files yet**

Stay in red state until the test failure is confirmed.

### Task 2: Restore the repo-managed preset file and bind mount

**Files:**
- Create: `config/oh-my-opencode-slim.jsonc`
- Modify: `docker-compose.yml`
- Test: `tests/runtime_user_regression.py`

- [ ] **Step 1: Restore the preset file in the repo**

Create `config/oh-my-opencode-slim.jsonc` with this content:

```jsonc
{
  "preset": "cmlops",
  "presets": {
    "cmlops": {
      "orchestrator": { "model": "openai/gpt-5.4-fast", "skills": ["*"], "mcps": ["*", "!context7"] },
      "oracle": { "model": "minimax-coding-plan/MiniMax-M2.7", "variant": "high", "skills": ["simplify"], "mcps": [] },
      "librarian": { "model": "minimax-coding-plan/MiniMax-M2.7", "variant": "low", "skills": [], "mcps": ["websearch", "context7", "grep_app"] },
      "explorer": { "model": "opencode-go/qwen3.6-plus", "variant": "low", "skills": [], "mcps": [] },
      "designer": { "model": "opencode-go/kimi-k2.6", "skills": ["agent-browser"], "mcps": [] },
      "fixer": { "model": "minimax-coding-plan/MiniMax-M2.7", "variant": "low", "skills": [], "mcps": [] }
    }
  },
  "council": {
    "master": { "model": "openai/gpt-5.4" },
    "presets": {
      "default": {
        "alpha": { "model": "opencode-go/kimi-k2.6" },
        "beta": { "model": "opencode-go/minimax-m2.7" },
        "gamma": { "model": "opencode-go/qwen3.6-plus" }
      }
    }
  },
  "showStartupToast": true,
  "disabled_mcps": []
}
```

- [ ] **Step 2: Add the file-level bind mount to compose**

Update `docker-compose.yml` so `volumes:` becomes:

```yaml
    volumes:
      - ./data/opencode/config:/home/aidev/.config/opencode
      - ./data/opencode/share:/home/aidev/.local/share/opencode
      - ./data/openchamber:/home/aidev/.config/openchamber
      - ./data/workspace:/workspace
      - ./data/ssh:/home/aidev/.ssh
      - ./config/oh-my-opencode-slim.jsonc:/home/aidev/.config/opencode/oh-my-opencode-slim.jsonc
```

- [ ] **Step 3: Run the regression test**

Run: `python3 tests/runtime_user_regression.py`

Expected: PASS.

### Task 3: Rewrite docs for the hybrid preset workflow

**Files:**
- Modify: `README.md`
- Modify: `AGENTS.md`
- Test: `README.md`, `AGENTS.md`

- [ ] **Step 1: Update README preset editing instructions**

Replace the current in-container edit instructions with host-side editing instructions:

```md
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
```

Keep the surrounding operator workflow sections intact.

- [ ] **Step 2: Update AGENTS.md persistence wording**

Add one explicit note under persistence rules:

```md
Hybrid preset rule:
- `./config/oh-my-opencode-slim.jsonc` is bind-mounted to `/home/aidev/.config/opencode/oh-my-opencode-slim.jsonc`
- this preset file is repo-managed on purpose because operators frequently edit it
- other files under `/home/aidev/.config/opencode` remain runtime-managed via `./data/opencode/config`
```

- [ ] **Step 3: Remove conflicting text**

Delete any sentence claiming there is *no* repo-managed source of truth for config at runtime. Narrow that claim so it excludes the preset file.

- [ ] **Step 4: Run a text sanity check**

Run:

```bash
python3 tests/runtime_user_regression.py
```

Expected: PASS.

### Task 4: Verify the hybrid mount does not damage sibling runtime files

**Files:**
- Test: live container runtime only

- [ ] **Step 1: Render compose config**

Run: `docker compose config`

Expected: both the directory-level bind mount and the file-level preset bind mount appear.

- [ ] **Step 2: Build and start the stack**

Run:

```bash
git submodule update --init
docker compose up --build -d
docker compose ps
```

Expected: service is `Up`.

- [ ] **Step 3: Verify the mounted preset file exists in-container**

Run:

```bash
docker compose exec -u aidev aidev sh -lc 'ls -l /home/aidev/.config/opencode/oh-my-opencode-slim.jsonc && sed -n "1,20p" /home/aidev/.config/opencode/oh-my-opencode-slim.jsonc'
```

Expected: file exists and contents match the repo-managed `.jsonc` file.

- [ ] **Step 4: Verify sibling runtime files still work**

Run:

```bash
docker compose exec -u aidev aidev sh -lc 'ls -la /home/aidev/.config/opencode && test -f /home/aidev/.config/opencode/opencode.json && test -d /home/aidev/.config/opencode/skills'
```

Expected: `opencode.json` and `skills/` still exist alongside the bind-mounted preset file.

- [ ] **Step 5: Verify health**

Run:

```bash
docker compose exec -u root aidev python3 -c "import urllib.request; print(urllib.request.urlopen('http://127.0.0.1:4096/global/health').status)"
docker compose exec -u root aidev python3 -c "import urllib.request; print(urllib.request.urlopen('http://127.0.0.1:3000/health').status)"
```

Expected: both print `200`.

- [ ] **Step 6: Verify operator edit flow**

Run:

```bash
python3 - <<'PY'
from pathlib import Path
p = Path('config/oh-my-opencode-slim.jsonc')
text = p.read_text()
marker = "// HYBRID_PRESET_CHECK\n"
if marker not in text:
    p.write_text(marker + text)
PY
docker compose restart aidev
docker compose exec -u aidev aidev sh -lc 'grep "HYBRID_PRESET_CHECK" /home/aidev/.config/opencode/oh-my-opencode-slim.jsonc'
```

Expected: marker is visible inside the container after restart.
