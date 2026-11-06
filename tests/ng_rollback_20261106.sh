#!/system/bin/sh
# Rollback for the 2026-11-06 traffic config batch.
# Restores CMFA active profile + AGH yaml from the backups taken by
# ng_apply_20261106.sh, then restarts AGH. Module scripts stay at v2.2.5.
# Usage: adb shell "su -c 'sh /data/local/tmp/ng_rollback_20261106.sh'"
M=/data/adb/modules/rmg_netguard
BK=$M/run/backups
P=/data/data/com.github.metacubex.clash.meta/files/imported/91af3e78-5b33-4080-88e4-68e9abbe7b40/config.yaml
A=/data/adb/agh/bin/AdGuardHome.yaml

[ -r "$BK/91af3e78-config.yaml.bak-20261106" ] || { echo "ABORT: profile backup missing"; exit 1; }
[ -r "$BK/AdGuardHome.yaml.bak-20261106" ] || { echo "ABORT: agh backup missing"; exit 1; }

cat "$BK/91af3e78-config.yaml.bak-20261106" > "$P"
cat "$BK/AdGuardHome.yaml.bak-20261106" > "$A"
kill $(pidof AdGuardHome) 2>/dev/null
sleep 2
/data/adb/agh/scripts/tool.sh stop >/dev/null 2>&1
sleep 1
/data/adb/agh/scripts/tool.sh start >/dev/null 2>&1
sleep 3
echo "restored: GEOIP_rule=$(grep -c '^- GEOIP,CN,DIRECT$' "$P") overseas_agh=$(grep -cE '1\.1\.1\.1|8\.8\.8\.8' "$A")"
echo "ROLLBACK DONE - reopen Clash Meta VPN to load the restored profile"
