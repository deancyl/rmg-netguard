#!/system/bin/sh
# Pre-change validation: GeoIP database categories + backup space + AGH idleness
G=/data/data/com.github.metacubex.clash.meta/files/clash
echo "=== GeoIP DB category strings ==="
for f in "$G/GeoIP.dat" "$G/geoip.metadb" "$G/ASN.mmdb"; do
  [ -f "$f" ] || continue
  echo "--- $f ($(stat -c %s "$f" 2>/dev/null) bytes)"
  echo "  CN hits: $(grep -ao 'CN' "$f" 2>/dev/null | wc -l)"
  echo "  LAN hits: $(grep -ao 'LAN' "$f" 2>/dev/null | wc -l)"
  echo "  private hits: $(grep -ao 'private' "$f" 2>/dev/null | wc -l)"
done
echo "=== imported profiles that use GEOIP,LAN with CMFA (not FlClash) ==="
grep -rln 'GEOIP,LAN' /data/data/com.github.metacubex.clash.meta/files/imported/*/config.yaml 2>/dev/null | head -5
echo "=== backup space ==="
df -h /data | tail -1
echo "=== AGH idle check (track B => safe window for restart) ==="
M=/data/adb/modules/rmg_netguard
. $M/scripts/env.sh
hijack_check && echo "hijack=ATTACHED (restart would affect DNS!)" || echo "hijack=DETACHED (AGH restart has no network impact)"
echo "AGH pid=$(pidof "$AGH_PROC")"
echo "querylog_size=$(stat -c %s "$AGH_QUERYLOG" 2>/dev/null || echo missing)"
echo "=== files to change ==="
ls -lZ /data/data/com.github.metacubex.clash.meta/files/imported/91af3e78-5b33-4080-88e4-68e9abbe7b40/config.yaml /data/adb/agh/bin/AdGuardHome.yaml 2>/dev/null
