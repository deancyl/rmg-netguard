#!/system/bin/sh
# RMG NetGuard v2.1 - one-shot full diagnostics (manual: Action button / WebUI).
# Read-only except printing. Prints a human-readable report.
#
# v2.1 latency budget (~3s worst, was ~40s worst):
#   - filter probes run as a concurrent PAIR (worst single probe, not sum)
#   - DNS latency: 3 concurrent samples @3s ceiling (was 5 serial @6s = 30s)
#   - port liveness probes run concurrently
#   - querylog stats: single awk pass
#   - AGH absent -> probes/port checks SKIP instantly (no waiting on
#     a dead 5591; module reports clean "not installed/not running" state)
# robust MODDIR derivation: handles absolute/relative/bare invocation
case "$0" in */*) MODDIR="${0%/*}" ;; *) MODDIR=. ;; esac
MODDIR=$(cd "$MODDIR" 2>/dev/null && pwd) || MODDIR=""
case "$MODDIR" in */scripts) MODDIR="${MODDIR%/scripts}" ;; esac
[ -r "$MODDIR/scripts/env.sh" ] || MODDIR="/data/adb/modules/rmg_netguard"
. "$MODDIR/scripts/env.sh"

echo "== RMG NetGuard 体检 v2.1 $(date '+%F %T') =="

vpn_if_detect
HIJACK=0; hijack_check && HIJACK=1
AGH_PID=$(pidof "$AGH_PROC" 2>/dev/null); [ -n "$AGH_PID" ] || AGH_PID=0
client_detect
MODE=$(mode_get)
TRACK="?"
if [ "$HIJACK" = "1" ]; then TRACK=A; elif [ "$VPN_UP" = "1" ]; then TRACK=B; fi

echo "1) VPN 接口     : $([ $VPN_UP = 1 ] && echo "$VPN_IF (活跃)" || echo "无")"
echo "2) 运行客户端   : $CLIENT"
echo "3) 模式 / 轨道  : $MODE / $TRACK"
echo "4) AGH 53 劫持  : $([ $HIJACK = 1 ] && echo "在挂 (nat OUTPUT -> $AGH_CHAIN)" || echo "未挂载")"
echo "5) AGH 进程     : $AGH_PID"

# ---- state classification (same rules as guard.sh) ----
AGH_PORT_UP=0
MIHOMO_PORT_UP=0
if [ "$AGH_PID" != "0" ]; then
  ports_check
fi
echo "6) AGH 5591 监听: $( [ "$AGH_PID" != "0" ] && { [ $AGH_PORT_UP = 1 ] && echo 是 || echo 否; } || echo "跳过(AGH 未运行)")"
echo "7) mihomo 1053  : $( [ $MIHOMO_PORT_UP = 1 ] && echo 是 || { [ "$AGH_PID" != "0" ] && echo 否 || echo "跳过"; })"

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

# ---- availability banner (v2.1) ----
if ! agh_installed && ! agh_running; then
  echo "   [i] AGH 未安装 -> 过滤探针/日志统计跳过 (模块纯观测空载)"
fi

# ---- filter probes: concurrent pair, only while AGH is running ----
if agh_running; then
  r=$(filter_probe_pair)
  FP=${r%% *}; FP=${FP#P=}
  FW=${r##* }; FW=${FW#W=}
  echo "9) 过滤探针     : primary=$FP wedge=$FW  (api.ad.xiaomi.com / googleads.g.doubleclick.net -> AGH:5591)"
  if [ "$FP" = "BLOCKED" ] && [ "$FW" = "UNKNOWN" ]; then
    echo "   !! 楔死签名: 主域被拦而 wedge 域被静默丢弃 -> AGH 进程内部状态退化, 建议重启 AGH"
  fi
  QAGE=$(querylog_age)
  echo "   querylog 年龄 : ${QAGE}s (陈旧=日志缓冲停写或无流量)"
else
  echo "9) 过滤探针     : SKIP (AGH 未运行, 无 5591 目标)"
fi

echo "10) 集成状态    : $(sh "$MODDIR/scripts/config_toggle.sh" status 2>/dev/null | tr '\n' ' ')"

# ---- system-path DNS latency: 3 concurrent samples @3s ----
echo "11) 系统路径 DNS 延迟 (3 次并发, 即 App 实际体验):"
if [ "$VPN_UP" = "1" ] || [ "$HIJACK" = "1" ] || [ "$AGH_PID" != "0" ]; then
  dns_latency_batch 3 3 | sed 's/^/   - /'
else
  echo "   - 纯直连环境: 跳过采样 (系统 DNS 未被任何组件接管)"
fi

# ---- local resolver UDP liveness: concurrent ----
echo "12) 本地解析器 UDP DNS 存活探测:"
if command -v nc >/dev/null 2>&1 && agh_running; then
  ( probe_dns "$AGH_PORT" && echo "   - 5591 (AGH)      : 已应答" \
                     || echo "   - 5591 (AGH)      : 无应答/不可达" ) &
  ( probe_dns "$MIHOMO_PORT" && echo "   - 1053 (mihomo)   : 已应答" \
                          || echo "   - 1053 (mihomo)   : 无应答/未监听" ) &
  wait
else
  echo "   - (AGH 未运行或 nc 不可用, 跳过)"
fi

echo "13) AGH querylog 近段统计:"
if [ "$AGH_PID" != "0" ]; then
  querylog_stats
else
  echo "   total 0 filtered 0 loopback 0 (AGH 未运行)"
fi

echo "14) 最近事件:"
if [ -f "$LOG_EVENTS" ]; then
  tail -n 5 "$LOG_EVENTS" | sed 's/^/   /'
else
  echo "   (无)"
fi
exit 0
