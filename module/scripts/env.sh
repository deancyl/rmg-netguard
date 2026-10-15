# RMG NetGuard shared environment - sourced by all scripts
# Rules: busybox ash standalone mode; no bashisms; keep fork count minimal.

# Callers derive MODDIR BEFORE sourcing this file (their $0 is the reliable
# reference). Only fall back to self-derivation when caller did not provide
# a valid one -- do NOT overwrite a working MODDIR (2026-10-15 真机调试发现
# source 时 $0 仍指向调用方脚本, 在此重推导会覆盖正确值).
if [ -z "$MODDIR" ] || [ ! -r "$MODDIR/scripts/env.sh" ]; then
  MODDIR_SRC="${0%/*}"
  case "$MODDIR_SRC" in
    */scripts) MODDIR="${MODDIR_SRC%/*}" ;;
    *) MODDIR="/data/adb/modules/rmg_netguard" ;;
  esac
fi

RUN="$MODDIR/run"
LOG_EVENTS="$RUN/events.log"
LOG_STATE="$RUN/state.json"
LOG_AUDIT="$RUN/audit.txt"
PID_GUARD="$RUN/guard.pid"
FLAG_RESCUED="$RUN/rescue.removed"
MODE_FILE="$RUN/mode"                # observe | auto
INTEG_FILE="$RUN/integration"        # on | off
LOCK="$RUN/ctrl.lock"
BKDIR="$RUN/backups"

MODID="rmg_netguard"
# v2.1: all target paths/packages are overridable via environment
# (simulation hook for "no AGH / no Clash" testing; normal runs use defaults).
AGH_MODDIR="${AGH_MODDIR:-/data/adb/modules/AdGuardHome}"
AGH_DIR="${AGH_DIR:-/data/adb/agh}"
AGH_CHAIN="${AGH_CHAIN:-ADGUARD_REDIRECT_DNS}"
AGH_PORT="${AGH_PORT:-5591}"
AGH_QUERYLOG="${AGH_QUERYLOG:-/data/adb/agh/bin/data/querylog.json}"
MIHOMO_PORT="1053"

META_PKG="${META_PKG:-com.github.metacubex.clash.meta}"
FLCLASH_PKG="${FLCLASH_PKG:-com.follow.clash}"
META_IMPORT="${META_IMPORT:-/data/data/$META_PKG/files/imported}"
META_PREFS="${META_PREFS:-/data/data/$META_PKG/shared_prefs/service.xml}"
NS5591="127.0.0.1:5591"

# tunables (defaults; $RUN/config may override via guard.sh)
INTERVAL="${INTERVAL:-90}"
IDLE_INTERVAL="${IDLE_INTERVAL:-300}" # sleep when no target (AGH+Clash absent)
AUDIT_EVERY="${AUDIT_EVERY:-20}"
DNS_EVERY="${DNS_EVERY:-5}"
DNS_WARN_MS="${DNS_WARN_MS:-800}"
CURL_TARGET="${CURL_TARGET:-http://www.baidu.com}"
CURL_TIMEOUT="${CURL_TIMEOUT:-6}"
HYSTERESIS="${HYSTERESIS:-2}"        # consecutive rounds before acting
FILTER_PROBE_TMO="${FILTER_PROBE_TMO:-2}"  # per-probe ceiling, seconds

# ---- availability helpers (v2.1: graceful degradation w/o AGH / Clash) ----
AGH_PROC="${AGH_PROC:-AdGuardHome}"   # simulation hook: set to a dead name
agh_installed() {
  [ -d "$AGH_DIR" ] || [ -d "$AGH_MODDIR" ]
}
agh_running() {
  [ -n "$(pidof "$AGH_PROC" 2>/dev/null)" ]
}
clash_installed() {
  [ -d "/data/data/$META_PKG" ] || [ -d "/data/data/$FLCLASH_PKG" ]
}
# target_present = module has anything to watch at all; false -> idle mode
target_present() {
  agh_installed && return 0
  clash_installed && return 0
  [ -n "$(pidof "$AGH_PROC" 2>/dev/null)" ]
}

log_event() {
  # log_event <tag> <message...>
  mkdir -p "$RUN" 2>/dev/null
  echo "$(date '+%Y-%m-%d %H:%M:%S') [$1] $2" >> "$LOG_EVENTS"
  if [ -f "$LOG_EVENTS" ]; then
    n=$(grep -c '' "$LOG_EVENTS" 2>/dev/null)
    if [ "${n:-0}" -gt 300 ]; then
      tail -n 200 "$LOG_EVENTS" > "$LOG_EVENTS.tmp" 2>/dev/null && mv "$LOG_EVENTS.tmp" "$LOG_EVENTS"
    fi
  fi
}

mode_get() {
  m=$(cat "$MODE_FILE" 2>/dev/null)
  [ "$m" = "auto" ] && { echo auto; return; }
  echo observe
}

integ_get() {
  i=$(cat "$INTEG_FILE" 2>/dev/null)
  [ "$i" = "on" ] && { echo on; return; }
  echo off
}

# ---- probe helpers ----

# VPN iface detection: zero-fork. Excludes tunl0 (kernel ipip device).
vpn_if_detect() {
  VPN_IF=""
  VPN_UP=0
  for d in /sys/class/net/*; do
    dev=${d#/sys/class/net/}
    case "$dev" in
      tun[0-9]*|FlClash|clash*)
        VPN_IF="$dev"
        VPN_UP=1
        break
        ;;
    esac
  done
}

# which VPN client is running (pgrep by package name fragment)
client_detect() {
  CLIENT="none"
  if pgrep -f "$META_PKG" >/dev/null 2>&1; then
    CLIENT="meta"
  elif pgrep -f "$FLCLASH_PKG" >/dev/null 2>&1; then
    CLIENT="flclash"
  fi
}

# AGH hijack chain present in nat OUTPUT (1 fork); rc=0 means present
hijack_check() {
  iptables -w -t nat -C OUTPUT -j "$AGH_CHAIN" 2>/dev/null
}

# resolver liveness: 1-2 forks (grep -q over /proc/net/udp*)
# note: /proc/net/udp port field is NOT at line end; match ":PORT " with
# trailing separator. Remote-port false positives are practically impossible
# for 5591/1053.
ports_check() {
  AGH_PORT_UP=0
  MIHOMO_PORT_UP=0
  if grep -q ":15D7 " /proc/net/udp /proc/net/udp6 2>/dev/null; then
    AGH_PORT_UP=1
  fi
  if grep -q ":041D " /proc/net/udp /proc/net/udp6 2>/dev/null; then
    MIHOMO_PORT_UP=1
  fi
}

# end-to-end system-path DNS latency in ms (what apps actually feel).
# 1 fork (curl). Optional $1 = curl max-time override (probe.sh uses 3).
# echoes integer ms, or "timeout" on failure.
dns_latency_ms() {
  local v sec frac ms tmo="${1:-$CURL_TIMEOUT}"
  v=$(curl -o /dev/null -s --max-time "$tmo" -w '%{time_namelookup}' "$CURL_TARGET" 2>/dev/null)
  case "$v" in
    ''|*[!0-9.]*) echo timeout; return 1 ;;
  esac
  sec=${v%%.*}
  frac=${v#*.}
  [ "$sec" = "$v" ] && sec=$v && frac=0
  while [ ${#frac} -lt 6 ]; do frac="${frac}0"; done
  case "$frac" in *[!0-9]*) frac=000000 ;; esac
  ms=$(( sec * 1000 + frac / 1000 ))
  echo "$ms"
}

# parallel batch of N system-path DNS latency samples (v2.1).
# echoes one result per line (ms or timeout); wall time = worst single
# sample, NOT sum -- keeps 一键体检 under a few seconds.
dns_latency_batch() {
  local n="${1:-3}" i out="$RUN/.dl.$$"
  : > "$out"
  i=0
  while [ $i -lt "$n" ]; do
    ( dns_latency_ms "${2:-3}" >> "$out" 2>/dev/null ) &
    i=$(( i + 1 ))
  done
  wait
  cat "$out"
  rm -f "$out" 2>/dev/null
}

# DNS liveness probe against a local resolver over UDP (liveness only;
# mksh 32-bit arithmetic forbids ns timing here).
probe_dns() {
  local out expect
  expect=$(printf '\001\002')
  out=$(printf '\001\002\001\000\000\001\000\000\000\000\000\000\001a\002cn\000\000\001\000\001' \
        | timeout 2 nc -u -w 1 127.0.0.1 "$1" 2>/dev/null | head -c 2)
  [ "$out" = "$expect" ]
}

# END-TO-END FILTER PROBE (v2.0): query a known-blocked ad domain directly
# against AGH:5591 and classify the answer.
# BLOCKED = rcode3(NXDOMAIN) or answer rdata 0.0.0.0; OPEN = real answer.
# echoes: BLOCKED | OPEN | UNKNOWN
# Parameterized core: $1 = printf query string (raw DNS A-query bytes).
# v2.1: ceiling FILTER_PROBE_TMO (default 2s, was fixed 3s + -w 2).
filter_probe_domain() {
  local hex rcode ancount
  hex=$(printf "$1" \
        | timeout "$FILTER_PROBE_TMO" nc -u -w 1 127.0.0.1 "$AGH_PORT" 2>/dev/null \
        | od -An -v -tx1 | tr -d ' \n')
  [ -n "$hex" ] || { echo UNKNOWN; return; }
  rcode=$(echo "$hex" | cut -c7-8)          # flags low byte
  ancount=$(echo "$hex" | cut -c13-16)      # ANCOUNT
  if [ "$rcode" = "03" ]; then echo BLOCKED; return; fi
  if [ "$ancount" != "0000" ]; then
    case "$hex" in
      *00000000) echo BLOCKED ;;
      *) echo OPEN ;;
    esac
    return
  fi
  echo UNKNOWN
}

# Probe domain 1 (primary): api.ad.xiaomi.com -- blocked 0.0.0.0/TTL10,
# verified live 2026-10-15.
filter_probe() {
  filter_probe_domain '\001\002\001\000\000\001\000\000\000\000\000\000\003api\002ad\006xiaomi\003com\000\000\001\000\001'
}

# Probe domain 2 (wedge detector): googleads.g.doubleclick.net -- WAS blocked
# by AGH (12:49/14:47 querylog) but the surviving pre-soft-reboot AGH process
# silently DROPS its queries (UDP+TCP both mute) while everything else works.
# xiaomi=BLOCKED + googleads=UNKNOWN is the single-domain-wedge signature.
filter_probe_wedge() {
  filter_probe_domain '\001\002\001\000\000\001\000\000\000\000\000\000\011googleads\001g\007doubleclick\003net\000\000\001\000\001'
}

# v2.1: run BOTH filter probes concurrently; echoes "P=<res> W=<res>".
# Wall time = worst single probe (<= FILTER_PROBE_TMO), not the sum.
# Temp files are $-suffixed: concurrent WebUI invocations cannot collide.
filter_probe_pair() {
  local pf="$RUN/.fp_p.$$" wf="$RUN/.fp_w.$$" r
  ( filter_probe       > "$pf" 2>/dev/null ) &
  ( filter_probe_wedge > "$wf" 2>/dev/null ) &
  wait
  r="P=$(cat "$pf" 2>/dev/null) W=$(cat "$wf" 2>/dev/null)"
  rm -f "$pf" "$wf" 2>/dev/null
  echo "$r"
}

# querylog file age in seconds (mksh-safe: epoch seconds fit 32-bit until 2038)
querylog_age() {
  local m now
  m=$(stat -c %Y "$AGH_QUERYLOG" 2>/dev/null)
  [ -n "$m" ] || { echo -1; return; }
  now=$(date +%s)
  echo $(( now - m ))
}

# active Meta profile uuid from service.xml (empty when absent)
meta_active_profile() {
  grep -o 'active_profile">[a-f0-9-]*' "$META_PREFS" 2>/dev/null \
    | head -n 1 | sed 's/.*">//'
}

# integration status of the active Meta profile:
# echoes: patched | unpatched | noprofile
integration_check() {
  local uuid f
  uuid=$(meta_active_profile)
  [ -n "$uuid" ] || { echo noprofile; return; }
  f="$META_IMPORT/$uuid/config.yaml"
  if [ -r "$f" ]; then
    if grep -q "$NS5591" "$f" 2>/dev/null; then echo patched; else echo unpatched; fi
  else
    echo noprofile
  fi
}

# querylog mini-stats over the most recent chunk.
# v2.1: single awk pass (was 3x grep + awk = 4 passes over 200KB).
# outputs:
#   total <n> / filtered <n> / loopback <n> (client 127.0.0.1 = track B)
#   top blocked domains (3)
querylog_stats() {
  [ -r "$AGH_QUERYLOG" ] || { echo "total 0 filtered 0 loopback 0"; return; }
  tail -c 200000 "$AGH_QUERYLOG" 2>/dev/null | awk '
    /"QH":/             { total++ }
    /"IsFiltered":true/ { filt++
        if (match($0, /"QH":"[^"]*"/)) { d = substr($0, RSTART+6, RLENGTH-7); c[d]++ } }
    /"IP":"127.0.0.1"/  { loop++ }
    END {
      printf "total %d filtered %d loopback %d\n", total, filt, loop
      n = 0; for (k in c) { if (n++ >= 3) break; print "  top " c[k] " " k }
    }' 2>/dev/null
}

write_state() {
  # write_state <state> <vpn> <vpnif> <hijack> <aghpid> <aghport> <mihport>
  #             <dnsms> [client] [mode] [track]
  mkdir -p "$RUN" 2>/dev/null
  printf '{"ts":"%s","state":"%s","vpn":%s,"vpn_if":"%s","hijack":%s,"agh_pid":%s,"agh_port":%s,"mihomo_port":%s,"dns_ms":"%s","client":"%s","mode":"%s","track":"%s"}\n' \
    "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" \
    "${9:-none}" "${10:-observe}" "${11:-?}" \
    > "$LOG_STATE.tmp" && mv "$LOG_STATE.tmp" "$LOG_STATE"
}
