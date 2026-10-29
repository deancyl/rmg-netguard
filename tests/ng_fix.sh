#!/system/bin/sh
# RMG NetGuard - AGH repair chain 2026-10-29
# detach -> restart AGH -> verify wedge -> reattach. All steps verified.
M=/data/adb/modules/rmg_netguard
. $M/scripts/env.sh

echo "== STEP1: detach (v2.2.2 fail-open controller) =="
sh $M/scripts/controller.sh detach
echo "rc=$?"
hijack_check && echo "hijack=STILL_ATTACHED(!)" || echo "hijack=DETACHED OK"
echo "dns_latency_after_detach=$(dns_latency_ms)ms"

echo "== STEP2: restart AGH =="
echo "old_pid=$(pidof "$AGH_PROC")"
kill $(pidof "$AGH_PROC") 2>/dev/null
sleep 2
/data/adb/agh/scripts/tool.sh stop >/dev/null 2>&1
sleep 1
/data/adb/agh/scripts/tool.sh start >/dev/null 2>&1
sleep 4
NEW=$(pidof "$AGH_PROC")
echo "new_pid=$NEW"
ports_check
echo "5591_up=$AGH_PORT_UP"
if probe_dns 5591; then echo "5591 answers OK"; else echo "5591 NO ANSWER(!)"; fi

echo "== STEP3: wedge signature re-test on fresh process =="
echo "primary=$(filter_probe) wedge=$(filter_probe_wedge)"
echo "querylog_age=$(querylog_age)s"

echo "== STEP4: reattach hijack =="
sh $M/scripts/controller.sh attach
echo "rc=$?"
hijack_check && echo "hijack=ATTACHED OK" || echo "hijack=STILL_DETACHED"
echo "dns_latency_final=$(dns_latency_ms)ms"
echo "== events tail =="
tail -n 6 $M/run/events.log
