#!/bin/sh
set -e

# gh-web-auth writes tokens to the same ~/.config/gh/hosts.yml file that the
# gh CLI reads, so once a browser login completes, `gh` (and therefore
# mcp-cli's wrapped gh tools) is authenticated automatically.
GH_WEB_AUTH_LISTEN_ADDR="${GH_WEB_AUTH_LISTEN_ADDR:-0.0.0.0:8080}"

echo "Starting gh-web-auth on ${GH_WEB_AUTH_LISTEN_ADDR} ..."
gh-web-auth --listen-addr "${GH_WEB_AUTH_LISTEN_ADDR}" &
GH_WEB_AUTH_PID=$!

# Let the caller stop the whole container cleanly if either process exits.
trap 'kill -TERM "$GH_WEB_AUTH_PID" 2>/dev/null || true' TERM INT

echo "Starting mcp-cli wrapping the gh CLI with /app/mcp-cli-config/gh-config.json ..."
exec node /app/mcp-cli/dist/index.js gh /app/mcp-cli-config/gh-config.json
