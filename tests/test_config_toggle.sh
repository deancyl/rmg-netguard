#!/usr/bin/env bash
# Isolated regression test for config_toggle.sh v2.3.0 (no device writes).
# Each scenario gets its own tree; nothing is ever deleted (sandbox-safe).
# Covers inline-array + block-list nameserver, backup/revert, the
# watchdog rule "only re-apply a patch we previously applied",
# GEOIP,CN,DIRECT injection before MATCH, and status output format.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"

# Portable md5: use md5sum on Linux/Android, md5 -q on macOS
_md5() { md5sum "$1" 2>/dev/null | cut -d' ' -f1 || md5 -q "$1" 2>/dev/null; }
T="$(TMPDIR=/tmp mktemp -d)"

inline='dns:
  enable: true
  nameserver: [https://dns.cloudflare.com/dns-query, https://dns.google/dns-query]
  nameserver-policy:
    rule-set:cn: [https://doh.pub/dns-query]
rules:
- MATCH,proxy
'
block='dns:
  enable: true
  nameserver:
  - https://dns.cloudflare.com/dns-query#proxy
  - https://dns.google/dns-query#proxy
  nameserver-policy:
    rule-set:cn:
    - https://doh.pub/dns-query
rules:
- RULE-SET,cn,DIRECT
- MATCH,proxy
'
block_with_geoip='dns:
  enable: true
  nameserver:
  - https://dns.cloudflare.com/dns-query#proxy
  nameserver-policy:
    rule-set:cn:
    - https://doh.pub/dns-query
rules:
- RULE-SET,cn,DIRECT
- GEOIP,CN,DIRECT
- MATCH,proxy
'

pass=0; fail=0
chk() { if eval "$2"; then echo "PASS  $1"; pass=$((pass+1)); else echo "FAIL  $1"; fail=$((fail+1)); fi; }

# setup <name> <shape> -> prints env assignments to eval
setup() {
  local name="$1" shape="$2" root="$T/$1"
  mkdir -p "$root/mod/scripts" "$root/profiles/abcd/config" "$root/mod/run"
  cp "$HERE/module/scripts/config_toggle.sh" "$HERE/module/scripts/env.sh" \
     "$HERE/module/scripts/rules_audit.sh" "$root/mod/scripts/"
  echo 'active_profile">abcd' > "$root/prefs.xml"
  if   [ "$shape" = inline ];        then printf '%s' "$inline"          > "$root/profiles/abcd/config.yaml"
  elif [ "$shape" = block_with_geoip ]; then printf '%s' "$block_with_geoip" > "$root/profiles/abcd/config.yaml"
  else printf '%s' "$block"          > "$root/profiles/abcd/config.yaml"; fi
  cp "$root/profiles/abcd/config.yaml" "$root/orig.yaml"
  export META_PREFS="$root/prefs.xml" META_IMPORT="$root/profiles"
  export AGH_MODDIR="$root/no-agh" AGH_DIR="$root/no-agh" AGH_QUERYLOG="$root/no-querylog"
  export META_PKG=nope FLCLASH_PKG=nope
  CFG="$root/profiles/abcd/config.yaml"
  CT="sh $root/mod/scripts/config_toggle.sh"
  ROOT="$root"
}

for shape in inline block; do
  setup "$shape" "$shape"
  out=$($CT apply 2>&1) || true
  chk "$shape: apply succeeds" "echo '$out' | grep -q 'OK: patched'"
  chk "$shape: NS5591 present" "grep -q '127.0.0.1:5591' '$CFG'"
  chk "$shape: exactly one nameserver value" "[ \$(grep -c '127.0.0.1:5591' '$CFG') = 1 ]"
  chk "$shape: nameserver-policy preserved" "grep -q 'nameserver-policy:' '$CFG'"
  chk "$shape: rules preserved" "grep -q 'MATCH,proxy' '$CFG'"
  chk "$shape: GEOIP injected before MATCH" "grep -qE 'GEOIP,CN,DIRECT' '$CFG'"
  chk "$shape: backup saved" "[ -f '$ROOT/mod/run/backups/abcd.yaml.orig' ]"
  chk "$shape: marker saved" "[ -f '$ROOT/mod/run/backups/abcd.yaml.patched' ]"
  chk "$shape: status patched" "$CT status | grep -q 'patched: patched'"
  chk "$shape: status has geoip field" "$CT status | grep -q 'geoip:'"
  chk "$shape: status geoip is yes" "$CT status | grep -q 'geoip: yes'"
  chk "$shape: status agh_upstream is na (no AGH)" "$CT status | grep -q 'agh_upstream: na'"
done

# GEOIP injection is idempotent: apply on a file that already has GEOIP,CN,DIRECT
setup "geoip_idempotent" "block_with_geoip"
out=$($CT apply 2>&1) || true
chk "geoip_idempotent: apply succeeds" "echo '$out' | grep -q 'OK: patched'"
cnt=$(grep -c 'GEOIP,CN,DIRECT' "$CFG" 2>/dev/null || echo 0)
chk "geoip_idempotent: no duplicate GEOIP line" "[ '$cnt' = '1' ]"

for shape in inline block; do
  setup "revert_$shape" "$shape"
  $CT apply >/dev/null 2>&1
  $CT revert >/dev/null 2>&1
  chk "$shape: revert restores original" "cmp -s '$CFG' '$ROOT/orig.yaml'"
  chk "$shape: revert removes marker" "[ ! -f '$ROOT/mod/run/backups/abcd.yaml.patched' ]"
done

# watchdog: integration=on, unpatched, NO marker -> must NOT touch the file
setup auto_nomarker block
echo on > "$ROOT/mod/run/integration"
$CT auto >/dev/null 2>&1
chk "auto: no marker => no patch (storm fix)" "cmp -s '$CFG' '$ROOT/orig.yaml'"

# watchdog: marker exists + patch lost -> must re-apply (NS + GEOIP)
setup auto_marker block
echo on > "$ROOT/mod/run/integration"
$CT apply >/dev/null 2>&1
printf '%s' "$block" > "$CFG"
$CT auto >/dev/null 2>&1
chk "auto: marker + lost patch => re-apply NS" "grep -q '127.0.0.1:5591' '$CFG'"
chk "auto: marker + lost patch => re-apply GEOIP" "grep -qE 'GEOIP,CN,DIRECT' '$CFG'"

# watchdog: marker exists, NS patched, GEOIP wiped by subscription update -> re-apply
setup auto_geoip_drift block
echo on > "$ROOT/mod/run/integration"
$CT apply >/dev/null 2>&1
# simulate subscription update that kept NS but wiped GEOIP line
# (CMFA rewrites the config file but does NOT touch our marker file,
# so marker still holds hash(patched_with_geoip) != hash(now_no_geoip) -> drift)
grep -v 'GEOIP,CN,DIRECT' "$CFG" > "$CFG.tmp" && mv "$CFG.tmp" "$CFG"
$CT auto >/dev/null 2>&1
chk "auto: geoip drift => re-inject GEOIP" "grep -qE 'GEOIP,CN,DIRECT' '$CFG'"

# rules_audit source-level assertion (real-file behavior is verified on device)
AUD_SRC="$HERE/module/scripts/rules_audit.sh"
chk "audit: recognises RULE-SET,cn as equivalent coverage" "grep -q 'RULE-SET,(cn|cn-ip|china)' \"$AUD_SRC\""
chk "audit: RULE-SET profiles emit INFO not WARN" "grep -q '有 RULE-SET/GEOSITE 国内直连覆盖' \"$AUD_SRC\""

# agh_guard subcommand (v2.3.1): detects and auto-corrects unsafe AGH upstream
# config_toggle.sh derives MODDIR from $0 (its own path), so we copy the
# module/scripts directory into a temp dir so MODDIR resolves to that temp dir.
T_AGH="$T/agh_guard"
mkdir -p "$T_AGH/agh/bin" "$T_AGH/run/backups" "$T_AGH/scripts"
# Copy all scripts so env.sh MODDIR self-check passes with $T_AGH as MODDIR
cp "$HERE/module/scripts/env.sh"          "$T_AGH/scripts/env.sh"
cp "$HERE/module/scripts/config_toggle.sh" "$T_AGH/scripts/config_toggle.sh"
cat > "$T_AGH/agh/bin/AdGuardHome.yaml" << 'YAMLEOF'
dns:
  upstream_dns:
    - https://1.12.12.12/dns-query
    - https://1.1.1.1/dns-query
    - https://doh.pub/dns-query
  fallback_dns:
    - https://8.8.8.8/dns-query
  bootstrap_dns:
    - 8.8.8.8
    - 1.1.1.1
YAMLEOF
# Call via copied script so $0-derived MODDIR == $T_AGH, RUN=$T_AGH/run, BKDIR=$T_AGH/run/backups
out=$(AGH_DIR="$T_AGH/agh" sh "$T_AGH/scripts/config_toggle.sh" agh_guard 2>&1) || true
chk "agh_guard: 1.12.12.12 removed" "! grep -q '1\.12\.12\.12' \"$T_AGH/agh/bin/AdGuardHome.yaml\""
chk "agh_guard: 1.1.1.1 removed"    "! grep -q '1\.1\.1\.1'    \"$T_AGH/agh/bin/AdGuardHome.yaml\""
chk "agh_guard: 8.8.8.8 removed"    "! grep -q '8\.8\.8\.8'    \"$T_AGH/agh/bin/AdGuardHome.yaml\""
chk "agh_guard: 223.5.5.5 written"  "grep  -q '223\.5\.5\.5'   \"$T_AGH/agh/bin/AdGuardHome.yaml\""
chk "agh_guard: backup created"     "[ -f \"$T_AGH/run/backups/AdGuardHome.yaml.orig\" ]"
out2=$(AGH_DIR="$T_AGH/agh" sh "$T_AGH/scripts/config_toggle.sh" agh_guard 2>&1) || true
chk "agh_guard: idempotent (already safe)" "echo \"$out2\" | grep -q 'already safe'"

# domain-form DoH triggers agh_guard (v2.3.2)
cat > "$T_AGH/agh/bin/AdGuardHome.yaml" << 'YAMLEOF'
dns:
  upstream_dns:
    - https://doh.pub/dns-query
  fallback_dns:
    - https://223.5.5.5/dns-query
  bootstrap_dns:
    - 223.5.5.5
YAMLEOF
out_doh=$(AGH_DIR="$T_AGH/agh" sh "$T_AGH/scripts/config_toggle.sh" agh_guard 2>&1) || true
chk "agh_guard: domain DoH triggers fix" "echo \"$out_doh\" | grep -q 'OK: AGH upstream corrected'"
chk "agh_guard: doh.pub removed" "! grep -q 'doh\.pub' \"$T_AGH/agh/bin/AdGuardHome.yaml\""
chk "agh_guard: status reports agh_upstream: safe" "AGH_DIR=\"$T_AGH/agh\" sh \"$T_AGH/scripts/config_toggle.sh\" status | grep -q 'agh_upstream: safe'"

echo "---- result: pass=$pass fail=$fail (temp: $T)"
[ "$fail" = 0 ]
