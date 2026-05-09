ARG NODE_IMAGE=docker.io/library/node:24-slim
ARG RUNTIME_IMAGE=docker.io/library/node:24-slim

FROM ${NODE_IMAGE} AS build

ARG HTTP_PROXY
ARG HTTPS_PROXY
ARG http_proxy
ARG https_proxy
ARG no_proxy
ARG NO_PROXY

ENV HTTP_PROXY=${HTTP_PROXY}
ENV HTTPS_PROXY=${HTTPS_PROXY}
ENV http_proxy=${http_proxy}
ENV https_proxy=${https_proxy}
ENV no_proxy=${no_proxy}
ENV NO_PROXY=${NO_PROXY}
ENV CI=true

# debian/slim equivalent of alpine's python3 make g++
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 make g++ \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY scripts/postinstall.mjs ./scripts/postinstall.mjs
COPY packages ./packages
COPY tools ./tools
COPY apps/daemon/package.json ./apps/daemon/package.json
COPY apps/web/package.json ./apps/web/package.json
COPY e2e/package.json ./e2e/package.json

RUN corepack enable && \
    corepack prepare pnpm@10.33.2 --activate && \
    pnpm install --frozen-lockfile

COPY apps ./apps

RUN pnpm --filter @open-design/daemon build && \
    pnpm --filter @open-design/web build && \
    pnpm --filter @open-design/daemon deploy --legacy --prod /app/deploy/daemon && \
    pnpm store prune && \
    rm -rf \
      /root/.cache \
      /root/.local/share/pnpm/store \
      /app/deploy/daemon/node_modules/.cache \
      /app/deploy/daemon/node_modules/@types \
      /app/deploy/daemon/node_modules/.pnpm/@types+* \
      /app/deploy/daemon/node_modules/.pnpm/better-sqlite3@*/node_modules/better-sqlite3/deps \
      /app/deploy/daemon/node_modules/.pnpm/better-sqlite3@*/node_modules/better-sqlite3/src && \
    find /app/deploy/daemon/node_modules -type d \( \
      -name test -o \
      -name tests -o \
      -name "__tests__" -o \
      -name docs -o \
      -name doc -o \
      -name example -o \
      -name examples -o \
      -name ".github" \
    \) -prune -exec rm -rf '{}' + && \
    find /app/deploy/daemon/node_modules -type f \( \
      -name "*.md" -o \
      -name "*.markdown" -o \
      -name "*.d.ts" -o \
      -name "*.d.cts" -o \
      -name "*.d.mts" -o \
      -name "*.map" -o \
      -name "*.tsbuildinfo" -o \
      -name "binding.gyp" \
    \) -delete

FROM ${RUNTIME_IMAGE}

RUN apt-get update && apt-get install -y --no-install-recommends \
    tini \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g @anthropic-ai/claude-code

WORKDIR /app

COPY --from=build --chown=node:node /app/deploy/daemon ./apps/daemon
COPY --from=build --chown=node:node /app/apps/web/out ./apps/web/out
COPY --chown=node:node skills ./skills
COPY --chown=node:node design-systems ./design-systems
COPY --chown=node:node craft ./craft
COPY --chown=node:node prompt-templates ./prompt-templates
COPY --chown=node:node assets/frames ./assets/frames
COPY --chown=node:node assets/community-pets ./assets/community-pets

RUN mkdir -p /app/.od && \
    chown -R node:node /app

ENV NODE_ENV=production
ENV NODE_OPTIONS=--max-old-space-size=192
ENV OD_BIND_HOST=0.0.0.0
ENV OD_PORT=7456

EXPOSE 7456

RUN usermod -d /home/node node
USER node

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["node", "apps/daemon/dist/cli.js", "--no-open"]
