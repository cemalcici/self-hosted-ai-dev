# Repo-Managed OpenCode Preset Config Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the oh-my-opencode-slim preset editable from a repo-tracked config file instead of only through the generated file inside the container volume.

**Architecture:** Move the default preset JSONC out of the shell heredoc in `scripts/opencode-entrypoint.sh` into a tracked repo file under `config/`. Keep the current first-bootstrap behavior: the entrypoint copies the repo file into the persistent OpenCode config location only when the target file does not already exist, so repo defaults are easy to edit while operator customizations inside an existing volume remain preserved.

**Tech Stack:** Docker Compose, POSIX shell entrypoint, JSONC config, Markdown documentation

---

### File Structure

**Files:**
- Create: `config/oh-my-opencode-slim.jsonc`
- Modify: `scripts/opencode-entrypoint.sh`
- Modify: `README.md`

Responsibilities:
- `config/oh-my-opencode-slim.jsonc` becomes the repo-owned source of truth for the default plugin preset shipped by this stack.
- `scripts/opencode-entrypoint.sh` copies that tracked file into `$PLUGIN_CONFIG_FILE` only on first bootstrap.
- `README.md` explains how to edit the preset from the repo, how bootstrap behaves, and what to do for already-initialized persistent volumes.

### Task 1: Move the default preset into a tracked repo file

**Files:**
- Create: `config/oh-my-opencode-slim.jsonc`
- Modify: `scripts/opencode-entrypoint.sh`

- [ ] **Step 1: Capture the current default preset as the failing-before state**

Run:

```bash
grep -n '"preset": "openai"' scripts/opencode-entrypoint.sh
```

Expected: PASS with the preset currently embedded in the shell heredoc, proving the repo does not yet have a separate tracked config source.

- [ ] **Step 2: Create the tracked preset file**

Create `config/oh-my-opencode-slim.jsonc` with this exact content:

```jsonc
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
```

- [ ] **Step 3: Replace the inline heredoc with a file copy**

Update `scripts/opencode-entrypoint.sh` so the plugin-config bootstrap reads from the tracked repo file instead of embedding JSON inline. The relevant block should become:

```sh
REPO_PLUGIN_CONFIG_TEMPLATE="/app/config/oh-my-opencode-slim.jsonc"

if [ ! -f "$PLUGIN_CONFIG_FILE" ]; then
  cp "$REPO_PLUGIN_CONFIG_TEMPLATE" "$PLUGIN_CONFIG_FILE"
fi
```

Keep the surrounding behavior unchanged:
- still create config/data/workspace directories
- still only create the file when it does not already exist
- still preserve user-modified persistent config files

- [ ] **Step 4: Verify the inline preset was removed and the tracked file is now the source**

Run:

```bash
grep -n '"preset": "openai"' scripts/opencode-entrypoint.sh config/oh-my-opencode-slim.jsonc
```

Expected:
- no match in `scripts/opencode-entrypoint.sh`
- one or more matches in `config/oh-my-opencode-slim.jsonc`

- [ ] **Step 5: Verify the container build still includes the template path**

Run:

```bash
docker compose build opencode
```

Expected: PASS, proving the new tracked config file is copied into the image successfully.

### Task 2: Document the repo-managed customization workflow

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add operator guidance for preset editing**

Add a README section describing all of the following points clearly:
- the repo-managed source file is `config/oh-my-opencode-slim.jsonc`
- users should edit that file in the repo when they want to change the shipped preset
- on first bootstrap, the entrypoint copies it into the persistent OpenCode config directory as `~/.config/opencode/oh-my-opencode-slim.jsonc`
- if the target file already exists in the persistent volume, the entrypoint does not overwrite it
- for existing deployments, operators must either edit the file inside the mounted config volume themselves or remove that file so bootstrap can recreate it from the repo template on next start

- [ ] **Step 2: Verify the README mentions the tracked config path and bootstrap behavior**

Run:

```bash
grep -n 'config/oh-my-opencode-slim.jsonc\|does not overwrite\|persistent volume' README.md
```

Expected: PASS with matches showing the new operator guidance is present.

- [ ] **Step 3: Commit the change**

Run:

```bash
git add config/oh-my-opencode-slim.jsonc scripts/opencode-entrypoint.sh README.md docs/superpowers/plans/2026-04-30-opencode-preset-config.md
git commit -m "feat: make plugin preset repo-managed"
```

Expected: PASS with one commit containing the tracked preset file, entrypoint update, README update, and this plan document.
