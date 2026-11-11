#!/system/bin/sh
# RMG NetGuard v2.3.1 - DNS integration toggle for Clash Meta active profile.
# Applies/reverts nameserver -> 127.0.0.1:5591 in the ACTIVE profile's
# config.yaml so mihomo routes its upstream through AGH (track B filter).
# Also injects - GEOIP,CN,DIRECT before - MATCH to ensure domestic traffic
# with Fake-IP is not leaked to proxy in track B (cn-ip,no-resolve is skipped
# for Fake-IPs; GEOIP,CN without no-resolve triggers real resolution via
# direct-nameserver and correctly catches domestic hosts).
#
# apply  : backup once (never overwrite), patch NS+GEOIP, record md5,
#          broadcast PROFILE_CHANGED so mihomo hot-reloads patched config
# revert : restore from first backup, broadcast PROFILE_CHANGED
# status : patched? backup? drifted? (profile changed since last apply)
# auto   : re-apply ONLY when a patch we previously applied was lost;
#          after re-apply also broadcasts PROFILE_CHANGED
#
# Notes learned on-device (2026-10-15 / 2026-11-06 / 2026-11-10):
# - CMFA override.json is SUPPRESSED by the profile's own dns: section, so
#   patching the profile file is the only working hook.
# - subscription updates rewrite the imported profile -> drift detection +
#   auto-reapply is mandatory (WebUI "integration" toggle owns this).
# - nameserver has TWO yaml shapes: inline array `nameserver: [ ... ]` and
#   block list `nameserver:` + `- item` lines. v2.2.5+ supports both.
# - v2.3.0: without in-memory hot-reload, disk patch is invisible to mihomo
#   until VPN is reconnected. Broadcast PROFILE_CHANGED after every write.
# - v2.3.0: GEOIP,CN,DIRECT (no no-resolve) must precede MATCH so domestic
#   traffic with Fake-IP skips cn-ip(no-resolve) but still gets DIRECT.
# - never sed -i: it breaks uid/SELinux context. Use truncate-rewrite.
case "$0" in */*) MODDIR="${0%/*}" ;; *) MODDIR=. ;; esac
MODDIR=$(cd "$MODDIR" 2>/dev/null && pwd) || MODDIR=""
case "$MODDIR" in */scripts) MODDIR="${MODDIR%/scripts}" ;; esac
[ -r "$MODDIR/scripts/env.sh" ] || MODDIR="/data/adb/modules/rmg_netguard"
. "$MODDIR/scripts/env.sh"

mkdir -p "$RUN" "$BKDIR" 2>/dev/null

target_file() {
  uuid=$(meta_active_profile)
  [ -n "$uuid" ] || return 1
  f="$META_IMPORT/$uuid/config.yaml"
  [ -r "$f" ] || return 1
  TARGET_UUID="$uuid"
  TARGET_FILE="$f"
  return 0
}

backup_path() {
  echo "$BKDIR/${TARGET_UUID}.yaml.orig"
}

marker_path() {
  echo "$BKDIR/${TARGET_UUID}.yaml.patched"
}

# Count the `nameserver:` key, accepting BOTH yaml shapes (v2.2.5+).
# Deliberately does NOT match default-nameserver / direct-nameserver /
# nameserver-policy / proxy-server-nameserver.
ns_line_count() {
  grep -cE '^[[:space:]]*nameserver:[[:space:]]*($|\[)' "$TARGET_FILE" 2>/dev/null
}

# Rewrite the nameserver value to NS5591, preserving all other lines and the
# original indentation. Emits to stdout; caller truncates into the target
# (preserves inode/uid/SELinux context). Exits 2 if the layout is ambiguous.
# Output uses a bare yaml scalar (127.0.0.1:5591), valid in both flow and
# block sequences and avoids nested shell quotes.
patch_nameserver() {
  awk -v ns="$NS5591" '
    BEGIN { state = 0; emitted = 0; found = 0 }
    /^[[:space:]]*nameserver:[[:space:]]*\[/ {
      match($0, /^[[:space:]]*/)
      print substr($0, 1, RLENGTH) "nameserver: [" ns "]"
      found++; next
    }
    /^[[:space:]]*nameserver:[[:space:]]*$/ {
      print $0
      state = 1; emitted = 0; found++; next
    }
    state == 1 && /^[[:space:]]*-[[:space:]]/ {
      if (!emitted) {
        match($0, /^[[:space:]]*/)
        print substr($0, 1, RLENGTH) "- " ns
        emitted = 1
      }
      next
    }
    state == 1 { state = 0 }
    { print }
    END { if (found != 1) exit 2 }
  ' "$TARGET_FILE"
}

# Inject `- GEOIP,CN,DIRECT` immediately before `- MATCH,...` if not already
# present. Emits full file to stdout. Safe to call even when GEOIP line exists
# (idempotent: skips injection when already present). Exits 2 on parse error.
patch_geoip_rule() {
  awk '
    BEGIN { found_match = 0; found_geoip = 0; injected = 0 }
    /^[[:space:]]*-[[:space:]]*GEOIP,CN,DIRECT/ { found_geoip = 1 }
    /^[[:space:]]*-[[:space:]]*MATCH,/ {
      found_match++
      if (!found_geoip && !injected) {
        match($0, /^[[:space:]]*/)
        print substr($0, 1, RLENGTH) "- GEOIP,CN,DIRECT"
        injected = 1
      }
    }
    { print }
    END { if (found_match == 0) exit 2 }
  ' "$TARGET_FILE"
}

# Broadcast PROFILE_CHANGED to CMFA so mihomo hot-reloads patched config
# from imported/[UUID]/config.yaml into memory immediately.
# v2.3.0: without this, disk patch is invisible until user reconnects VPN.
broadcast_reload() {
  local uuid="${1:-$TARGET_UUID}"
  [ -n "$uuid" ] || return 0
  am broadcast \
    -a com.github.metacubex.clash.meta.intent.action.PROFILE_CHANGED \
    --es uuid "$uuid" \
    -p com.github.metacubex.clash.meta \
    >/dev/null 2>&1
  log_event "INTEG" "broadcast PROFILE_CHANGED -> CMFA hot-reload ($uuid)"
}

do_apply() {
  target_file || { echo "FAIL: no readable active Meta profile"; return 1; }

  # --- nameserver patch ---
  already_ns=0
  grep -q "$NS5591" "$TARGET_FILE" 2>/dev/null && already_ns=1

  if [ "$already_ns" = "0" ]; then
    n=$(ns_line_count)
    [ "$n" = "1" ] || { echo "FAIL: ambiguous nameserver lines ($n), refusing"; return 1; }
    ORIG="$(backup_path)"
    if [ ! -f "$ORIG" ]; then
      cp -a "$TARGET_FILE" "$ORIG" || { echo "FAIL: backup failed"; return 1; }
      log_event "INTEG" "backup saved: $ORIG"
    fi
    if ! patch_nameserver > "$RUN/.integ.tmp" 2>/dev/null; then
      rm -f "$RUN/.integ.tmp"
      echo "FAIL: patch generation failed (unsupported nameserver layout)"
      return 1
    fi
    if ! grep -q "$NS5591" "$RUN/.integ.tmp"; then
      rm -f "$RUN/.integ.tmp"
      echo "FAIL: NS patch did not take effect"
      return 1
    fi
    cat "$RUN/.integ.tmp" > "$TARGET_FILE"
    rm -f "$RUN/.integ.tmp"
    log_event "INTEG" "applied NS5591 to $TARGET_UUID"
  else
    # Already patched for NS; ensure backup exists
    ORIG="$(backup_path)"
    if [ ! -f "$ORIG" ]; then
      cp -a "$TARGET_FILE" "$ORIG" || { echo "FAIL: backup failed"; return 1; }
      log_event "INTEG" "backup saved (NS already patched): $ORIG"
    fi
  fi

  # --- GEOIP,CN,DIRECT rule patch (v2.3.0) ---
  already_geoip=0
  grep -qE '^[[:space:]]*-[[:space:]]*GEOIP,CN,DIRECT' "$TARGET_FILE" 2>/dev/null && already_geoip=1

  if [ "$already_geoip" = "0" ]; then
    if ! patch_geoip_rule > "$RUN/.geoip.tmp" 2>/dev/null; then
      rm -f "$RUN/.geoip.tmp"
      log_event "INTEG" "WARN: no MATCH rule found, skipping GEOIP injection"
    else
      cat "$RUN/.geoip.tmp" > "$TARGET_FILE"
      rm -f "$RUN/.geoip.tmp"
      log_event "INTEG" "injected GEOIP,CN,DIRECT before MATCH ($TARGET_UUID)"
    fi
  fi

  md5sum "$TARGET_FILE" | cut -d' ' -f1 > "$(marker_path)" 2>/dev/null
  log_event "INTEG" "apply complete ($TARGET_UUID): NS5591+GEOIP patched"
  echo "OK: patched $TARGET_UUID"

  # hot-reload CMFA memory config (v2.3.0)
  broadcast_reload "$TARGET_UUID"
  return 0
}

do_revert() {
  target_file || { echo "FAIL: no readable active Meta profile"; return 1; }
  ORIG="$(backup_path)"
  if [ ! -f "$ORIG" ]; then
    echo "FAIL: no backup for $TARGET_UUID (nothing to revert)"
    return 1
  fi
  if grep -q "$NS5591" "$ORIG"; then
    echo "FAIL: backup itself contains NS5591, refusing (corrupt backup?)"
    return 1
  fi
  cat "$ORIG" > "$TARGET_FILE"
  rm -f "$(marker_path)" 2>/dev/null
  log_event "INTEG" "reverted $TARGET_UUID from backup"
  echo "OK: reverted $TARGET_UUID"

  # hot-reload CMFA so mihomo immediately runs the reverted config (v2.3.0)
  broadcast_reload "$TARGET_UUID"
  return 0
}

do_status() {
  target_file || { echo "profile: none"; return 0; }
  st=$(integration_check)
  ORIG="$(backup_path)"
  MARK="$(marker_path)"
  b="no"; [ -f "$ORIG" ] && b="yes"
  geoip="no"
  grep -qE '^[[:space:]]*-[[:space:]]*GEOIP,CN,DIRECT' "$TARGET_FILE" 2>/dev/null && geoip="yes"
  drift="no"
  if [ -f "$MARK" ] && [ -f "$TARGET_FILE" ]; then
    cur=$(md5sum "$TARGET_FILE" | cut -d' ' -f1)
    want=$(cat "$MARK" 2>/dev/null)
    [ "$cur" = "$want" ] || drift="yes"
  fi
  echo "profile: $TARGET_UUID"
  echo "patched: $st geoip: $geoip backup: $b drifted: $drift"
}

do_auto() {
  # v2.2.5: only repair a patch WE previously applied (marker exists).
  # Old logic re-applied ANY unpatched profile -> 27-retry storm on
  # 2026-10-28, and would silently overwrite a user's deliberate config
  # (e.g. domestic DoH) while the flag happens to be "on".
  # First-time patching is exclusively the WebUI "开启 DNS 集成" action.
  # v2.3.0: also check GEOIP rule; broadcast PROFILE_CHANGED after re-apply.
  [ "$(integ_get)" = "on" ] || return 0
  target_file || return 0
  MARK="$(marker_path)"
  [ -f "$MARK" ] || return 0
  st=$(integration_check)
  if [ "$st" = "unpatched" ]; then
    log_event "INTEG" "drift detected (patch lost), re-applying"
    do_apply >/dev/null 2>&1
  else
    cur=$(md5sum "$TARGET_FILE" | cut -d' ' -f1)
    want=$(cat "$MARK" 2>/dev/null)
    if [ "$cur" != "$want" ]; then
      # Content changed but NS still patched (e.g. subscription update may
      # have wiped GEOIP rule) -> re-run apply to restore GEOIP and refresh marker
      log_event "INTEG" "content drifted after subscription update, re-patching GEOIP+marker"
      do_apply >/dev/null 2>&1
    fi
  fi
  return 0
}

# ---- AGH upstream drift guard (v2.3.1) ----
# Enforces safe upstream DNS in AdGuardHome.yaml: removes 1.12.12.12,
# 1.1.1.1, 8.8.8.8 and rewrites upstream_dns/fallback_dns/bootstrap_dns to
# pure-IP CNdoH entries. Called by guard.sh every cycle and manually via
# config_toggle.sh agh_guard.
# SAFETY: always verifies PID cmdline before SIGHUP; never overwrites the
# first backup (AdGuardHome.yaml.orig) so uninstall.sh can restore it.
AGH_YAML="${AGH_DIR}/bin/AdGuardHome.yaml"
AGH_UNSAFE_PATTERN='1\.12\.12\.12|1\.1\.1\.1|8\.8\.8\.8'

agh_upstream_needs_fix() {
  [ -r "$AGH_YAML" ] || return 1
  grep -qE "$AGH_UNSAFE_PATTERN" "$AGH_YAML" 2>/dev/null
}

do_agh_guard() {
  [ -r "$AGH_YAML" ] || return 0
  agh_upstream_needs_fix || { echo "OK: AGH upstream already safe"; return 0; }
  # First backup only: never overwrite the original
  BKFILE="$BKDIR/AdGuardHome.yaml.orig"
  if [ ! -f "$BKFILE" ]; then
    mkdir -p "$BKDIR" 2>/dev/null
    cp -a "$AGH_YAML" "$BKFILE" || { log_event "AGH_GUARD" "FAIL: backup failed"; return 1; }
    log_event "AGH_GUARD" "AGH yaml first backup saved: $BKFILE"
  fi
  TMP="$RUN/.agh_yaml.$$"
  awk '
    /^  upstream_dns:/ {
      print "  upstream_dns:"
      print "    - https://223.5.5.5/dns-query"
      print "    - https://223.6.6.6/dns-query"
      skip=1; next
    }
    /^  fallback_dns:/ {
      print "  fallback_dns:"
      print "    - https://119.29.29.29/dns-query"
      skip=2; next
    }
    /^  bootstrap_dns:/ {
      print "  bootstrap_dns:"
      print "    - 119.29.29.29"
      print "    - 223.5.5.5"
      print "    - 223.6.6.6"
      skip=3; next
    }
    skip>0 && /^    - / { next }
    skip>0 && !/^    / { skip=0 }
    { print }
  ' "$AGH_YAML" > "$TMP" || { rm -f "$TMP"; log_event "AGH_GUARD" "FAIL: awk rewrite failed"; return 1; }
  # Sanity: new file must have safe upstream and must NOT contain unsafe entries
  if ! grep -q '223.5.5.5' "$TMP" || grep -qE "$AGH_UNSAFE_PATTERN" "$TMP"; then
    rm -f "$TMP"; log_event "AGH_GUARD" "FAIL: generated yaml invalid or still unsafe"; return 1
  fi
  cat "$TMP" > "$AGH_YAML"; rm -f "$TMP"
  log_event "AGH_GUARD" "AGH upstream auto-corrected (removed unsafe entries)"
  # SIGHUP to live AGH process (anti-brick: verify cmdline first)
  local pid cmd
  pid=$(pidof AdGuardHome 2>/dev/null)
  if [ -n "$pid" ]; then
    cmd=$(cat /proc/$pid/cmdline 2>/dev/null | tr '\0' ' ')
    case "$cmd" in
      *AdGuardHome*)
        kill -HUP "$pid" 2>/dev/null
        log_event "AGH_GUARD" "SIGHUP sent to AGH pid=$pid"
        ;;
    esac
  fi
  echo "OK: AGH upstream corrected"
}

case "$1" in
  apply)     do_apply; exit $? ;;
  revert)    do_revert; exit $? ;;
  status)    do_status ;;
  auto)      do_auto; exit $? ;;
  agh_guard) do_agh_guard; exit $? ;;
  *) echo "Usage: config_toggle.sh {apply|revert|status|auto|agh_guard}"; exit 1 ;;
esac
exit 0
