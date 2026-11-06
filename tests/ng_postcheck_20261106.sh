#!/system/bin/sh
# Post-implementation verification (no nounset; MODDIR exported explicitly).
MODDIR=/data/adb/modules/rmg_netguard
export MODDIR
. "$MODDIR/scripts/env.sh"

echo "=== AGH 5591 real answer ==="
if probe_dns 5591; then echo "5591 OK"; else echo "5591 NO ANSWER"; fi
echo "AGH pid=$(pidof "$AGH_PROC")"
ports_check
echo "5591_up=$AGH_PORT_UP"

echo "=== network still fine (track B, AGH not in path) ==="
echo "dns_latency=$(dns_latency_ms)ms"
echo "domestic_egress=$(curl -s --max-time 5 https://myip.ipip.net 2>/dev/null | head -c 60)"
echo ""
echo "overseas_egress=$(curl -s --max-time 6 https://api.ipify.org 2>/dev/null | head -c 40)"

echo "=== config_toggle isolated smoke on device (block-list profile copy) ==="
T=/data/local/tmp/ng_ct_smoke
mkdir -p "$T/mod/scripts" "$T/profiles/abcd/config" "$T/mod/run"
cp "$MODDIR/scripts/config_toggle.sh" "$MODDIR/scripts/env.sh" "$T/mod/scripts/"
echo 'active_profile">abcd' > "$T/prefs.xml"
cp /data/data/com.github.metacubex.clash.meta/files/imported/91af3e78-5b33-4080-88e4-68e9abbe7b40/config.yaml "$T/profiles/abcd/config.yaml"
AGH_MODDIR=/nonexistent AGH_DIR=/nonexistent AGH_QUERYLOG=/nonexistent \
META_PREFS=$T/prefs.xml META_IMPORT=$T/profiles META_PKG=nope FLCLASH_PKG=nope \
sh "$T/mod/scripts/config_toggle.sh" apply 2>&1 | head -2
echo "patched_lines=$(grep -c '127.0.0.1:5591' "$T/profiles/abcd/config.yaml")"
echo "marker=$([ -f "$T/mod/run/backups/abcd.yaml.patched" ] && echo yes || echo no)"

echo "=== watchdog: no storm (last events) ==="
tail -n 8 "$MODDIR/run/events.log" 2>/dev/null
echo "=== module version + integration flag ==="
grep -E '^version' "$MODDIR/module.prop"
echo "integration=$(cat "$MODDIR/run/integration")"
sh "$MODDIR/scripts/config_toggle.sh" status
