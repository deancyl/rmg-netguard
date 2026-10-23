#!/system/bin/sh
# RMG NetGuard v2.0 - WebUI action dispatcher. Every WebUI button calls
# exactly one command here; output is plain text rendered by index.html.
# robust MODDIR derivation
case "$0" in */*) MODDIR="${0%/*}" ;; *) MODDIR=. ;; esac
MODDIR=$(cd "$MODDIR" 2>/dev/null && pwd) || MODDIR=""
case "$MODDIR" in */scripts) MODDIR="${MODDIR%/scripts}" ;; esac
[ -r "$MODDIR/scripts/env.sh" ] || MODDIR="/data/adb/modules/rmg_netguard"
. "$MODDIR/scripts/env.sh"

case "$1" in
  status)
    cat "$LOG_STATE" 2>/dev/null
    echo "---"
    sh "$MODDIR/scripts/controller.sh" status 2>/dev/null
    # v2.1: probes only make sense while AGH is running; SKIP instantly
    # otherwise (no 2x2s nc wait -> no WebUI freeze on "刷新全部").
    if agh_running; then
      r=$(filter_probe_pair)
      p=${r%% *}; p=${p#P=}
      w=${r##* }; w=${w#W=}
      echo "filter_probe=$p"
      echo "filter_probe_wedge=$w"
    else
      echo "filter_probe=SKIP"
      echo "filter_probe_wedge=SKIP"
      echo "agh_state=not_running"
    fi
    echo "querylog_age=$(querylog_age)"
    sh "$MODDIR/scripts/config_toggle.sh" status 2>/dev/null
    ;;
  status_fast)
    # v2.2: auto-refresh path. Same shape as `status` minus the DNS filter
    # probes (the only slow part: 2x2s nc). Used by the WebUI's 30s poll and
    # by the click-to-refresh button, so the panel never sits locked for
    # seconds right after opening. Probe badges simply keep their last value.
    cat "$LOG_STATE" 2>/dev/null
    echo "---"
    sh "$MODDIR/scripts/controller.sh" status 2>/dev/null
    echo "querylog_age=$(querylog_age)"
    sh "$MODDIR/scripts/config_toggle.sh" status 2>/dev/null
    ;;
  stats)
    echo "== AGH querylog 近段统计 =="
    querylog_stats
    exit $?
    ;;
  log)
    echo "== events.log 最近 20 行 =="
    tail -n 20 "$LOG_EVENTS" 2>/dev/null
    exit $?
    ;;
  probe)
    sh "$MODDIR/scripts/probe.sh" 2>&1
    exit $?
    ;;
  audit)
    sh "$MODDIR/scripts/rules_audit.sh" 2>&1
    exit $?
    ;;
  mode_observe)
    printf '%s\n' observe > "$MODE_FILE" || {
      echo "FAIL: cannot write mode file"
      exit 1
    }
    log_event "MODE" "switched to observe (WebUI)"
    echo "OK: mode=observe"
    ;;
  mode_auto)
    printf '%s\n' auto > "$MODE_FILE" || {
      echo "FAIL: cannot write mode file"
      exit 1
    }
    log_event "MODE" "switched to auto dual-track (WebUI)"
    echo "OK: mode=auto"
    ;;
  integ_on)
    out=$(sh "$MODDIR/scripts/config_toggle.sh" apply 2>&1)
    rc=$?
    [ "$rc" = "0" ] && { echo on > "$INTEG_FILE"; log_event "INTEG" "integration enabled (WebUI)"; }
    echo "$out"
    exit "$rc"
    ;;
  integ_off)
    out=$(sh "$MODDIR/scripts/config_toggle.sh" revert 2>&1)
    rc=$?
    [ "$rc" = "0" ] && { echo off > "$INTEG_FILE"; log_event "INTEG" "integration disabled (WebUI)"; }
    echo "$out"
    exit "$rc"
    ;;
  detach)
    sh "$MODDIR/scripts/controller.sh" detach 2>&1
    exit $?
    ;;
  attach)
    sh "$MODDIR/scripts/controller.sh" attach 2>&1
    exit $?
    ;;
  *)
    echo "Usage: webui.sh {status|status_fast|stats|log|probe|audit|mode_observe|mode_auto|integ_on|integ_off|detach|attach}"
    exit 1
    ;;
esac
exit 0
