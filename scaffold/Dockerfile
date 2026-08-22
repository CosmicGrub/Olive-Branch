# OLIVE BRANCH — server image. Every version of scaffold/ that this project
# ships is buildable into this same image, unmodified — see
# tools/docker-dev/README.md for why this exists and how it's used (live
# two-device testing without a fragile host-native Node process that dies
# silently the moment the shell session that launched it exits — a real bug
# this session hit before this image existed).
#
# Single-stage, not multi-stage: this only ever runs `node server/index.mjs`
# (or local-call-room-server.mjs — see docker-compose.dev.yml's `callroom`
# service, same image, different command) directly against the .mjs files
# `npm run build` produces. No bundler/minifier step ships a smaller final
# artifact than "the repo plus node_modules", and this is a dev/test image,
# not a production deployment — see tools/docker-dev/README.md's own scope
# note for why production packaging is deliberately out of scope here.
FROM node:22-slim

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
# Same command tools/verify.sh runs — see that script for why CI never
# trusts a committed .mjs file's correctness, only ever a freshly-built one.
RUN npm run build

EXPOSE 8080 8787

CMD ["node", "server/index.mjs"]
