#!/bin/bash
# Helper for managing the dual-end OpenVPN deployment on macOS.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/env.sh
source "$SCRIPT_DIR/scripts/lib/env.sh"

BACKHAUL_PLIST="${OVPN_BACKHAUL_PLIST:-/Library/LaunchDaemons/com.example.openvpn-backhaul.plist}"
SERVER_LAN_PLIST="${OVPN_SERVER_LAN_PLIST:-/Library/LaunchDaemons/com.example.openvpn-server-lan.plist}"
ROUTE_SYNC_PLIST="${OVPN_ROUTE_SYNC_PLIST:-/Library/LaunchDaemons/com.example.openvpn-route-sync.plist}"
OPENVPN_BIN="${OVPN_BIN_PATH:-/opt/homebrew/sbin/openvpn}"
STATUS_LAN_FILE="${OVPN_LAN_STATUS_FILE:-/opt/homebrew/var/log/openvpn-lan.status}"

BACKHAUL_ID="$(basename "$BACKHAUL_PLIST" .plist)"
SERVER_LAN_ID="$(basename "$SERVER_LAN_PLIST" .plist)"
ROUTE_SYNC_ID="$(basename "$ROUTE_SYNC_PLIST" .plist)"

require_var OVPN_ROUTE_APPLY
require_var OVPN_SSH_HOST_ALIAS
require_var OVPN_CLOUD_STATUS_PATH
require_var OVPN_CLOUD_STATUS_BACKHAUL_PATH

if [ -n "${OVPN_SUDO_PASS:-}" ]; then
  SUDO=(sudo -S -p '')
  sudo_run() { printf '%s\n' "$OVPN_SUDO_PASS" | "${SUDO[@]}" "$@"; }
else
  SUDO=(sudo)
  sudo_run() { "${SUDO[@]}" "$@"; }
fi

TS() { date '+%F %T'; }
say() { printf '[%s] %s\n' "$(TS)" "$*"; }
ok() { say "OK: $*"; }
warn() { say "WARN: $*"; }
fail() { say "FAIL: $*"; }

cloud_cmd() {
  ssh -o StrictHostKeyChecking="${OVPN_SSH_STRICT_HOSTKEY:-accept-new}" -o ConnectTimeout=8 "$OVPN_SSH_HOST_ALIAS" "$@"
}

load_daemons() {
  say 'Loading OpenVPN launch daemons'
  for plist in "$BACKHAUL_PLIST" "$SERVER_LAN_PLIST" "$ROUTE_SYNC_PLIST"; do
    [ -f "$plist" ] || { warn "missing $plist"; continue; }
    sudo_run launchctl unload -w "$plist" 2>/dev/null || true
    sudo_run launchctl load -w "$plist"
  done
}

unload_daemons() {
  say 'Unloading OpenVPN launch daemons'
  for plist in "$BACKHAUL_PLIST" "$SERVER_LAN_PLIST" "$ROUTE_SYNC_PLIST"; do
    [ -f "$plist" ] || continue
    sudo_run launchctl unload -w "$plist" 2>/dev/null || true
  done
}

show_status_local() {
  say '=== Processes ==='
  ps aux | grep "$OPENVPN_BIN" | grep -v grep || true
  say '=== Interfaces (utun) ==='
  ifconfig | grep -E 'utun[0-9]|10\\.8\\.|10\\.255\.' || true
  say '=== Routes (10.8/10.255) ==='
  netstat -rn -f inet | grep -E '^10\\.8\\.|^10\\.255\.' || true
}

show_status_cloud() {
  say '=== Cloud status excerpts ==='
  cloud_cmd "sudo -n sed -n '1,120p' '$OVPN_CLOUD_STATUS_PATH'" || warn 'cannot read cloud status'
  cloud_cmd "sudo -n sed -n '1,120p' '$OVPN_CLOUD_STATUS_BACKHAUL_PATH'" || warn 'cannot read backhaul status'
}

health() {
  say '=== Launchd Jobs ==='
  for id in "$BACKHAUL_ID" "$SERVER_LAN_ID" "$ROUTE_SYNC_ID"; do
    if sudo_run launchctl print "system/$id" >/dev/null 2>&1; then
      ok "$id loaded"
    else
      warn "$id not loaded"
    fi
  done

  say '=== Interfaces ==='
  if ifconfig 2>/dev/null | grep -q '10.255.'; then ok 'backhaul interface present'; else warn 'backhaul interface missing'; fi
  if ifconfig 2>/dev/null | grep -q '10.8.'; then ok 'lan interface present'; else warn 'lan interface missing'; fi

  say '=== Cloud Reachability ==='
  cloud_cmd 'echo ok' >/dev/null 2>&1 && ok 'cloud reachable via SSH' || fail 'cloud unreachable'
}

routes() {
  say '=== Current routes ==='
  netstat -rn -f inet | grep '^10\\.8\\.0\.' || true
}

usage() {
  cat <<USAGE
Usage: $0 <command>
Commands:
  load        Load launch daemons
  unload      Unload launch daemons
  status      Show local status
  status-cloud  Show cloud OpenVPN status excerpts
  health      Run quick health checks
  routes      Show 10.8.0.x routes
USAGE
}

main() {
  case "${1:-}" in
    load) load_daemons ;;
    unload) unload_daemons ;;
    status) show_status_local ;;
    status-cloud) show_status_cloud ;;
    health) health ;;
    routes) routes ;;
    *) usage ;;
  esac
}

main "$@"
