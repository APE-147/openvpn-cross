#!/bin/sh
# learn-address hook on the cloud side to push /32 routes to the macOS gateway.
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/env.sh
. "$SCRIPT_DIR/lib/env.sh"

require_var OVPN_MAC_SYNC_USER
require_var OVPN_MAC_SSH_KEY
require_var OVPN_MAC_BACKHAUL_HOST
require_var OVPN_MAC_FALLBACK_HOST
require_var OVPN_MAC_ROUTE_APPLY
require_var OVPN_BACKHAUL_GATEWAY

op="$1"; ip="$2"; cn="${3:-}"
logf="${OVPN_CLOUD_ROUTE_LOG:-/data/route-sync-cloud.log}"

case "$ip" in
  10.8.0.*) : ;;
  *) exit 0 ;;
esac

log() { printf '[%s] %s\n' "$(date +'%F %T')" "$*" >> "$logf" 2>/dev/null || true; }

ssh_opts="-o StrictHostKeyChecking=${OVPN_SSH_STRICT_HOSTKEY:-accept-new} -o ConnectTimeout=5 -o ServerAliveInterval=3 -o ServerAliveCountMax=2"
cmd_add="$OVPN_MAC_ROUTE_APPLY add $ip $OVPN_BACKHAUL_GATEWAY"
cmd_del="$OVPN_MAC_ROUTE_APPLY del $ip $OVPN_BACKHAUL_GATEWAY"

try_ssh() {
  host="$1"; cmd="$2"
  if ssh -i "$OVPN_MAC_SSH_KEY" $ssh_opts "$OVPN_MAC_SYNC_USER@$host" "$cmd" >> "$logf" 2>&1; then
    log "ok host=$host cmd=$cmd"
    return 0
  fi
  log "fail host=$host cmd=$cmd"
  return 1
}

case "$op" in
  add|update)
    try_ssh "$OVPN_MAC_BACKHAUL_HOST" "$cmd_add" || try_ssh "$OVPN_MAC_FALLBACK_HOST" "$cmd_add" || true
    ;;
  delete)
    try_ssh "$OVPN_MAC_BACKHAUL_HOST" "$cmd_del" || try_ssh "$OVPN_MAC_FALLBACK_HOST" "$cmd_del" || true
    ;;
  *)
    log "skip op=$op cn=$cn"
    ;;
esac
