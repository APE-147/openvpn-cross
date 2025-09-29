#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/env.sh
source "$SCRIPT_DIR/lib/env.sh"

require_var OVPN_BACKHAUL_GATEWAY
TARGET_GW="$OVPN_BACKHAUL_GATEWAY"
LOG_FILE="${OVPN_BACKHAUL_FLUSH_LOG:-/tmp/openvpn-backhaul.log}"
DRY_RUN=${1:-}

ts() { date +'%F %T'; }
log() { echo "[backhaul-down-flush] $(ts) $*" >> "$LOG_FILE"; }

del_route() {
  local ip="$1"
  if [ "$DRY_RUN" = "--dry-run" ]; then
    log "dry-run del $ip via $TARGET_GW"
    return 0
  fi
  /sbin/route -n delete -host "$ip" 2>/dev/null || true
}

list_host_routes() {
  if command -v netstat >/dev/null 2>&1; then
    netstat -rn -f inet | awk '$1 ~ /^10\\.8\\./ && $2 == gw {print $1}' gw="$TARGET_GW"
  else
    ip route show | awk '$1 ~ /^10\\.8\\./ && $3 == gw {print $1}' gw="$TARGET_GW"
  fi
}

main() {
  list_host_routes | while read -r ip; do
    [ -n "$ip" ] || continue
    log "flush $ip via $TARGET_GW"
    del_route "$ip"
  done
}

main "$@"
