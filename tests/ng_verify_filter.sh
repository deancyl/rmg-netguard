#!/system/bin/sh
# Post-VPN-restart verification: track B filtering via AGH restored?
M=/data/adb/modules/rmg_netguard
. $M/scripts/env.sh

echo "== topology =="
hijack_check && echo "hijack=ATTACHED" || echo "hijack=DETACHED (track B)"
vpn_if_detect
echo "vpn=$VPN_UP if=$VPN_IF"
vpn_if_detect
client_detect
echo "client=$CLIENT mode=$(mode_get)"
cat $M/run/state.json

echo "== mihomo ports after reload =="
ports_check
echo "1053_up=$MIHOMO_PORT_UP 5591_up=$AGH_PORT_UP"

echo "== connectivity =="
echo "dns_latency=$(dns_latency_ms)ms"
echo "dns_latency2=$(dns_latency_ms)ms"

echo "== track B filter evidence: AGH querylog clients =="
# mihomo (127.0.0.1) hitting AGH = filtering path active on track B
if [ -r "$AGH_QUERYLOG" ]; then
  tail -c 200000 "$AGH_QUERYLOG" | grep -o '"IP":"[^"]*"' | sort | uniq -c | sort -rn | head -6
else
  echo "querylog unreadable"
fi
echo "== stats =="
querylog_stats
echo "== AGH alive =="
echo "pid=$(pidof "$AGH_PROC")"
probe_dns 5591 && echo "5591 OK" || echo "5591 NO ANSWER"
echo "== events tail =="
tail -n 5 $M/run/events.log
