#!/system/bin/sh
# Switch to auto dual-track + move to track B (VPN on -> hijack off)
M=/data/adb/modules/rmg_netguard
. $M/scripts/env.sh

echo "== switch mode=auto =="
sh $M/scripts/webui.sh mode_auto

echo "== immediate detach to track B =="
sh $M/scripts/controller.sh detach
echo "rc=$?"
hijack_check && echo "hijack=ATTACHED" || echo "hijack=DETACHED (track B)"

echo "-- connectivity verification (track B, VPN on) --"
echo "dns_latency=$(dns_latency_ms)ms"
ping -c 2 -W 2 223.5.5.5 2>/dev/null | tail -1
echo "dns_latency2=$(dns_latency_ms)ms"

echo "-- guard will keep track B (VPN stable on); state: --"
sleep 3
cat $M/run/state.json
tail -n 3 $M/run/events.log
