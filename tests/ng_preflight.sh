#!/system/bin/sh
# Pre-implementation validation: config formats, override behavior, backup paths
M=/data/adb/modules/rmg_netguard
P="/data/data/com.github.metacubex.clash.meta/files/imported/91af3e78-5b33-4080-88e4-68e9abbe7b40/config.yaml"
A="/data/adb/agh/bin/AdGuardHome.yaml"

echo "=== 1) file ownership / SELinux / writability (truncate-rewrite needed) ==="
ls -lZ "$P" 2>/dev/null || ls -l "$P"
ls -lZ "$A" 2>/dev/null || ls -l "$A"
echo "profile dir writable by root: $([ -w "$(dirname "$P")" ] && echo yes || echo no)"
echo "agh yaml writable by root: $([ -w "$A" ] && echo yes || echo no)"

echo "=== 2) how does an existing GOOD profile spell the rules? ==="
GOOD="/data/data/com.follow.clash/files/profiles/350668055388360704.yaml"
grep -nE 'GEOIP,(CN|LAN|private)' "$GOOD" 2>/dev/null | head -8
echo "--- imported profiles with GEOIP,LAN ---"
grep -rnE 'GEOIP,(CN|LAN)' /data/data/com.github.metacubex.clash.meta/files/imported/*/config.yaml 2>/dev/null | head -8

echo "=== 3) MATCH insertion point ==="
grep -nE '^rules:|^- MATCH|^[[:space:]]*- MATCH' "$P" 2>/dev/null
sed -n '688,698p' "$P" 2>/dev/null

echo "=== 4) fake-ip-filter (pollution risk if nameserver becomes domestic) ==="
sed -n '16,43p' "$P" 2>/dev/null

echo "=== 5) override.json merge behavior: processing config vs imported ==="
echo "--- processing dir ---"
ls -la /data/data/com.github.metacubex.clash.meta/files/processing/ 2>/dev/null | head -10
for f in /data/data/com.github.metacubex.clash.meta/files/processing/*; do
  [ -f "$f" ] || continue
  echo "--- $f (dns.nameserver / 5591 / rules head) ---"
  grep -nE '^dns:|nameserver:|5591|127.0.0.1:5591|dns.cloudflare|dns.google' "$f" 2>/dev/null | head -10
done

echo "=== 6) AGH yaml structure around upstream/fallback/bootstrap ==="
sed -n '28,50p' "$A" 2>/dev/null
echo "--- AGH config uid/context + backup target ---"
ls -ld /data/adb/agh/bin "$M/run/backups" 2>/dev/null

echo "=== 7) module scripts to patch (current logic) ==="
grep -n -A6 'ns_line_count()' "$M/scripts/config_toggle.sh" 2>/dev/null
grep -n -A6 'check_rules_file()' "$M/scripts/rules_audit.sh" 2>/dev/null | head -12

echo "=== 8) current module version on device ==="
grep -E '^version' "$M/module.prop"
