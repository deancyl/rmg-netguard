#!/system/bin/sh
# RMG NetGuard - MANUAL rescue. Invoked ONLY from WebUI / Action button.
# The guard loop never calls this file. All actions are logged and reversible.
#
# remove : detach AGH chain jump from nat OUTPUT (chain body preserved;
#          apps' DNS falls back to system resolver instantly)
# restore: re-insert the jump at position 1 (same position AGH's own
#          iptables.sh uses)
# status : print current attachment state
# robust MODDIR derivation: handles absolute/relative/bare invocation
case "$0" in */*) MODDIR="${0%/*}" ;; *) MODDIR=. ;; esac
MODDIR=$(cd "$MODDIR" 2>/dev/null && pwd) || MODDIR=""
case "$MODDIR" in */scripts) MODDIR="${MODDIR%/scripts}" ;; esac
[ -r "$MODDIR/scripts/env.sh" ] || MODDIR="/data/adb/modules/rmg_netguard"
. "$MODDIR/scripts/env.sh"

case "$1" in
  remove)
    if hijack_check; then
      if iptables -w -t nat -D OUTPUT -j "$AGH_CHAIN" 2>/dev/null; then
        touch "$FLAG_RESCUED" 2>/dev/null
        log_event "RESCUE" "removed OUTPUT -> $AGH_CHAIN (manual). Chain body kept; restore anytime via WebUI."
        echo "OK: 已摘除 nat OUTPUT -> $AGH_CHAIN (链体保留, 可随时恢复)"
      else
        echo "FAIL: 摘除失败 (iptables -D 返回非零)"
        exit 1
      fi
    else
      echo "OK: 劫持链当前未挂载, 无需摘除"
    fi
    ;;
  restore)
    if hijack_check; then
      echo "OK: 劫持链已在挂载, 无需恢复"
    else
      if iptables -w -t nat -I OUTPUT 1 -j "$AGH_CHAIN" 2>/dev/null; then
        rm -f "$FLAG_RESCUED" 2>/dev/null
        log_event "RESCUE" "restored OUTPUT -> $AGH_CHAIN (manual, inserted at 1)"
        echo "OK: 已恢复 nat OUTPUT -> $AGH_CHAIN (插入位置 1)"
      else
        echo "FAIL: 恢复失败 (iptables -I 返回非零; 链可能不存在, 请检查 AGH 模块)"
        exit 1
      fi
    fi
    ;;
  status)
    if hijack_check; then
      echo "ATTACHED: nat OUTPUT -> $AGH_CHAIN 在挂"
    else
      echo "DETACHED: 未挂载"
    fi
    [ -f "$FLAG_RESCUED" ] && echo "NOTE: 本模块曾执行过摘除 (rescue.removed 标记存在)"
    ;;
  *)
    echo "Usage: rescue.sh {remove|restore|status}"
    exit 1
    ;;
esac
exit 0
