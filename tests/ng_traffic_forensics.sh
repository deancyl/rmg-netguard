#!/system/bin/sh
# Read-only forensics: does the module force all traffic through the proxy?
M=/data/adb/modules/rmg_netguard
. $M/scripts/env.sh

echo "=== 1) module state / mode / integration / hijack ==="
cat $M/run/state.json 2>/dev/null
echo "mode=$(mode_get) integration=$(integ_get)"
hijack_check && echo "hijack=ATTACHED" || echo "hijack=DETACHED"
vpn_if_detect; echo "vpn=$VPN_UP if=$VPN_IF"
sh $M/scripts/config_toggle.sh status 2>/dev/null

echo "=== 2) active CMFA profile + routing rules (THE decisive part) ==="
UUID=$(meta_active_profile)
echo "active_profile=$UUID"
P="/data/data/com.github.metacubex.clash.meta/files/imported/$UUID/config.yaml"
echo "--- rules head (first 20 rule lines) ---"
grep -nE '^[[:space:]]*- ' "$P" 2>/dev/null | grep -E 'GEOIP|MATCH|DOMAIN|RULE-SET|IP-CIDR' | head -20
echo "--- GEOIP / MATCH / Final counts ---"
echo "GEOIP,CN lines: $(grep -c 'GEOIP,CN' "$P" 2>/dev/null)"
echo "GEOIP,LAN lines: $(grep -c 'GEOIP,LAN' "$P" 2>/dev/null)"
echo "MATCH lines: $(grep -c 'MATCH' "$P" 2>/dev/null)"
echo "--- dns section ---"
grep -n -A12 '^dns:' "$P" 2>/dev/null | head -16
echo "--- tun section ---"
grep -n -A8 '^tun:' "$P" 2>/dev/null | head -10
echo "--- mode (rule/global/direct) in config ---"
grep -nE '^mode:|^[[:space:]]*mode:' "$P" 2>/dev/null | head -3

echo "=== 3) mihomo external-controller API (live routing evidence) ==="
for ep in version configs connections; do
  echo "--- /$ep ---"
  curl -s --max-time 2 "http://127.0.0.1:9090/$ep" 2>/dev/null | head -c 400
  echo ""
done
echo "--- other controller ports ---"
grep -nE 'external-controller|secret' "$P" /data/data/com.github.metacubex.clash.meta/files/clash/override.json 2>/dev/null | head -5

echo "=== 4) routes (does traffic enter TUN?) ==="
ip route get 223.5.5.5 2>/dev/null | head -1
ip route get 114.114.114.114 2>/dev/null | head -1

echo "=== 5) AGH upstream (overseas DoH through TUN?) ==="
grep -n -A10 -E 'upstream_dns:|bootstrap_dns:' /data/adb/agh/bin/AdGuardHome.yaml 2>/dev/null | head -18

echo "=== 6) AGH querylog volume / clients ==="
querylog_stats
echo "--- client IP distribution (recent 200KB) ---"
tail -c 200000 "$AGH_QUERYLOG" 2>/dev/null | grep -o '"IP":"[^"]*"' | sort | uniq -c | sort -rn | head -6

echo "=== 7) module rules audit (GEOIP check) ==="
sh $M/scripts/rules_audit.sh 2>/dev/null | grep -E 'GEOIP|MATCH|WARN|INFO' | head -12

echo "=== 8) module never creates TUN / routes / proxy rules ==="
iptables -w -t nat -S OUTPUT 2>/dev/null | grep -v '^$' | head -8
ip rule 2>/dev/null | head -8
