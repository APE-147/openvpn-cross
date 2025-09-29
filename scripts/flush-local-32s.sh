#!/bin/bash
# Remove stale /32 host routes that still point at the backhaul gateway or Connect interface.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/env.sh
source "$SCRIPT_DIR/lib/env.sh"

require_var OVPN_LAN_STATUS_FILE
require_var OVPN_BACKHAUL_GATEWAY

STATUS_FILE="$OVPN_LAN_STATUS_FILE"
BACKHAUL_GW="$OVPN_BACKHAUL_GATEWAY"
LOG_FILE="${OVPN_FLUSH_LOG:-/var/log/openvpn-flush-local32.log}"
SELF_CONNECT_IP="${OVPN_CONNECT_SELF_IP:-10.8.0.5}"

ts(){ date '+%F %T'; }
log(){ printf '[%s] %s\n' "$(ts)" "$*" >> "$LOG_FILE" 2>/dev/null || true; }

get_local_108(){
  awk -F, 'BEGIN{p=0} /^ROUTING TABLE/{p=1; next} /^GLOBAL STATS/{p=0} p && $1 ~ /^10\\.8\\.0\./ {print $1}' "$STATUS_FILE" 2>/dev/null | sort -u
}

has_host_route_via_gw(){
  local ip="$1" gw="$2"
  if command -v netstat >/dev/null 2>&1; then
    netstat -rn -f inet | awk -v ip="$ip" -v gw="$gw" '$1==ip && $2==gw {found=1} END{exit found?0:1}'
  else
    ip route show "$ip/32" 2>/dev/null | grep -q "via $gw"
  fi
}

del_host_route(){
  local ip="$1"
  if command -v route >/dev/null 2>&1; then
    /sbin/route -n delete -host "$ip" 2>/dev/null || true
  else
    /usr/sbin/ip route del "$ip/32" 2>/dev/null || true
  fi
}

main(){
  [ -r "$STATUS_FILE" ] || { log "status file not readable: $STATUS_FILE"; exit 0; }
  local ips
  ips=$(get_local_108 || true)
  [ -n "$ips" ] || { log "no local 10.8.0.x peers in status"; exit 0; }

  local connect_iface=""
  connect_iface=$(ifconfig 2>/dev/null | awk -v ip="$SELF_CONNECT_IP" '/^utun[0-9]+:/{i=$1; gsub(":","",i)} $0 ~ ip {print i; exit}')

  while read -r ip; do
    [ -n "$ip" ] || continue
    if has_host_route_via_gw "$ip" "$BACKHAUL_GW"; then
      log "flush $ip via $BACKHAUL_GW"; del_host_route "$ip"
    fi
    if [ -n "$connect_iface" ]; then
      if netstat -rn -f inet | awk -v ip="$ip" -v ifc="$connect_iface" '$1==ip && $NF==ifc {found=1} END{exit found?0:1}'; then
        log "flush $ip via $connect_iface"; del_host_route "$ip"
      fi
    fi
  done <<ROUTES
$ips
ROUTES
}

main "$@"
