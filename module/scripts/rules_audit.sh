#!/system/bin/sh
# RMG NetGuard - clash profile & resolver config health audit (READ-ONLY).
# Never modifies app data. Prints WARN/INFO lines.
# robust MODDIR derivation: handles absolute/relative/bare invocation
case "$0" in */*) MODDIR="${0%/*}" ;; *) MODDIR=. ;; esac
MODDIR=$(cd "$MODDIR" 2>/dev/null && pwd) || MODDIR=""
case "$MODDIR" in */scripts) MODDIR="${MODDIR%/scripts}" ;; esac
[ -r "$MODDIR/scripts/env.sh" ] || MODDIR="/data/adb/modules/rmg_netguard"
. "$MODDIR/scripts/env.sh"

W=0

check_rules_file() {
  # check_rules_file <label> <yaml-path>
  local label="$1" f="$2"
  [ -r "$f" ] || { echo "INFO  $label: 配置不可读($f)"; return; }
  if grep -q 'GEOIP,CN' "$f" 2>/dev/null; then
    echo "OK    $label: 含 GEOIP,CN 直连兜底"
  else
    echo "WARN  $label: 缺 GEOIP,CN,DIRECT 兜底 -> 未命中域名规则的国内流量全部落入 MATCH 兜底组(经代理)"
    W=$(( W + 1 ))
  fi
  if grep -q 'GEOIP,LAN' "$f" 2>/dev/null; then
    echo "OK    $label: 含 GEOIP,LAN"
  else
    echo "INFO  $label: 无 GEOIP,LAN (建议补)"
  fi
}

echo "== 规则健康审计 $(date '+%F %T') =="

# --- FlClash ---
FC_PREFS="/data/data/$FLCLASH_PKG/shared_prefs/FlutterSharedPreferences.xml"
if [ -r "$FC_PREFS" ]; then
  echo "-- FlClash ($FLCLASH_PKG) --"
  # audit every profile; active/last-run flagged via shared prefs
  for f in "/data/data/$FLCLASH_PKG/files/profiles/"*.yaml; do
    [ -f "$f" ] || continue
    pid=${f##*/}
    tag="profile ${pid%.yaml}"
    case "$pid" in
      *311149465366958080*) tag="$tag [上次VPN运行]" ;;
      *350668055388360704*) tag="$tag [当前选中]" ;;
    esac
    check_rules_file "$tag" "$f"
  done
  if grep -q 'currentProfileId' "$FC_PREFS" 2>/dev/null; then
    cur=$(grep -o 'currentProfileId[^,]*' "$FC_PREFS" | head -n 1)
    echo "INFO  FlClash 选中 profile: $cur"
  fi
  # DNS override points at AGH? (fallback/default-nameserver)
  if grep -q '5591' "$FC_PREFS" 2>/dev/null; then
    if grep -q 'default-nameserver[^]]*5591' "$FC_PREFS" 2>/dev/null; then
      echo "WARN  FlClash default-nameserver 含 127.0.0.1:5591 -> 冷启动/AGH 未就绪时解析节点存在死锁风险, 应改纯 IP(223.5.5.5/119.29.29.29)"
      W=$(( W + 1 ))
    else
      echo "INFO  FlClash DNS fallback 引用 127.0.0.1:5591 (nameserver-policy/fallback 链路, 属预期协同)"
    fi
  fi
else
  echo "INFO  FlClash 未安装或不可读"
fi

# --- Clash Meta ---
CM_PREFS="$META_PREFS"
if [ -r "$CM_PREFS" ]; then
  echo "-- Clash Meta ($META_PKG) --"
  act=$(grep -o 'active_profile">[a-f0-9-]*' "$CM_PREFS" 2>/dev/null | head -n 1 | sed 's/.*">//')
  if [ -n "$act" ]; then
    check_rules_file "活动 profile ${act}" "$META_IMPORT/${act}/config.yaml"
  fi
  ov="/data/data/$META_PKG/files/clash/override.json"
  if [ -r "$ov" ]; then
    if grep -q '"default-nameserver":\["127.0.0.1:5591"\]' "$ov" 2>/dev/null; then
      echo "WARN  Clash Meta override default-nameserver 指向本地 5591 -> 冷启动死锁风险, 应改纯 IP"
      W=$(( W + 1 ))
    fi
    if ! grep -q '5591' "$ov" 2>/dev/null; then
      echo "INFO  Clash Meta override 无 AGH(5591) 集成: fake-ip 被 AGH 劫持旁路时过滤与分流无法协同"
    fi
  fi
else
  echo "INFO  Clash Meta 未安装或不可读"
fi

# --- AdGuardHome module ---
echo "-- AdGuardHome 模块 --"
if [ -r "$AGH_DIR/settings.conf" ]; then
  if grep -q '^enable_iptables=true' "$AGH_DIR/settings.conf" 2>/dev/null; then
    echo "INFO  enable_iptables=true (每次开机恢复 53 劫持; 与 Clash 并存时进入串联风险态)"
  else
    echo "OK    enable_iptables=false (AGH 不劫持 53, 与 Clash 天然无冲突)"
  fi
else
  echo "INFO  /data/adb/agh 不可读"
fi
if [ -r "$AGH_DIR/bin/AdGuardHome.yaml" ]; then
  if grep -q -E 'https://(1\.1\.1\.1|8\.8\.8\.8)' "$AGH_DIR/bin/AdGuardHome.yaml" 2>/dev/null; then
    echo "WARN  AGH fallback 上游含境外 DoH(1.1.1.1/8.8.8.8) -> 劫持开启时该流量必经 TUN/代理, 劣化即 10-30s 级挂起(10-13 实证)"
    W=$(( W + 1 ))
  fi
fi
# multi-instance / stale state snapshot
AGH_PID=$(pidof "$AGH_PROC" 2>/dev/null); [ -n "$AGH_PID" ] || AGH_PID=0
HIJACK=0; hijack_check && HIJACK=1
if [ "$AGH_PID" != "0" ] && [ "$HIJACK" != "1" ]; then
  echo "WARN  AGH 进程($AGH_PID)存活但劫持规则不在 -> 停止不对称缺陷态(历史 48 启/2 停)"
  W=$(( W + 1 ))
fi

echo "== 审计完成: WARN x$W =="
exit 0
