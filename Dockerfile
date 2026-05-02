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

RUN useradd -m -d /home/aidev -s /bin/bash aidev

ENV OPENCODE_HOME=/home/aidev
ENV OPENCHAMBER_HOME=/home/aidev
ENV XDG_CONFIG_HOME=/home/aidev/.config
ENV XDG_DATA_HOME=/home/aidev/.local/share
ENV BUN_INSTALL=/home/aidev/.bun
ENV PATH=/home/aidev/.bun/bin:${PATH}

RUN bun add -g opencode-ai && bunx oh-my-opencode-slim@latest install --no-tui \
  && mkdir -p /home/aidev/.bun/bin \
  && ln -sf /home/aidev/.bun/install/global/node_modules/opencode-ai/bin/opencode /home/aidev/.bun/bin/opencode \
  && ln -sf /home/aidev/.bun/install/global/node_modules/.bin/oh-my-opencode-slim /home/aidev/.bun/bin/oh-my-opencode-slim 2>/dev/null || true

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
  && mkdir -p /workspace /home/aidev/.config/opencode /home/aidev/.local/share/opencode /home/aidev/.config/openchamber /home/aidev/.ssh \
  && chmod o+X /home/aidev \
  && chown -R aidev:aidev /workspace /home/aidev

EXPOSE 3000 4096

ENTRYPOINT ["/usr/local/bin/single-container-entrypoint.sh"]
