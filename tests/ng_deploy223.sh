#!/system/bin/sh
# Deploy v2.2.3 classifier fix + restart guard + verify state becomes NORMAL
M=/data/adb/modules/rmg_netguard
cat /data/local/tmp/guard.sh > $M/scripts/guard.sh
cat /data/local/tmp/probe.sh > $M/scripts/probe.sh
cat /data/local/tmp/module.prop > $M/module.prop
chmod 755 $M/scripts/*.sh
chmod 644 $M/module.prop
echo "version: $(grep '^version=' $M/module.prop)"

# restart guard to load new classify()
for d in /proc/[0-9]*; do
  if grep -qa "rmg_netguard/scripts/guard.sh" "$d/cmdline" 2>/dev/null; then
    kill ${d#/proc/} 2>/dev/null
  fi
done
sleep 1
nohup sh $M/scripts/guard.sh >/dev/null 2>&1 &
sleep 4
echo "guard_pid=$(cat $M/run/guard.pid)"
echo "== state.json (expect NORMAL, mode=auto, track=B) =="
cat $M/run/state.json
echo "== probe ST line (expect NORMAL track B wording) =="
sh $M/scripts/probe.sh 2>/dev/null | grep -E "^8\)"
echo "== events tail =="
tail -n 3 $M/run/events.log
