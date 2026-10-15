#!/system/bin/sh
# RMG NetGuard v2.0 - uninstall cleanup. Restores whatever this module
# changed, nothing else:
#   1. stops the guard loop
#   2. reverts the Meta profile NS5591 patch (if integration was applied)
#   3. re-attaches the AGH hijack if THIS module detached it
MODDIR=${0%/*}
RUN="$MODDIR/run"
BKDIR="$RUN/backups"

# stop guard (v1.0.1: PID-reuse guard -- cmdline verified before kill)
if [ -f "$RUN/guard.pid" ]; then
  pid=$(cat "$RUN/guard.pid" 2>/dev/null)
  if [ -n "$pid" ] && [ -r "/proc/$pid/cmdline" ] \
     && grep -aq "rmg_netguard/scripts/guard.sh" "/proc/$pid/cmdline" 2>/dev/null; then
    kill "$pid" 2>/dev/null
  fi
fi
pkill -f "rmg_netguard/scripts/guard.sh" 2>/dev/null

# 2. revert DNS integration patch: restore every profile backup we hold
#    (v2.0: integration backups live in $RUN/backups/<uuid>.yaml.orig)
if [ -d "$BKDIR" ]; then
  for orig in "$BKDIR"/*.yaml.orig; do
    [ -f "$orig" ] || continue
    uuid=${orig##*/}; uuid=${uuid%.yaml.orig}
    tgt="/data/data/com.github.metacubex.clash.meta/files/imported/$uuid/config.yaml"
    if [ -f "$tgt" ] && grep -q "127.0.0.1:5591" "$tgt"; then
      if grep -q "127.0.0.1:5591" "$orig"; then
        echo "NetGuard: backup for $uuid contains NS5591, skipping (corrupt?)" >&2
      else
        cat "$orig" > "$tgt" \
          && echo "NetGuard: reverted profile $uuid to pre-integration state" >&2
      fi
    fi
  done
fi

# 3. if we detached the AGH hijack, restore it so the system returns to its
#    pre-module state
if [ -f "$RUN/rescue.removed" ]; then
  if ! iptables -w -t nat -C OUTPUT -j ADGUARD_REDIRECT_DNS 2>/dev/null; then
    iptables -w -t nat -I OUTPUT 1 -j ADGUARD_REDIRECT_DNS 2>/dev/null \
      && echo "NetGuard: restored AGH redirect chain (was detached by rescue)" >&2
  fi
fi

rm -rf "$RUN" 2>/dev/null
exit 0
