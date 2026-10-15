#!/system/bin/sh
# RMG NetGuard - service.sh (late_start service mode).
# Compatible with KSU late-load: service.sh IS executed in late-load mode;
# we deliberately avoid post-fs-data.sh / initrc (unavailable in late-load).
MODDIR=${0%/*}
RUN="$MODDIR/run"
mkdir -p "$RUN" 2>/dev/null

# singleton: root daemons survive KSU soft reboot, so kill any stale guard
# from the previous framework session before starting a new one.
# v1.0.1: PID-reuse guard -- only kill when cmdline matches our guard script.
if [ -f "$RUN/guard.pid" ]; then
  oldpid=$(cat "$RUN/guard.pid" 2>/dev/null)
  if [ -n "$oldpid" ] && [ "$oldpid" != "$$" ] && [ -r "/proc/$oldpid/cmdline" ]; then
    if grep -aq "rmg_netguard/scripts/guard.sh" "/proc/$oldpid/cmdline" 2>/dev/null; then
      kill "$oldpid" 2>/dev/null
    fi
  fi
fi
pkill -f "rmg_netguard/scripts/guard.sh" 2>/dev/null
sleep 1

# start observation loop in background (service.sh must not block late_start)
sh "$MODDIR/scripts/guard.sh" &
echo $! > "$RUN/guard.pid"

# startup marker
. "$MODDIR/scripts/env.sh"
log_event "START" "NetGuard guard started (pid $(cat "$RUN/guard.pid" 2>/dev/null)) interval=${INTERVAL}s"
exit 0
