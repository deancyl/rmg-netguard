#!/system/bin/sh
# Round 3: are the DIRECT rule-sets actually populated? Is overseas proxied?
P="/data/data/com.github.metacubex.clash.meta/files/imported/91af3e78-5b33-4080-88e4-68e9abbe7b40/config.yaml"
BASE="/data/data/com.github.metacubex.clash.meta/files"

echo "=== rule-providers definitions (cn / cn-ip) ==="
grep -n -A24 '^rule-providers:' "$P" 2>/dev/null | head -50

echo "=== rule-provider files on disk ==="
find "$BASE" -type f \( -name '*.yaml' -o -name '*.yml' -o -name '*.list' -o -name '*.txt' -o -name '*.mrs' \) 2>/dev/null | grep -iE 'cn|rule|provider' | head -20
echo "--- any provider dir listing ---"
find "$BASE" -type d 2>/dev/null | head -20
echo "--- cn/cn-ip file size+mtime if present ---"
for f in $(find "$BASE" -type f 2>/dev/null | grep -iE '/(cn|cn-ip)(\.|$)'); do
  stat -c '%y %s %n' "$f" 2>/dev/null
  echo "  lines: $(wc -l < "$f" 2>/dev/null)"
done

echo "=== dns nameserver block (full) ==="
sed -n '40,60p' "$P" 2>/dev/null

echo "=== egress comparison: overseas endpoint ==="
echo "--- ipify ---"; curl -s --max-time 6 https://api.ipify.org 2>/dev/null | head -c 120; echo ""
echo "--- ipinfo ---"; curl -s --max-time 6 https://ipinfo.io/json 2>/dev/null | head -c 300; echo ""

echo "=== mihomo listening sockets (API / mixed port) ==="
(ss -lntp 2>/dev/null || netstat -lntp 2>/dev/null) | grep -E '127.0.0.1|0.0.0.0' | head -15

echo "=== CMFA selected proxy group hints ==="
grep -rao '节点选择[^<]*\|自动选择[^<]*\|剩余流量[^<]*' /data/data/com.github.metacubex.clash.meta/shared_prefs/ 2>/dev/null | head -10

echo "=== per-app traffic hint: VPN uid totals (top 5) ==="
dumpsys netstats 2>/dev/null | grep -m5 -E 'uid=.*(rxBytes|txBytes)' | head -5
