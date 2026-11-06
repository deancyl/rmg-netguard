#!/system/bin/sh
# Explicit proof: watchdog no longer patches an unpatched profile without marker.
MODDIR=/data/adb/modules/rmg_netguard
export MODDIR
. "$MODDIR/scripts/env.sh"
P=/data/data/com.github.metacubex.clash.meta/files/imported/91af3e78-5b33-4080-88e4-68e9abbe7b40/config.yaml
BEFORE=$(md5sum "$P" | cut -d' ' -f1)
E0=$(grep -c 'INTEG' "$MODDIR/run/events.log" 2>/dev/null)
sh "$MODDIR/scripts/config_toggle.sh" auto
AFTER=$(md5sum "$P" | cut -d' ' -f1)
E1=$(grep -c 'INTEG' "$MODDIR/run/events.log" 2>/dev/null)
echo "integration=$(integ_get)"
echo "profile_unchanged=$([ "$BEFORE" = "$AFTER" ] && echo yes || echo NO)"
echo "integ_events: $E0 -> $E1 (delta=$((E1-E0)))"
echo "status: $(sh "$MODDIR/scripts/config_toggle.sh" status | tail -1)"
