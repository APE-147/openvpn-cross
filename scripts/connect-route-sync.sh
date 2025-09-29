#!/bin/bash
# Synchronise host routes between macOS OpenVPN Connect and the backhaul tunnel.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/env.sh
source "$SCRIPT_DIR/lib/env.sh"

require_var OVPN_ROUTE_APPLY
require_var OVPN_BACKHAUL_GATEWAY
require_var OVPN_SELF_TUN_IP
require_var OVPN_SSH_HOST_ALIAS
require_var OVPN_CLOUD_STATUS_PATH

MODE=${1:-sync}
SSH_STRICT=${OVPN_SSH_STRICT_HOSTKEY:-accept-new}
LOG_FILE="${OVPN_CONNECT_SYNC_LOG:-/tmp/openvpn-connect-route.log}"

log() { echo "[connect-route-sync] $(date +'%F %T') $*" >> "$LOG_FILE"; }

ssh_cloud() {
  ssh -o StrictHostKeyChecking="$SSH_STRICT" -o ConnectTimeout=6 "$OVPN_SSH_HOST_ALIAS" "$@"
}

cloud_clients() {
  ssh_cloud "sudo -n sed -n '1,220p' '$OVPN_CLOUD_STATUS_PATH'" 2>/dev/null \
    | awk -F, 'BEGIN{p=0} /^ROUTING TABLE/{p=1;next} /^GLOBAL STATS/{p=0} p && $1 ~ /^10\\.8\\.0\\./{print $1}'
}

connect_iface() {
  ifconfig 2>/dev/null | awk '/^utun[0-9]+:/{iface=$1; sub(":","",iface)} /inet 10\.8\./{print iface; exit}'
}

set_route() {
  local ip="$1" gw="$2"
  if [ "$MODE" = "--dry-run" ]; then
    log "dry-run set $ip via $gw"
    return 0
  fi
  "$OVPN_ROUTE_APPLY" add "$ip" "$gw"
}

status_dump() {
  echo "=== Cloud clients ==="
  cloud_clients || true
  echo
  echo "=== Current routes (10.8.0.x) ==="
  netstat -rn -f inet | grep '^10\\.8\\.0\.' || true
}

sync_routes() {
  local connect_gw="$1"
  local cloud_ips; cloud_ips=$(cloud_clients || true)
  [ -n "$cloud_ips" ] || { log 'no clients reported'; return 0; }

  while read -r ip; do
    [ -n "$ip" ] || continue
    [ "$ip" = "$OVPN_SELF_TUN_IP" ] && continue
    if [ -n "$connect_gw" ]; then
      set_route "$ip" "$connect_gw"
    else
      set_route "$ip" "$OVPN_BACKHAUL_GATEWAY"
    fi
  done <<ROUTES
$cloud_ips
ROUTES
}

main() {
  case "$MODE" in
    status)
      status_dump
      return 0
      ;;
    sync|--dry-run)
      :
      ;;
    *)
      echo "usage: $0 [sync|status|--dry-run]" >&2
      exit 2
      ;;
  esac

  local iface connect_target=""
  iface=$(connect_iface || true)
  if [ -n "$iface" ]; then
    connect_target="$iface"
    log "Connect interface detected: $iface"
  else
    log 'no Connect interface detected; using backhaul gateway'
  fi

  sync_routes "$connect_target"
}

main
