# OLIVE BRANCH — server image. Every version of scaffold/ that this project
# ships is buildable into this same image, unmodified — see
# tools/docker-dev/README.md for why this exists and how it's used (live
# two-device testing without a fragile host-native Node process that dies
# silently the moment the shell session that launched it exits — a real bug
# this session hit before this image existed).
#
# Multi-stage (audit P-16). The old image was one stage that ran a full
# `npm ci` (jsdom, esbuild, the demo's dependencies), COPY'd the whole tree
# (Flutter client, demo, every test suite) and ran as root. This one:
#
#   build  — full `npm ci` (esbuild is a devDependency) + `npm run build`
#            (every packages/*/src/*.ts -> *.mjs; same command tools/verify.sh
#            runs — CI never trusts a committed .mjs), then the build stage
#            DELETES what must not ship: every test/ directory, the demo, the
#            Flutter client, docs.
#   deps   — `npm ci --omit=dev`: runtime dependencies only. (livekit-server-
#            sdk used to be a devDependency although server/routes.mjs imports
#            it at runtime — harmless while the image installed everything,
#            fatal the moment dev dependencies were omitted — so it is now a
#            real dependency in package.json.)
#   final  — node:22-slim, runtime node_modules, the pruned tree, and
#            `USER node` (uid 1000): a compromised request handler no longer
#            owns the container's filesystem.
#
# The .ts sources stay in the image ON PURPOSE: esbuild is run without
# --bundle, so a built pool.mjs still `import`s "../../auth/src/auth.ts" and
# Node's native type stripping (22.18+) executes it. Deleting them would
# break startup.
#
# Postgres client tools (pg_dump/pg_restore 16, from the official PGDG apt
# repository) are installed so the scheduler's `backup` job can really run
# inside this image (tools/scheduler.mjs, docs/backup-and-restore.md). They
# must match the SERVER's major version (docker-compose.prod.yml's db is
# postgres:16): a pg_dump newer than the server writes an archive an older
# pg_restore cannot read. ~25 MB. Build with `--build-arg PG_CLIENT=0` for an
# image without them (the backup job then reports a clear dump-stage failure).
#
# Production deployment note: the process is no longer root. A named volume
# that an earlier (root) image already populated — olive-prod-media — keeps
# its root ownership; run once:
#   docker compose -f docker-compose.prod.yml run --rm --user root \
#     server chown -R node:node /app/data/media
# A fresh volume inherits the node-owned /app/data/media created below.

# ----------------------------------------------------------------- build ----
FROM node:22-slim AS build
WORKDIR /app

# Dependencies first, separately from source, so an unchanged package.json
# reuses Docker's layer cache on every rebuild — this image is meant to be
# rebuilt on every commit ("previous, current, and future builds"), and a
# multi-minute `npm ci` on every single rebuild would defeat that.
COPY package.json package-lock.json ./
RUN npm ci

# Everything else, including tools/, packages/, server/, db/ — build.mjs and
# migrate.mjs both need the whole tree, not just server/.
COPY . .

# Compiles every packages/*/src/*.ts -> *.mjs pair server/index.mjs imports.
RUN npm run build

# Nothing below ships. Test suites (and their fixtures), the offline demo, the
# Flutter client and the docs have no business in a runtime image.
RUN find packages server tools db -type d \( -name test -o -name tests \) -prune -exec rm -rf {} + \
 && rm -rf demo client docs INVENTORY.md

# ------------------------------------------------------------------ deps ----
FROM node:22-slim AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

# ----------------------------------------------------------------- final ----
FROM node:22-slim
ENV NODE_ENV=production
ARG PG_CLIENT=1
RUN if [ "$PG_CLIENT" = "1" ]; then \
      set -eux; \
      apt-get update; \
      apt-get install -y --no-install-recommends ca-certificates curl gnupg; \
      install -d /usr/share/postgresql-common/pgdg; \
      curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc \
        https://www.postgresql.org/media/keys/ACCC4CF8.asc; \
      . /etc/os-release; \
      echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt ${VERSION_CODENAME}-pgdg main" \
        > /etc/apt/sources.list.d/pgdg.list; \
      apt-get update; \
      apt-get install -y --no-install-recommends postgresql-client-16; \
      apt-get purge -y --auto-remove curl gnupg; \
      rm -rf /var/lib/apt/lists/*; \
    fi

WORKDIR /app
COPY --from=deps  --chown=node:node /app/node_modules ./node_modules
COPY --from=build --chown=node:node /app/package.json ./package.json
COPY --from=build --chown=node:node /app/server   ./server
COPY --from=build --chown=node:node /app/packages ./packages
COPY --from=build --chown=node:node /app/tools    ./tools
COPY --from=build --chown=node:node /app/db       ./db

# Uploaded media lives here (docker-compose.prod.yml mounts a named volume at
# this exact path); created node-owned so a FRESH volume is writable.
RUN mkdir -p /app/data/media && chown -R node:node /app/data
USER node

EXPOSE 8080 8787

CMD ["node", "server/index.mjs"]
