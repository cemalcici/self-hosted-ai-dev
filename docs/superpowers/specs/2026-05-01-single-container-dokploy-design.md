# Single-Container Dokploy Deployment Design

## Goal

OpenCode, OpenChamber, and oh-my-opencode-slim should run inside a single Docker image and a single Dokploy-managed container, without `docker-compose.yml`, so configuration sharing, startup ordering, and operational debugging are simpler and more deterministic.

## Why This Replaces The Current Architecture

The current two-container model solved initial separation concerns, but it keeps creating friction in the exact places this stack cares about most:

- OpenChamber and OpenCode need to observe related config/state
- startup ordering matters because OpenChamber depends on a ready OpenCode backend
- cross-container file paths and runtime assumptions can drift
- Dokploy already supports imperative single-container deployments, so Compose orchestration is not required

The new target architecture intentionally trades service separation for operational simplicity.

## Scope

This design covers:

- replacing the Compose-based two-service deployment with a single Dockerfile deployment
- running OpenCode and OpenChamber in one container under one startup supervisor
- keeping oh-my-opencode-slim installed and repo-managed
- adapting persistence, startup, and readiness to Dokploy's single-container model

This design does not cover:

- upstream contributions to OpenChamber
- changing the product behavior of oh-my-opencode-slim itself
- redesigning the user-facing OpenChamber UI

## Approved Architecture

### Runtime Model

The deployment becomes a single custom image and a single runtime container.

That container includes:

- OpenCode
- OpenChamber
- oh-my-opencode-slim
- a repo-owned startup supervisor / entrypoint

OpenChamber connects to OpenCode over `127.0.0.1` / `localhost` inside the same container instead of using Docker service discovery.

### Deployment Model

`docker-compose.yml` is removed from the target deployment architecture.

Dokploy should deploy this stack through its single-container / imperative Dockerfile flow:

- one Dockerfile
- one container
- Dokploy-managed environment variables
- Dokploy-managed persistent mounts / volumes
- Dokploy-managed public routing to OpenChamber

### Image Strategy

The current split between `Dockerfile.opencode` and `Dockerfile.openchamber` is replaced by one new Dockerfile that builds the final runtime image.

That image should:

- include the OpenChamber build output and runtime files
- include OpenCode and oh-my-opencode-slim
- include the repo-managed preset file `config/oh-my-opencode-slim.jsonc`
- include one startup script responsible for process supervision and readiness sequencing

## Process Supervision Design

### Startup Order

Container start must follow this order:

1. prepare filesystem layout and writable directories
2. sync repo-managed OpenCode / plugin config into runtime locations
3. start OpenCode
4. wait until OpenCode's health endpoint is actually ready
5. start OpenChamber
6. keep the container alive under a supervisor that forwards signals and handles child shutdown cleanly

### Process Ownership

This design should not rely on a fragile “start one thing in the background and hope the foreground process cleans everything up” shell pattern.

Instead, the container must use an explicit supervisor approach. The exact implementation may be a repo-owned supervisor script or a lightweight init/supervision tool, but the behavior must be:

- both processes are started intentionally
- logs go to stdout/stderr
- `SIGTERM` and restart events shut both processes down cleanly
- orphan processes are not left behind
- OpenChamber never starts before OpenCode readiness is confirmed

## Filesystem And Persistence Model

Single-container does not mean “everything shares one folder.” Data responsibilities remain separated, but they now live in one runtime filesystem context instead of across container boundaries.

Recommended persistent areas:

- OpenCode config
- OpenCode data
- OpenChamber config
- shared workspace

These remain separate Dokploy-managed persistent mounts / volumes.

### Why Keep The Separation

This preserves clarity around ownership and recovery:

- OpenCode runtime state is still distinct from OpenChamber state
- workspace data stays independently understandable
- operators can reset one area without destroying everything else

### Config Locality Benefit

Because both products run in the same container:

- OpenChamber can read OpenCode-related files from the same filesystem context when needed
- path locality bugs become much less likely
- localhost connectivity replaces service-name dependency like `http://opencode:4096`

## Configuration Model

### OpenCode

OpenCode remains internal-only within the container.

- no separate public exposure
- no extra server username/password layer required for OpenCode itself
- OpenChamber remains the intended user-facing entrypoint

### oh-my-opencode-slim Preset

`config/oh-my-opencode-slim.jsonc` remains the repo-authoritative source of truth.

On every container start, startup logic should sync that file into OpenCode's runtime config location so that repo changes apply on restart/redeploy.

### OpenChamber

OpenChamber remains the public web surface.

- Dokploy routes external traffic to OpenChamber
- OpenChamber UI password remains enabled unless explicitly changed later
- OpenChamber should target the colocated OpenCode backend over localhost

## Security Boundaries

The simplified model still preserves the intended boundary:

- only OpenChamber is publicly reachable
- OpenCode is not independently exposed
- secrets stay in Dokploy-managed environment settings and persistent runtime data, not hardcoded in the repo
- SSH mount remains out of scope

The trust model becomes: internal same-container communication is trusted; public user access still goes through OpenChamber.

## Operational Trade-Offs

### Benefits

- simpler config sharing
- simpler readiness sequencing
- simpler debugging
- fewer cross-container integration bugs
- no Docker service discovery dependency for the core app flow
- Dokploy deployment model aligns more closely with the actual runtime architecture

### Costs

- larger image size
- one container now carries two important processes
- startup script / supervisor becomes a critical integration point
- migration from current Compose model must be deliberate

## Migration Direction

The implementation should be treated as an architectural transition, not a tiny patch.

Expected high-level migration steps:

1. introduce a new single Dockerfile and startup supervisor
2. adapt OpenChamber runtime to use colocated OpenCode over localhost
3. move persistence assumptions from Compose volumes to Dokploy container mounts
4. retire `docker-compose.yml` from the target deployment path
5. update README and operator instructions for Dokploy imperative deployment

## Validation Requirements

The new architecture is only acceptable if all of the following are verified:

1. the single Dockerfile builds successfully
2. the container starts both OpenCode and OpenChamber cleanly
3. OpenCode reaches healthy state before OpenChamber is started
4. OpenChamber UI loads successfully through Dokploy routing
5. OpenCode-backed features visible in OpenChamber still work
6. skills/providers/config visibility still work from the user perspective
7. repo-managed preset changes apply after restart/redeploy
8. shutdown/restart does not leave orphan processes behind

## Acceptance Criteria

This redesign is complete when:

- deployment no longer depends on `docker-compose.yml`
- Dokploy can deploy the stack from a single Dockerfile
- OpenCode and OpenChamber run correctly in one container
- OpenChamber waits for actual OpenCode readiness
- existing config/preset workflow still works under the new model
- public access still goes only through OpenChamber

## Expected File Direction

The exact filenames may change during implementation, but the target shape should converge on:

- one new primary Dockerfile for the full stack
- one repo-owned supervisor / startup script
- retained `config/oh-my-opencode-slim.jsonc`
- updated `README.md` for Dokploy single-container deployment
- eventual retirement or deprecation of Compose-specific deployment wiring from the main path
