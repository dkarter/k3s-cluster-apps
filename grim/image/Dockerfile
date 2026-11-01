# Grim (https://github.com/anomalyco/grim) publishes no container image, so we
# build one from a pinned upstream commit. Built and pushed to
# ghcr.io/dkarter/grim by .github/workflows/grim-image.yml.
ARG BUN_IMAGE=oven/bun:1.4.4-slim

# The build output is architecture-independent (no native modules in the
# production dependencies), so build natively and only emulate the final stage.
FROM --platform=${BUILDPLATFORM} ${BUN_IMAGE} AS build
# Upstream commit to build. To upgrade, bump this and the image tag in
# grim/values.yml.
ARG GRIM_REF=4534002a1100c99acf11116bd980a3756fa322d5
RUN apt-get update \
  && apt-get install -y --no-install-recommends git ca-certificates \
  && rm -rf /var/lib/apt/lists/*
WORKDIR /app
RUN git init -q . \
  && git fetch -q --depth 1 https://github.com/anomalyco/grim.git "${GRIM_REF}" \
  && git checkout -q FETCH_HEAD \
  && rm -rf .git \
  && bun install --frozen-lockfile \
  && bun run build:client \
  && rm -rf node_modules \
  && bun install --frozen-lockfile --production

FROM ${BUN_IMAGE}
# git is required at runtime: with STORAGE=local every note is committed to a
# bare git repo by shelling out to git.
RUN apt-get update \
  && apt-get install -y --no-install-recommends git ca-certificates \
  && rm -rf /var/lib/apt/lists/* \
  && install -d -o bun -g bun /data
WORKDIR /app
COPY --from=build --chown=bun:bun /app /app
USER bun
ENV PORT=8787 \
  DATA_DIR=/data \
  STORAGE=local \
  SIGN_IN=off
EXPOSE 8787
VOLUME /data
# SIGTERM makes the server commit pending edits before exiting.
STOPSIGNAL SIGTERM
CMD ["bun", "src/server/index.ts"]
