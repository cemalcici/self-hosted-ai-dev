#!/usr/bin/env sh
set -eu

exec opencode serve --hostname 0.0.0.0 --port "${OPENCODE_PORT:-4096}"
