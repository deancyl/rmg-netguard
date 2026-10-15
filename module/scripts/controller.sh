#!/system/bin/sh
# RMG NetGuard v2.0 - dual-track controller. Performs ONE idempotent,
# health-gated iptables action per invocation. The guard loop (auto mode)
# and the WebUI (manual) are the only callers; flock serializes them.
#
# detach : remove nat OUTPUT -> AGH_CHAIN jump  (track B: VPN on)
# attach : re-insert jump at position 1         (track A: VPN off)
# status : print current topology
# __do <action> : internal (already lock-held) entry
# robust MODDIR derivation
case "$0" in */*) MODDIR="${0%/*}" ;; *) MODDIR=. ;; esac
MODDIR=$(cd "$MODDIR" 2>/dev/null && pwd) || MODDIR=""
case "$MODDIR" in */scripts) MODDIR="${MODDIR%/scripts}" ;; esac
[ -r "$MODDIR/scripts/env.sh" ] || MODDIR="/data/adb/modules/rmg_netguard"
. "$MODDIR/scripts/env.sh"

mkdir -p "$RUN" "$BKDIR" 2>/dev/null

# health gate: BOTH directions require AGH alive AND answering on 5591.
# (attaching the hijack with AGH dead = full DNS black hole; detaching
# with mihomo's AGH upstream dead = track B resolution failure.)
health_gate() {
  AGH_PID=$(pidof "$AGH_PROC" 2>/dev/null)
  [ -n "$AGH_PID" ] || { echo "GATE: AGH process not running"; return 1; }
  if ! probe_dns "$AGH_PORT"; then
    echo "GATE: AGH not answering on $AGH_PORT"
    return 1
  fi
  return 0
}

do_detach() {
  if hijack_check; then
    health_gate || { log_event "CTRL" "detach blocked: $(health_gate 2>&1)"; return 2; }
    if iptables -w -t nat -D OUTPUT -j "$AGH_CHAIN" 2>/dev/null; then
      touch "$FLAG_RESCUED" 2>/dev/null
      log_event "CTRL" "DETACHED OUTPUT -> $AGH_CHAIN (track B, VPN on)"
      echo "OK: detached (track B)"
      return 0
    fi
    echo "FAIL: iptables -D returned nonzero"
    return 1
  fi
  echo "OK: already detached"
  return 0
}

do_attach() {
  if ! hijack_check; then
    health_gate || { log_event "CTRL" "attach blocked: $(health_gate 2>&1)"; return 2; }
    if iptables -w -t nat -I OUTPUT 1 -j "$AGH_CHAIN" 2>/dev/null; then
      rm -f "$FLAG_RESCUED" 2>/dev/null
      log_event "CTRL" "ATTACHED OUTPUT -> $AGH_CHAIN at 1 (track A, VPN off)"
      echo "OK: attached (track A)"
      return 0
    fi
    echo "FAIL: iptables -I returned nonzero"
    return 1
  fi
  echo "OK: already attached"
  return 0
}

do_status() {
  if hijack_check; then
    echo "track A: hijack ATTACHED"
  else
    echo "track B: hijack DETACHED"
  fi
  vpn_if_detect
  echo "vpn=$VPN_UP if=$VPN_IF"
  client_detect
  echo "client=$CLIENT mode=$(mode_get) integration=$(integ_get) profile=$(integration_check)"
}

case "$1" in
  detach|attach)
    # serialize guard-loop vs WebUI invocations; actions are idempotent so
    # a lost race degrades to a no-op on retry.
    # v2.1: device toybox flock lacks -w (2026-10-15实测: silent no-op!) ->
    # probe support first; fallback = mkdir spin-lock (atomic, 5s timeout).
    if command -v flock >/dev/null 2>&1 && flock -w 1 "$LOCK" true 2>/dev/null; then
      flock -w 5 "$LOCK" sh "$MODDIR/scripts/controller.sh" __do "$1"
      rc=$?
    else
      n=0
      while ! mkdir "$LOCK.d" 2>/dev/null; do
        n=$(( n + 1 ))
        [ "$n" -ge 25 ] && { echo "FAIL: lock busy"; exit 3; }
        sleep 0.2 2>/dev/null || sleep 1
      done
      "do_$1"
      rc=$?
      rmdir "$LOCK.d" 2>/dev/null
    fi
    exit "$rc"
    ;;
  __do)
    "do_$2"
    exit $?
    ;;
  status|*)
    do_status
    ;;
esac
exit 0
