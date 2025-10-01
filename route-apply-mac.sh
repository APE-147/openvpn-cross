#!/usr/bin/env bash
set -euo pipefail

# This script is invoked by OpenVPN server via `learn-address`.
# Args: $1 = add|update|delete, $2 = address[/mask], $3 = common_name (optional)

ACTION=${1:-}
ADDR=${2:-}
CN=${3:-}

LOG_FILE=/tmp/route-apply-mac.log

# Local backhaul gateway (towards cloud via backhaul tunnel)
BACKHAUL_GW_LOCAL=${BACKHAUL_GW_LOCAL:-10.255.0.1}
# Mac-mini backhaul IP as seen by cloud (client IP on backhaul)
BACKHAUL_GW_CLOUD=${BACKHAUL_GW_CLOUD:-10.255.0.2}

# Optional cloud SSH notify (set CLOUD_SSH_DEST like ubuntu@13.54.193.137 and CLOUD_SSH_KEY to key path)
CLOUD_SSH_DEST=${CLOUD_SSH_DEST:-}
CLOUD_SSH_KEY=${CLOUD_SSH_KEY:-}
CLOUD_SCRIPT=${CLOUD_SCRIPT:-/home/ubuntu/openvpn-backup/data/scripts/route-apply-cloud.sh}

ts() { date '+%Y-%m-%d %H:%M:%S'; }
log() { echo "$(ts) [$ACTION] addr=$ADDR cn=${CN:-} :: $*" >>"$LOG_FILE"; }

# Extract IPv4 without mask
IP=${ADDR%%/*}

# Act only on 10.8.0.0/24 single-subnet Plan B host routes
case "$IP" in
  10.8.0.*) : ;;  # ok
  *) log "skip non-10.8.0.0/24 address"; exit 0 ;;
esac

add_route() {
  # change if exists; otherwise add
  if /sbin/route -n change -host "$IP" "$BACKHAUL_GW_LOCAL" 2>>"$LOG_FILE"; then
    log "route changed: $IP via $BACKHAUL_GW_LOCAL"
  else
    if /sbin/route -n add -host "$IP" "$BACKHAUL_GW_LOCAL" >>"$LOG_FILE" 2>&1; then
      log "route added: $IP via $BACKHAUL_GW_LOCAL"
    else
      log "route add failed: $IP"
    fi
  fi
}

del_route() {
  if /sbin/route -n delete -host "$IP" >>"$LOG_FILE" 2>&1; then
    log "route deleted: $IP"
  else
    log "route delete failed or not present: $IP"
  fi
}

notify_cloud() {
  [ -n "$CLOUD_SSH_DEST" ] || return 0
  [ -n "$CLOUD_SCRIPT" ] || return 0

  case "$ACTION" in
    add|update) REMOTE_ACT=add ;;
    delete)     REMOTE_ACT=del ;;
    *)          REMOTE_ACT=$ACTION ;;
  esac

  SSH_OPTS=("-o" "StrictHostKeyChecking=no")
  [ -n "${CLOUD_SSH_KEY}" ] && SSH_OPTS+=("-i" "$CLOUD_SSH_KEY")

  # Send: route-apply-cloud.sh add|del <ip> <via-macmini-backhaul>
  if ssh "${SSH_OPTS[@]}" "$CLOUD_SSH_DEST" "$CLOUD_SCRIPT" "$REMOTE_ACT" "$IP" "$BACKHAUL_GW_CLOUD" >>"$LOG_FILE" 2>&1; then
    log "cloud notified: $REMOTE_ACT $IP via $BACKHAUL_GW_CLOUD"
  else
    log "cloud notify failed: $REMOTE_ACT $IP"
  fi
}

case "$ACTION" in
  add|update)
    add_route
    notify_cloud
    ;;
  delete)
    del_route
    notify_cloud
    ;;
  *)
    log "unknown action: $ACTION"
    ;;
esac

exit 0

