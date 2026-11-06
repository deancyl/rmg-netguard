#!/system/bin/sh
# 2026-11-06 one-shot implementation (reversible, backed up).
# A) hot-deploy v2.2.5 module scripts
# B) CMFA active profile: GEOIP,CN,DIRECT + domestic DoH nameserver
# C) AGH: remove overseas fallback/bootstrap DNS, restart (idle window)
# Does NOT restart VPN / change module mode / integration flag / hijack.
# note: no `set -u` here -- env.sh reads $MODDIR when sourced below.
M=/data/adb/modules/rmg_netguard
P=/data/data/com.github.metacubex.clash.meta/files/imported/91af3e78-5b33-4080-88e4-68e9abbe7b40/config.yaml
A=/data/adb/agh/bin/AdGuardHome.yaml
BK=$M/run/backups
TS=20261106
T=/data/local/tmp

echo "=== 0) preconditions ==="
[ -r "$P" ] || { echo "ABORT: CMFA profile missing"; exit 1; }
[ -r "$A" ] || { echo "ABORT: AGH yaml missing"; exit 1; }
grep -q 'GEOIP,CN,DIRECT' "$P" && { echo "ABORT: GEOIP rule already present"; exit 1; }
mkdir -p "$BK" || { echo "ABORT: backup dir"; exit 1; }

echo "=== 1) backups (cp -a keeps uid/context) ==="
cp -a "$P" "$BK/91af3e78-config.yaml.bak-$TS" || { echo "ABORT: profile backup"; exit 1; }
cp -a "$A" "$BK/AdGuardHome.yaml.bak-$TS" || { echo "ABORT: agh backup"; exit 1; }
ls -lZ "$BK/91af3e78-config.yaml.bak-$TS" "$BK/AdGuardHome.yaml.bak-$TS"

echo "=== 2) deploy v2.2.5 module scripts (truncate-rewrite) ==="
for f in config_toggle.sh rules_audit.sh; do
  cat "$T/$f" > "$M/scripts/$f" || { echo "ABORT: $f"; exit 1; }
done
cat "$T/index.html" > "$M/webroot/index.html" || { echo "ABORT: index"; exit 1; }
cat "$T/module.prop" > "$M/module.prop" || { echo "ABORT: prop"; exit 1; }
chmod 755 "$M/scripts/config_toggle.sh" "$M/scripts/rules_audit.sh"
echo "version=$(sed -n 's/^version=//p' "$M/module.prop")"

echo "=== 3) generate CMFA profile patch ==="
awk '
  BEGIN { done = 0; inns = 0 }
  /^- MATCH,/ && !done { print "- GEOIP,CN,DIRECT"; done = 1 }
  /^  nameserver:[[:space:]]*$/ { inns = 1; print; next }
  inns && /^  - https:\/\/dns\.cloudflare\.com\/dns-query/ { print "  - https://doh.pub/dns-query"; next }
  inns && /^  - https:\/\/dns\.google\/dns-query/ { print "  - https://dns.alidns.com/dns-query"; next }
  inns && !/^  - / { inns = 0 }
  { print }
' "$P" > "$T/cmfa.new" || { echo "ABORT: cmfa awk"; exit 1; }

echo "old_lines=$(wc -l < "$P") new_lines=$(wc -l < "$T/cmfa.new")"
echo "GEOIP_rule=$(grep -c '^- GEOIP,CN,DIRECT$' "$T/cmfa.new") MATCH=$(grep -c '^- MATCH,' "$T/cmfa.new")"
echo "overseas_ns_left=$(grep -cE '^  - https://dns\.(cloudflare|google)/dns-query' "$T/cmfa.new")"
echo "domestic_ns=$(grep -cE '^  - https://(doh\.pub|dns\.alidns\.com)/dns-query' "$T/cmfa.new")"
[ "$(grep -c '^- GEOIP,CN,DIRECT$' "$T/cmfa.new")" = 1 ] || { echo "ABORT: GEOIP rule count"; exit 1; }
[ "$(grep -c '^- MATCH,' "$T/cmfa.new")" = 1 ] || { echo "ABORT: MATCH count"; exit 1; }
[ "$(grep -cE '^  - https://dns\.(cloudflare|google)/dns-query' "$T/cmfa.new")" = 0 ] || { echo "ABORT: overseas nameserver remains"; exit 1; }
[ "$(wc -l < "$T/cmfa.new")" -eq "$(( $(wc -l < "$P") + 1 ))" ] || { echo "ABORT: line delta"; exit 1; }

echo "=== 4) generate AGH yaml patch ==="
awk '
  /^  bootstrap_dns:/ { sec = "boot"; print; next }
  /^  fallback_dns:/ { sec = "fall"; print; next }
  sec == "boot" && /^    - 1\.1\.1\.1$/ { next }
  sec == "boot" && /^    - 8\.8\.8\.8$/ { next }
  sec == "fall" && /^    - https:\/\/1\.1\.1\.1\/dns-query$/ { if (!e) { print "    - https://doh.pub/dns-query"; e = 1 } next }
  sec == "fall" && /^    - https:\/\/8\.8\.8\.8\/dns-query$/ { next }
  /^  [a-z_]+:/ { sec = "" }
  { print }
' "$A" > "$T/agh.new" || { echo "ABORT: agh awk"; exit 1; }
echo "old_lines=$(wc -l < "$A") new_lines=$(wc -l < "$T/agh.new")"
echo "overseas_left=$(grep -cE '1\.1\.1\.1|8\.8\.8\.8' "$T/agh.new") domestic_fallback=$(grep -c 'doh.pub' "$T/agh.new")"
[ "$(grep -cE '1\.1\.1\.1|8\.8\.8\.8' "$T/agh.new")" = 0 ] || { echo "ABORT: overseas dns remains"; exit 1; }
[ "$(grep -c 'doh.pub' "$T/agh.new")" -ge 1 ] || { echo "ABORT: domestic fallback missing"; exit 1; }

echo "=== 5) write rollback script BEFORE applying ==="
cat > "$T/ng_rollback_20261106.sh" <<'EOS'
#!/system/bin/sh
M=/data/adb/modules/rmg_netguard
BK=$M/run/backups
cat "$BK/91af3e78-config.yaml.bak-20261106" > /data/data/com.github.metacubex.clash.meta/files/imported/91af3e78-5b33-4080-88e4-68e9abbe7b40/config.yaml
cat "$BK/AdGuardHome.yaml.bak-20261106" > /data/adb/agh/bin/AdGuardHome.yaml
kill $(pidof AdGuardHome) 2>/dev/null
sleep 2
/data/adb/agh/scripts/tool.sh start >/dev/null 2>&1
echo "ROLLBACK DONE (module scripts stay at v2.2.5; VPN restart still needed)"
EOS
chmod 755 "$T/ng_rollback_20261106.sh"
echo "rollback_ready=$T/ng_rollback_20261106.sh"

echo "=== 6) apply (truncate-rewrite preserves inode/uid/SELinux) ==="
cat "$T/cmfa.new" > "$P" || { echo "ABORT: write cmfa"; exit 1; }
cat "$T/agh.new" > "$A" || { echo "ABORT: write agh"; exit 1; }
ls -lZ "$P" "$A"

echo "=== 7) restart AGH (zero network impact: hijack detached, querylog empty) ==="
OLDPID=$(pidof AdGuardHome)
kill "$OLDPID" 2>/dev/null
sleep 2
/data/adb/agh/scripts/tool.sh stop >/dev/null 2>&1
sleep 1
/data/adb/agh/scripts/tool.sh start >/dev/null 2>&1
sleep 4
NEWPID=$(pidof AdGuardHome)
echo "agh_pid: $OLDPID -> $NEWPID"

echo "=== 8) post-check ==="
MODDIR=$M
export MODDIR
. $M/scripts/env.sh
probe_dns 5591 && echo "AGH 5591 OK" || echo "AGH 5591 NO ANSWER(!)"
echo "--- CMFA rules tail ---"
grep -nE '^- GEOIP|^- MATCH' "$P"
echo "--- CMFA nameserver ---"
sed -n '44,47p' "$P"
echo "--- AGH dns sections ---"
sed -n '32,45p' "$A"
echo "--- module integration status (must remain unpatched; no storm) ---"
sh $M/scripts/config_toggle.sh status
sh $M/scripts/config_toggle.sh auto
echo "--- rules_audit on active profile (expect OK/INFO, no GEOIP WARN) ---"
sh $M/scripts/rules_audit.sh 2>/dev/null | grep -E '活动 profile|WARN|审计完成' | head -6
echo "IMPLEMENT_DONE"
