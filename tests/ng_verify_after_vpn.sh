#!/system/bin/sh
# Run AFTER the user reopens Clash Meta VPN to load the edited profile.
# Verifies rule validity, domestic/overseas split, and no fallback to proxy.
MODDIR=/data/adb/modules/rmg_netguard
export MODDIR
. "$MODDIR/scripts/env.sh"
P=/data/data/com.github.metacubex.clash.meta/files/imported/91af3e78-5b33-4080-88e4-68e9abbe7b40/config.yaml

echo "=== profile on disk ==="
grep -nE '^- GEOIP|^- MATCH' "$P"
sed -n '44,47p' "$P"

echo "=== runtime: VPN up? ==="
vpn_if_detect
echo "vpn=$VPN_UP if=$VPN_IF"
client_detect
echo "client=$CLIENT"

echo "=== egress split (both must work) ==="
echo -n "domestic: "; curl -s --max-time 5 https://myip.ipip.net 2>/dev/null | head -c 70; echo ""
echo -n "overseas: "; curl -s --max-time 6 https://api.ipify.org 2>/dev/null | head -c 40; echo ""
echo "dns_latency=$(dns_latency_ms)ms"

echo "=== module state (integration must stay unpatched, no storm) ==="
sh "$MODDIR/scripts/config_toggle.sh" status
echo "--- INTEG events after 10:20 (should be none) ---"
awk '/^2026-11-06 1[0-9]:/ && /INTEG/' "$MODDIR/run/events.log" 2>/dev/null | tail -5
echo "--- rules audit ---"
sh "$MODDIR/scripts/rules_audit.sh" 2>/dev/null | grep '活动 profile'
