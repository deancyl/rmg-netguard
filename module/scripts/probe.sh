#!/system/bin/sh
# RMG NetGuard v2.0 - one-shot full diagnostics (manual: Action button / WebUI).
# Read-only except printing. Prints a human-readable report.
# robust MODDIR derivation: handles absolute/relative/bare invocation
case "$0" in */*) MODDIR="${0%/*}" ;; *) MODDIR=. ;; esac
MODDIR=$(cd "$MODDIR" 2>/dev/null && pwd) || MODDIR=""
case "$MODDIR" in */scripts) MODDIR="${MODDIR%/scripts}" ;; esac
[ -r "$MODDIR/scripts/env.sh" ] || MODDIR="/data/adb/modules/rmg_netguard"
. "$MODDIR/scripts/env.sh"

echo "== RMG NetGuard 体检 v2 $(date '+%F %T') =="

vpn_if_detect
HIJACK=0; hijack_check && HIJACK=1
ports_check
AGH_PID=$(pidof AdGuardHome 2>/dev/null); [ -n "$AGH_PID" ] || AGH_PID=0
client_detect
MODE=$(mode_get)
TRACK="?"
if [ "$HIJACK" = "1" ]; then TRACK=A; elif [ "$VPN_UP" = "1" ]; then TRACK=B; fi

echo "1) VPN 接口     : $([ $VPN_UP = 1 ] && echo "$VPN_IF (活跃)" || echo "无")"
echo "2) 运行客户端   : $CLIENT"
echo "3) 模式 / 轨道  : $MODE / $TRACK"
echo "4) AGH 53 劫持  : $([ $HIJACK = 1 ] && echo "在挂 (nat OUTPUT -> $AGH_CHAIN)" || echo "未挂载")"
echo "5) AGH 进程     : $AGH_PID"
echo "6) AGH 5591 监听: $([ $AGH_PORT_UP = 1 ] && echo 是 || echo 否)"
echo "7) mihomo 1053  : $([ $MIHOMO_PORT_UP = 1 ] && echo 是 || echo 否)"

# 当前态判定（与 guard.sh 同规则）
if [ "$VPN_UP" = "1" ] && [ "$HIJACK" = "1" ]; then
  ST="RISK_COEXIST(串联风险: AppDNS->AGH->DoH->TUN 串联, VPN 路径抖动即全机 DNS 停摆)"
elif [ "$AGH_PID" != "0" ] && [ "$HIJACK" != "1" ]; then
  ST="INCONSISTENT(进程在但劫持规则不在, AGH 实际未接管 DNS)"
elif [ "$HIJACK" = "1" ] && [ "$AGH_PORT_UP" != "1" ]; then
  ST="DOWN_PORT(劫持在挂但 5591 无监听: 全机 DNS 黑洞!)"
else
  ST="NORMAL"
fi
echo "8) 状态判定     : $ST"

FP=$(filter_probe)
FW=$(filter_probe_wedge)
echo "9) 过滤探针     : primary=$FP wedge=$FW  (api.ad.xiaomi.com / googleads.g.doubleclick.net -> AGH:5591)"
if [ "$FP" = "BLOCKED" ] && [ "$FW" = "UNKNOWN" ]; then
  echo "   !! 楔死签名: 主域被拦而 wedge 域被静默丢弃 -> AGH 进程内部状态退化, 建议重启 AGH"
fi
QAGE=$(querylog_age)
echo "   querylog 年龄 : ${QAGE}s (陈旧=日志缓冲停写或无流量)"
echo "10) 集成状态    : $(sh "$MODDIR/scripts/config_toggle.sh" status 2>/dev/null | tr '\n' ' ')"

echo "11) 系统路径 DNS 延迟 (5 次, 即 App 实际体验):"
i=0
while [ $i -lt 5 ]; do
  printf "   - %s ms\n" "$(dns_latency_ms)"
  i=$(( i + 1 ))
done

echo "12) 本地解析器 UDP DNS 存活探测:"
if command -v nc >/dev/null 2>&1; then
  probe_dns "$AGH_PORT" \
    && echo "   - 5591 (AGH)      : 已应答" \
    || echo "   - 5591 (AGH)      : 无应答/不可达"
  probe_dns "$MIHOMO_PORT" \
    && echo "   - 1053 (mihomo)   : 已应答" \
    || echo "   - 1053 (mihomo)   : 无应答/未监听"
else
  echo "   - (nc 不可用, 跳过)"
fi

echo "13) AGH querylog 近段统计:"
querylog_stats

echo "14) 最近事件:"
if [ -f "$LOG_EVENTS" ]; then
  tail -n 5 "$LOG_EVENTS" | sed 's/^/   /'
else
  echo "   (无)"
fi
exit 0
