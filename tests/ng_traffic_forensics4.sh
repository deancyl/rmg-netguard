#!/system/bin/sh
# Round 4: live connections through mihomo + integration patch failure reason
M=/data/adb/modules/rmg_netguard
P="/data/data/com.github.metacubex.clash.meta/files/imported/91af3e78-5b33-4080-88e4-68e9abbe7b40/config.yaml"

echo "=== mihomo (pid 876) established connections: peer distribution ==="
ss -tnp 2>/dev/null | grep -E 'pid=876' | head -25
echo "--- count by peer port ---"
ss -tnp 2>/dev/null | grep -E 'pid=876' | awk '{print $4}' | sed 's/.*://' | sort | uniq -c | sort -rn | head -8
echo "--- total established sockets owned by mihomo ---"
ss -tnp 2>/dev/null | grep -cE 'pid=876'

echo "=== Syncthing (backup traffic candidate) peers ==="
ss -tnp 2>/dev/null | grep -E 'pid=21247' | head -8

echo "=== integration patch: why unpatched? name server format ==="
echo "--- ns_line_count expectation: ^[[:space:]]*nameserver: \[ ---"
grep -nE '^[[:space:]]*nameserver: \[' "$P" 2>/dev/null | head -3
echo "(count above = $(grep -cE '^[[:space:]]*nameserver: \[' "$P" 2>/dev/null))"
echo "--- actual nameserver block (block-list form) ---"
sed -n '44,47p' "$P" 2>/dev/null
echo "--- do_apply dry reason ---"
sh $M/scripts/config_toggle.sh apply 2>&1 | head -3
echo "--- status after apply attempt (read-only outcome) ---"
sh $M/scripts/config_toggle.sh status 2>/dev/null

echo "=== override.json (rules/dns overrides present?) ==="
cat /data/data/com.github.metacubex.clash.meta/files/clash/override.json 2>/dev/null | head -c 500
echo ""

echo "=== per-uid traffic (netstats sample) ==="
dumpsys netstats 2>/dev/null | grep -E '^\s*uid=' | head -8
