#!/bin/bash
# route-apply-mac.sh add|del 10.8.0.x 10.255.0.1
set -euo pipefail
op="${1:-}"; ip="${2:-}"; gw="${3:-}"
if [[ -z "$op" || -z "$ip" || -z "$gw" ]]; then
  echo "usage: $0 add|del <10.8.0.x> <gw>" >&2
  exit 2
fi

plat=$(uname -s)
run(){ if [ "$(id -u)" -eq 0 ]; then /sbin/route -n "$@"; else sudo /sbin/route -n "$@"; fi; }

case "$op" in
  add)
    if [ "$plat" = "Darwin" ]; then
      run add -host "$ip" "$gw" 2>/dev/null || run change -host "$ip" "$gw" || true
    else
      /usr/sbin/ip route replace "$ip/32" via "$gw"
    fi
    ;;
  del)
    if [ "$plat" = "Darwin" ]; then
      run delete -host "$ip" 2>/dev/null || true
    else
      /usr/sbin/ip route del "$ip/32" 2>/dev/null || true
    fi
    ;;
  *)
    echo "unknown op: $op" >&2; exit 2 ;;
esac

exit 0

