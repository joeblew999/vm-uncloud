#!/bin/bash
# SessionStart hook — make `mise install` (and therefore `mise run ci`) work in
# Claude Code on the web. mise pulls github:/aqua: tools (nushell, fnox, http-nu,
# xs, yoke) whose version lookups hit GitHub's ANONYMOUS API rate limit (HTTP 403)
# without a token — the exact failure seen in web sessions. If the environment
# provides GITHUB_TOKEN, hand it to mise so installs are authenticated.
#
# Store/rotate that token in OrangeVault and expose it to the session via the
# environment config (or a fine-grained read-only PAT) — see docs/DEVCONTAINERS.md.
set -euo pipefail

# Web sessions only (local machines already have the tools).
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

# Authenticate mise's GitHub API calls if a token is present (kills the 403s).
if [ -n "${GITHUB_TOKEN:-}" ] && [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export MISE_GITHUB_TOKEN=\"$GITHUB_TOKEN\"" >> "$CLAUDE_ENV_FILE"
  export MISE_GITHUB_TOKEN="$GITHUB_TOKEN"
  echo "session-start: MISE_GITHUB_TOKEN set from GITHUB_TOKEN"
else
  echo "session-start: no GITHUB_TOKEN in env — mise install may hit GitHub rate limits."
fi

# Install the repo's pinned tools so ci/tests/linters run. mise is preinstalled in
# the web image; `install` (not a clean reinstall) benefits from container caching.
if command -v mise >/dev/null 2>&1; then
  mise trust "${CLAUDE_PROJECT_DIR:-$PWD}" || true
  # Soft-fail: a missing/invalid GITHUB_TOKEN shouldn't BLOCK the session — surface
  # the fix instead (most tools come from github:/aqua:, which need the token).
  mise install || echo "session-start: mise install failed — set GITHUB_TOKEN (OrangeVault / env config); see docs/DEVCONTAINERS.md"
else
  echo "session-start: mise not found on PATH" >&2
fi
