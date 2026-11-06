#!/system/bin/sh
# Round 2: are there ANY domestic DIRECT rules? Live egress evidence.
M=/data/adb/modules/rmg_netguard
P="/data/data/com.github.metacubex.clash.meta/files/imported/91af3e78-5b33-4080-88e4-68e9abbe7b40/config.yaml"

echo "=== rule inventory ==="
echo "total rule lines: $(grep -cE '^[[:space:]]*- [A-Z]' "$P" 2>/dev/null)"
echo "DIRECT rule lines: $(grep -c 'DIRECT' "$P" 2>/dev/null)"
echo "--- all DIRECT lines (context) ---"
grep -n 'DIRECT' "$P" 2>/dev/null | head -45
echo "--- CN / geosite / domestic hints ---"
grep -niE 'GEOSITE,?(CN|PRIVATE)|DOMAIN-SUFFIX,cn|RULE-SET,[^,]*(cn|china|direct)|GEOIP,CN' "$P" 2>/dev/null | head -20
echo "--- MATCH line and proxy-groups tail ---"
grep -n 'MATCH' "$P" 2>/dev/null | head -3
grep -n -A6 'proxy-groups:' "$P" 2>/dev/null | head -12
echo "--- rule-providers / RULE-SET names ---"
grep -nE '^[[:space:]]*- RULE-SET' "$P" 2>/dev/null | sed 's/.*RULE-SET,\([^,]*\),.*/\1/' | sort -u | head -30
echo "--- nameserver / 5591 in profile ---"
grep -nE 'nameserver|5591' "$P" 2>/dev/null | head -12

echo "=== live egress IP (domestic services: if proxied, IP != local ISP) ==="
for u in "https://myip.ipip.net" "http://members.3322.org/dyndns/getip" "https://www.taobao.com/help/getip.php"; do
  echo "--- $u"
  curl -s --max-time 5 "$u" 2>/dev/null | head -c 220
  echo ""
done

echo "=== AGH querylog file state ==="
stat -c '%y %s %n' /data/adb/agh/bin/data/querylog.json 2>/dev/null
echo "=== CMFA runtime mode hints ==="
grep -oE '"(mode|clashMode|modeName)"[^,}]*' /data/data/com.github.metacubex.clash.meta/shared_prefs/*.xml 2>/dev/null | head -8
ls /data/data/com.github.metacubex.clash.meta/files/clash/ 2>/dev/null | head -10

echo "=== AGH recent upstream errors (proxy-bound DNS amplification) ==="
tail -n 200 /data/adb/agh/bin/data/querylog.json 2>/dev/null | grep -ci 'IsFiltered' || true
