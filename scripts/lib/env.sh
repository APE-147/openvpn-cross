#!/bin/bash
# Shared helpers for sourcing .env and asserting required variables.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV_FILE="$REPO_ROOT/.env"

load_env() {
  if [ -f "$ENV_FILE" ]; then
    # shellcheck disable=SC1090
    set -a
    source "$ENV_FILE"
    set +a
  fi
}

require_var() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    echo "[env] missing required variable: $name" >&2
    exit 1
  fi
}

load_env
