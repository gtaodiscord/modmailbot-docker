# syntax=docker/dockerfile:1

ARG NODE_VERSION=24

FROM node:${NODE_VERSION}-bookworm-slim AS build

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends g++ make python3 \
    && rm -rf /var/lib/apt/lists/*

COPY upstream/package.json upstream/package-lock.json upstream/.npmrc ./

RUN npm ci --omit=dev \
    && npm cache clean --force

FROM node:${NODE_VERSION}-bookworm-slim AS runtime

ARG MODMAIL_VERSION=unknown
ARG UPSTREAM_REVISION=unknown
ARG BUILD_DATE=unknown

LABEL org.opencontainers.image.title="Dragory Modmail" \
      org.opencontainers.image.description="Minimal Debian glibc image for Dragory Modmail" \
      org.opencontainers.image.source="https://github.com/gtaodiscord/modmailbot-docker" \
      org.opencontainers.image.url="https://github.com/Dragory/modmailbot" \
      org.opencontainers.image.version="${MODMAIL_VERSION}" \
      org.opencontainers.image.revision="${UPSTREAM_REVISION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.licenses="MIT"

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends tini git ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /app/plugins /app/attachments \
    && chown -R node:node /app

WORKDIR /app

COPY --from=build --chown=node:node /app/node_modules ./node_modules
COPY --chown=node:node upstream/ ./

RUN rm -rf /app/.git \
    && mkdir -p /app/plugins /app/attachments \
    && chown -R node:node /app

USER node

EXPOSE 8890

ENTRYPOINT ["tini", "--"]
CMD ["node", "src/index.js"]
