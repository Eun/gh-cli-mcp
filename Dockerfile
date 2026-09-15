# syntax=docker/dockerfile:1

########################################
# Stage 1: build gh-web-auth (Go binary)
# https://github.com/Eun/gh-web-auth
########################################
FROM debian:bookworm-slim AS gh-web-auth-builder

# mise (https://mise.jdx.dev) reads gh-web-auth's own mise.toml and installs
# the exact Go (and golangci-lint/goreleaser) versions the project pins,
# then `mise run build` runs the project's own build task instead of us
# guessing at go build flags.
ENV MISE_DATA_DIR=/root/.local/share/mise \
    PATH="/root/.local/bin:${PATH}" \
    CGO_ENABLED=0

RUN apt-get update \
    && apt-get install -y --no-install-recommends git ca-certificates curl git \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL https://mise.run | sh

WORKDIR /src
RUN git clone --depth 1 https://github.com/Eun/gh-web-auth.git .
RUN mise install
RUN mise run build

########################################
# Stage 2: build mcp-cli (Node/TypeScript)
# https://github.com/pyrex41/mcp-cli
########################################
FROM node:26-bookworm-slim AS mcp-cli-builder

RUN apt-get update \
    && apt-get install -y --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
RUN git clone --depth 1 https://github.com/pyrex41/mcp-cli.git .
RUN npm install && npm run build

########################################
# Stage 3: final runtime image
########################################
FROM node:26-bookworm-slim

ARG GH_CLI_VERSION=2.96.0
ENV DEBIAN_FRONTEND=noninteractive

# ---- Install the official GitHub CLI (gh) ----
# Downloaded straight from GitHub's own release assets (the same host this
# image already needs for git clone below), so there's no dependency on
# cli.github.com's separate apt repo or its GPG keyring. Node itself comes
# from the base image, so there's nothing else to apt-install for the
# runtime beyond curl/ca-certificates/tar to fetch and unpack the binary.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        curl ca-certificates tar \
    && rm -rf /var/lib/apt/lists/* \
    && arch="$(dpkg --print-architecture)" \
    && curl -fsSL -o /tmp/gh.tar.gz \
        "https://github.com/cli/cli/releases/download/v${GH_CLI_VERSION}/gh_${GH_CLI_VERSION}_linux_${arch}.tar.gz" \
    && tar -xzf /tmp/gh.tar.gz -C /tmp \
    && install -m 0755 /tmp/gh_${GH_CLI_VERSION}_linux_${arch}/bin/gh /usr/local/bin/gh \
    && rm -rf /tmp/gh.tar.gz /tmp/gh_${GH_CLI_VERSION}_linux_${arch} \
    && gh --version

# ---- Bring in gh-web-auth (built in stage 1 via `mise run build`) ----
COPY --from=gh-web-auth-builder /src/gh-web-auth /usr/local/bin/gh-web-auth
RUN chmod +x /usr/local/bin/gh-web-auth

# ---- Bring in mcp-cli (built in stage 2) ----
WORKDIR /app/mcp-cli
COPY --from=mcp-cli-builder /src/dist ./dist
COPY --from=mcp-cli-builder /src/node_modules ./node_modules
COPY --from=mcp-cli-builder /src/package.json ./package.json

# ---- mcp-cli config that maps to the gh CLI's tooling ----
WORKDIR /app
COPY mcp-cli-config/gh-config.json /app/mcp-cli-config/gh-config.json

# ---- Entrypoint: start gh-web-auth, then run mcp-cli against the gh config ----
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

# gh-web-auth writes tokens here; gh CLI reads from the same default location.
# (GH_WEB_AUTH_LISTEN_ADDR is intentionally left unset here — entrypoint.sh
# already falls back to 0.0.0.0:8080. Setting it via ENV/ARG trips Docker's
# "secrets in ENV" heuristic even though it isn't a secret.)
ENV GH_CONFIG_DIR=/root/.config/gh

EXPOSE 8080

ENTRYPOINT ["/app/entrypoint.sh"]
