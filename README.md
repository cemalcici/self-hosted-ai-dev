# Dokploy OpenCode Stack

This repository provides a Dokploy-ready Docker Compose stack for:

- OpenCode
- oh-my-opencode-slim
- OpenChamber

## Services

- `opencode`: custom-built backend image with `oh-my-opencode-slim` preinstalled
- `openchamber`: web UI built from the pinned `openchamber/` submodule and connected to the `opencode` service

## Prerequisites

Before building or deploying, ensure the `openchamber` git submodule is present:

```bash
git submodule update --init
```

This is required because `Dockerfile.openchamber` copies from the `openchamber/` source tree. Without the submodule checked out, the build will fail.

## Required environment variables

Copy `.env.example` to `.env` for local validation. In Dokploy, define the same variables in the project environment UI.

Key variables:

- `UI_PASSWORD`
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
- Persistent volumes: `opencode_config`, `opencode_data`, `openchamber_config`, `workspace`.
- `OPENCODE_HOST=http://opencode:4096` uses the internal Docker Compose service name; keep this value when deploying.
- Use the OpenChamber UI to connect GitHub and clone repositories into the shared workspace.

## Shared workspace

Both services mount the same `/workspace` volume. Repositories cloned through OpenChamber should appear there and be available to OpenCode.