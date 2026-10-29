#!/system/bin/sh
# Verify auto mode holds track B after one full guard round (90s+)
M=/data/adb/modules/rmg_netguard
sleep 100
echo "== state.json after full guard round =="
cat $M/run/state.json
echo "== events tail =="
tail -n 4 $M/run/events.log
echo "== topology =="
. $M/scripts/env.sh
hijack_check && echo "hijack=ATTACHED" || echo "hijack=DETACHED (track B)"
vpn_if_detect
echo "vpn=$VPN_UP if=$VPN_IF mode=$(mode_get)"
echo "dns_latency=$(dns_latency_ms)ms"
echo "== AGH 24807 still healthy =="
echo "pid=$(pidof "$AGH_PROC")"
probe_dns 5591 && echo "5591 OK" || echo "5591 NO ANSWER"
