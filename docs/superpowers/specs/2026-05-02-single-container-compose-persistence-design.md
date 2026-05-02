# Single-Container Compose Persistence Design

## Goal

Keep the current single-container runtime architecture, but make `docker-compose.yml` the primary deployment contract again so Dokploy users can declare persistent mounts/volumes in-repo and stop losing sessions, providers, skills, and config state across restarts.

## Why This Change Is Needed

The current imperative `Dockerfile` deployment path works for booting the application, but it leaves persistence too implicit. When Dokploy is configured without matching volume mounts, container restarts wipe runtime state such as:

- OpenChamber sessions
- provider credentials and related auth state
- OpenCode config/state written after first boot
- skills/config data stored in persistent runtime paths
- workspace contents

The problem is not the single-container model itself. The problem is that the persistence contract is not currently encoded in a repo-managed deployment file.

## Approved Direction

The repository becomes **compose-first again**, but **does not** return to the old multi-container architecture.

The new target model is:

- one `docker-compose.yml`
- one service
- one image built from root `Dockerfile`
- one container running both OpenCode and OpenChamber
- explicit persistent mounts/volumes declared in Compose

This preserves the operational simplicity of the single-container runtime while restoring a declarative persistence contract that Dokploy can consume directly.

## Runtime Model

The runtime architecture stays unchanged:

- OpenCode and OpenChamber run in the same container
- `scripts/single-container-entrypoint.sh` remains the supervisor
- OpenCode starts first
- readiness is confirmed before OpenChamber starts
- OpenChamber remains the public entry point

No return to separate `opencode` and `openchamber` services is allowed in this design.

## Deployment Model

`docker-compose.yml` becomes the primary supported deployment path for Dokploy.

It should:

- build from root `Dockerfile`
- define the required environment variables
- declare explicit persistent volumes or mount targets
- expose only the OpenChamber-facing internal port expected by Dokploy/Traefik
- avoid reintroducing cross-container networking between OpenCode and OpenChamber

The root `Dockerfile` remains the canonical image definition. Compose becomes the canonical deployment contract.

## Required Persistent Areas

The compose contract must persist these runtime paths explicitly:

### 1. OpenCode config

Path:

- `/home/opencode/.config/opencode`

Why:

- stores repo-managed plugin config after sync
- stores later config updates
- stores skill-related persistent state

### 2. OpenCode data

Path:

- `/home/opencode/.local/share/opencode`

Why:

- stores runtime/auth/session-related OpenCode data

### 3. OpenChamber config

Path:

- `/home/openchamber/.config/openchamber`

Why:

- stores sessions, UI state, provider/session metadata, and other OpenChamber runtime state

### 4. Shared workspace

Path:

- `/workspace`

Why:

- stores repositories and working files used by both OpenChamber and OpenCode inside the same container

## Environment Contract

The compose-first env contract should remain focused on the single-container model.

Expected variables:

- `UI_PASSWORD`
- `OPENCODE_PORT`
- `OPENCHAMBER_PORT` (if the internal OpenChamber listen port remains configurable)
- provider API keys such as `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GOOGLE_API_KEY`

Variables from the old multi-container model must stay absent:

- `OPENCODE_HOST`
- `OPENCODE_SKIP_START`
- any cross-service host wiring variables

## README Expectations

README should be updated so the primary operator flow is:

1. `git submodule update --init`
2. configure `.env` or Dokploy env UI
3. deploy via `docker-compose.yml`
4. ensure the documented persistent volumes are attached

The README should clearly explain that persistence loss happens when these mounts are missing, and that the compose file now exists specifically to make those mount points explicit and reproducible.

## Non-Goals

This change does **not**:

- bring back separate OpenCode/OpenChamber containers
- discard the root `Dockerfile`
- undo the single-container startup supervisor
- redesign preset/provider behavior beyond persistence declaration

## Validation Requirements

Before calling the change complete, verify:

1. `docker-compose.yml` builds the single-container image from root `Dockerfile`
2. the service starts successfully under Compose
3. the service still follows OpenCode-ready-then-OpenChamber startup sequencing
4. the documented persistent paths are mounted in the Compose definition
5. a restart preserves session/config/provider state when those volumes are present
6. README and `.env.example` match the compose-first single-container model with no stale dual-container instructions

## Acceptance Criteria

This design is satisfied when:

- the repo has a real `docker-compose.yml` again
- that file defines a **single** service, not the old two-service split
- it mounts the four required persistent areas
- it builds from root `Dockerfile`
- the documented deployment path for Dokploy is compose-first
- persistence requirements are explicit enough that users do not lose sessions/config because of missing undeclared mounts
