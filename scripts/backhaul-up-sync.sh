#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/env.sh
source "$SCRIPT_DIR/lib/env.sh"

require_var OVPN_CLOUD_HOST
require_var OVPN_CLOUD_USER
require_var OVPN_SSH_KEY_PATH
require_var OVPN_CLOUD_STATUS_PATH
require_var OVPN_ROUTE_APPLY
require_var OVPN_BACKHAUL_GATEWAY
require_var OVPN_SELF_TUN_IP

DRY_RUN=${1:-}
SSH_STRICT=${OVPN_SSH_STRICT_HOSTKEY:-accept-new}
LOG_FILE="${OVPN_BACKHAUL_SYNC_LOG:-/tmp/openvpn-backhaul.log}"

SSH_OPTS=(-o StrictHostKeyChecking="$SSH_STRICT" -o ConnectTimeout=8 -o ServerAliveInterval=5 -o ServerAliveCountMax=2)

log() { echo "[backhaul-up-sync] $(date +'%F %T') $*" >> "$LOG_FILE"; }
fetch_status() {
  ssh -i "$OVPN_SSH_KEY_PATH" "${SSH_OPTS[@]}" "$OVPN_CLOUD_USER@$OVPN_CLOUD_HOST" \
    "sudo -n cat '$OVPN_CLOUD_STATUS_PATH'" 2>/dev/null
}

apply_routes() {
  awk -F, '/^ROUTING TABLE/{p=1;next} /^GLOBAL STATS/{p=0} p && $1 ~ /^10\\.8\\.0\\./{print $1}' |
  while read -r ip; do
    [ -n "$ip" ] || continue
    [ "$ip" = "$OVPN_SELF_TUN_IP" ] && continue
    if [ "$DRY_RUN" = "--dry-run" ]; then
      log "dry-run add $ip via $OVPN_BACKHAUL_GATEWAY"
      continue
    fi
    log "add $ip via $OVPN_BACKHAUL_GATEWAY"
    "$OVPN_ROUTE_APPLY" add "$ip" "$OVPN_BACKHAUL_GATEWAY" || true
  done
}

main() {
  if ! command -v ssh >/dev/null 2>&1; then
    log "ssh not found"
    exit 1
  fi
  if [ ! -x "$OVPN_ROUTE_APPLY" ]; then
    log "route apply script missing: $OVPN_ROUTE_APPLY"
    exit 1
  fi
  fetch_status | apply_routes
}

main "$@"
