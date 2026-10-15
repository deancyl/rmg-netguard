#!/system/bin/sh
# RMG NetGuard v2.0 - observation + optional dual-track control loop.
#
# modes ($RUN/mode):
#   observe (default) : NEVER touches iptables. v1.0.1 behaviour.
#   auto              : on confirmed VPN transitions (hysteresis) toggles the
#                       single hijack jump via controller.sh, health-gated.
# Integration watchdog: when $RUN/integration=on, re-applies the profile
# NS5591 patch if a subscription update overwrote it (config_toggle auto).
# robust MODDIR derivation: handles absolute/relative/bare invocation
case "$0" in */*) MODDIR="${0%/*}" ;; *) MODDIR=. ;; esac
MODDIR=$(cd "$MODDIR" 2>/dev/null && pwd) || MODDIR=""
case "$MODDIR" in */scripts) MODDIR="${MODDIR%/scripts}" ;; esac
[ -r "$MODDIR/scripts/env.sh" ] || MODDIR="/data/adb/modules/rmg_netguard"
. "$MODDIR/scripts/env.sh"

# load user tunables if present. Strict allowlist: only blank lines,
# comments and VAR=<safe-chars> assignments are sourced; anything else is
# rejected (prevents arbitrary code injection via a writable config path).
if [ -f "$RUN/config" ]; then
  if grep -qvE '^([[:space:]]*(#|$)|[A-Z_][A-Z0-9_]*=[A-Za-z0-9_.:/ -]*$)' "$RUN/config" 2>/dev/null; then
    log_event "WARN" "run/config rejected (unsafe line), defaults in effect"
  else
    . "$RUN/config"
  fi
fi

mkdir -p "$RUN" "$BKDIR"

# v2.1: self-register pid (service.sh also writes it; this makes manual
# restarts via WebUI/shell equally trackable and killable)
echo $$ > "$PID_GUARD" 2>/dev/null

LAST_STATE=""
LAST_DNS_MS=""
VPN_ON_N=0
VPN_OFF_N=0
ROUND=0
IDLE=0

classify() {
  # classify -> RISK_COEXIST | INCONSISTENT | DOWN_PORT | NORMAL
  if [ "$VPN_UP" = "1" ] && [ "$HIJACK" = "1" ]; then
    echo "RISK_COEXIST"
  elif [ "$AGH_PID" != "0" ] && [ "$HIJACK" != "1" ]; then
    echo "INCONSISTENT"
  elif [ "$HIJACK" = "1" ] && [ "$AGH_PORT_UP" != "1" ]; then
    echo "DOWN_PORT"
  else
    echo "NORMAL"
  fi
}

# current serving track: A = hijack attached; B = hijack detached + VPN up
track_of() {
  if [ "$HIJACK" = "1" ]; then echo A; else
    [ "$VPN_UP" = "1" ] && echo B || echo "-"
  fi
}

while :; do
  ROUND=$(( ROUND + 1 ))
  MODE=$(mode_get)

  vpn_if_detect
  HIJACK=0
  if hijack_check; then HIJACK=1; fi
  AGH_PID=$(pidof "$AGH_PROC" 2>/dev/null)
  [ -n "$AGH_PID" ] || AGH_PID=0
  client_detect

  # ---- v2.1 idle backoff: nothing installed to watch -> near-zero cost ----
  # (no DNS curl, no watchdogs, no audit, no controller; long sleep)
  if ! target_present && [ "$HIJACK" != "1" ]; then
    if [ "$IDLE" != "1" ]; then
      IDLE=1
      log_event "IDLE" "no AGH / no Clash present -> idle backoff (${IDLE_INTERVAL}s), pure observation"
    fi
    write_state "NORMAL" "$VPN_UP" "$VPN_IF" "$HIJACK" "$AGH_PID" 0 0 "n/a" "$CLIENT" "$MODE" "-"
    sleep "$IDLE_INTERVAL"
    continue
  fi
  if [ "$IDLE" = "1" ]; then
    IDLE=0
    log_event "IDLE" "target re-appeared -> back to normal ${INTERVAL}s loop"
  fi

  ports_check

  ST=$(classify)
  TRACK=$(track_of)

  # DNS latency probe throttled: curl only on state transition or every
  # DNS_EVERY rounds; breach events only on freshly measured values.
  DNS_FRESH=0
  if [ "$ST" != "$LAST_STATE" ] || [ -z "$LAST_DNS_MS" ] || [ $(( ROUND % DNS_EVERY )) -eq 1 ]; then
    DNS_MS=$(dns_latency_ms)
    LAST_DNS_MS=$DNS_MS
    DNS_FRESH=1
  else
    DNS_MS=$LAST_DNS_MS
  fi

  write_state "$ST" "$VPN_UP" "$VPN_IF" "$HIJACK" "$AGH_PID" "$AGH_PORT_UP" \
              "$MIHOMO_PORT_UP" "$DNS_MS" "$CLIENT" "$MODE" "$TRACK"

  # event: state transition
  if [ "$ST" != "$LAST_STATE" ] && [ -n "$LAST_STATE" ]; then
    log_event "STATE" "$LAST_STATE -> $ST (vpn=$VPN_UP if=$VPN_IF hijack=$HIJACK client=$CLIENT mode=$MODE track=$TRACK)"
  fi
  LAST_STATE=$ST

  # event: DNS latency breach (fresh measurements only)
  if [ "$DNS_FRESH" = "1" ]; then
    case "$DNS_MS" in
      timeout)
        log_event "DNS" "resolve timeout (${CURL_TARGET}, max ${CURL_TIMEOUT}s) vpn=$VPN_UP hijack=$HIJACK"
        ;;
      ''|*[!0-9]*) : ;;
      *)
        if [ "$DNS_MS" -gt "$DNS_WARN_MS" ]; then
          log_event "DNS" "slow resolve ${DNS_MS}ms > ${DNS_WARN_MS}ms (vpn=$VPN_UP hijack=$HIJACK)"
        fi
        ;;
    esac
  fi

  # ---- dual-track controller (auto mode only) ----
  if [ "$MODE" = "auto" ]; then
    if [ "$VPN_UP" = "1" ]; then
      VPN_ON_N=$(( VPN_ON_N + 1 )); VPN_OFF_N=0
    else
      VPN_OFF_N=$(( VPN_OFF_N + 1 )); VPN_ON_N=0
    fi
    # confirmed state + hysteresis reached -> single health-gated action
    if [ "$VPN_ON_N" -ge "$HYSTERESIS" ] && [ "$HIJACK" = "1" ]; then
      out=$(sh "$MODDIR/scripts/controller.sh" detach 2>&1)
      rc=$?
      log_event "CTRL" "auto detach rc=$rc: $out"
      [ "$rc" = "0" ] && VPN_ON_N=0
    elif [ "$VPN_OFF_N" -ge "$HYSTERESIS" ] && [ "$HIJACK" != "1" ]; then
      out=$(sh "$MODDIR/scripts/controller.sh" attach 2>&1)
      rc=$?
      log_event "CTRL" "auto attach rc=$rc: $out"
      [ "$rc" = "0" ] && VPN_OFF_N=0
    fi
  else
    VPN_ON_N=0; VPN_OFF_N=0
  fi

  # ---- integration watchdog (independent of mode) ----
  if [ $(( ROUND % 5 )) -eq 0 ]; then
    sh "$MODDIR/scripts/config_toggle.sh" auto >/dev/null 2>&1
  fi

  # ---- AGH health watchdog (every 10 rounds, deduped per episode) ----
  # querylog mtime frozen >=30min while AGH is running suggests the logging
  # buffer stopped flushing (degradation seen 2026-10-15 on a pre-soft-reboot
  # survivor). Zero-fork cost (one stat). Confirm via probe.sh dual probes.
  if [ $(( ROUND % 10 )) -eq 0 ] && [ "$AGH_PID" != "0" ]; then
    age=$(querylog_age)
    if [ "$age" -ge 1800 ] 2>/dev/null; then
      if [ ! -f "$RUN/qlog_stale.flag" ]; then
        touch "$RUN/qlog_stale.flag"
        log_event "HEALTH" "querylog stale ${age}s -- AGH logging idle or degraded; run probe.sh for dual filter probes"
      fi
    else
      rm -f "$RUN/qlog_stale.flag" 2>/dev/null
    fi
  fi

  # periodic rules audit (read-only); also fires once on ENTERING
  # RISK_COEXIST so WARN lines and the risk state land in the same frame
  if [ $(( ROUND % AUDIT_EVERY )) -eq 1 ] \
     || { [ "$ST" = "RISK_COEXIST" ] && [ "$LAST_STATE" != "RISK_COEXIST" ] && [ -n "$LAST_STATE" ]; }; then
    sh "$MODDIR/scripts/rules_audit.sh" > "$LOG_AUDIT.tmp" 2>&1 && mv "$LOG_AUDIT.tmp" "$LOG_AUDIT"
  fi

  sleep "$INTERVAL"
done
