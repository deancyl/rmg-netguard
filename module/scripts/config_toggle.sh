#!/system/bin/sh
# RMG NetGuard v2.2.5 - DNS integration toggle for Clash Meta active profile.
# Applies/reverts nameserver -> 127.0.0.1:5591 in the ACTIVE profile's
# config.yaml so mihomo routes its upstream through AGH (track B filter).
#
# apply  : backup once (never overwrite first backup), patch, record md5
# revert : restore from first backup (user data wins)
# status : patched? backup? drifted? (profile changed since last apply)
# auto   : re-apply ONLY when a patch we previously applied was lost
#
# Notes learned on-device (2026-10-15 / 2026-11-06):
# - CMFA override.json is SUPPRESSED by the profile's own dns: section, so
#   patching the profile file is the only working hook.
# - subscription updates rewrite the imported profile -> drift detection +
#   auto-reapply is mandatory (WebUI "integration" toggle owns this).
# - nameserver has TWO yaml shapes: inline array `nameserver: [ ... ]` and
#   block list `nameserver:` + `- item` lines. v2.2.5 supports both; the old
#   sed only matched the inline form and refused block-list profiles forever
#   (FAIL: ambiguous nameserver lines (0) -> 27-retry storm on 2026-10-28).
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

# Count the `nameserver:` key, accepting BOTH yaml shapes (v2.2.5).
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

do_apply() {
  target_file || { echo "FAIL: no readable active Meta profile"; return 1; }
  if grep -q "$NS5591" "$TARGET_FILE" 2>/dev/null; then
    md5sum "$TARGET_FILE" | cut -d' ' -f1 > "$(marker_path)" 2>/dev/null
    echo "OK: already patched ($TARGET_UUID)"
    return 0
  fi
  n=$(ns_line_count)
  [ "$n" = "1" ] || { echo "FAIL: ambiguous nameserver lines ($n), refusing"; return 1; }
  ORIG="$(backup_path)"
  if [ ! -f "$ORIG" ]; then
    cp -a "$TARGET_FILE" "$ORIG" || { echo "FAIL: backup failed"; return 1; }
    log_event "INTEG" "backup saved: $ORIG"
  fi
  # patch via generated content + truncate-rewrite (preserves inode, uid,
  # SELinux context). v2.2.5: handles inline-array AND block-list shapes.
  if ! patch_nameserver > "$RUN/.integ.tmp" 2>/dev/null; then
    rm -f "$RUN/.integ.tmp"
    echo "FAIL: patch generation failed (unsupported nameserver layout)"
    return 1
  fi
  if ! grep -q "$NS5591" "$RUN/.integ.tmp"; then
    rm -f "$RUN/.integ.tmp"
    echo "FAIL: patch did not take effect"
    return 1
  fi
  cat "$RUN/.integ.tmp" > "$TARGET_FILE"
  rm -f "$RUN/.integ.tmp"
  md5sum "$TARGET_FILE" | cut -d' ' -f1 > "$(marker_path)" 2>/dev/null
  log_event "INTEG" "applied NS5591 to $TARGET_UUID (profile patched)"
  echo "OK: patched $TARGET_UUID"
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
  return 0
}

do_status() {
  target_file || { echo "profile: none"; return 0; }
  st=$(integration_check)
  ORIG="$(backup_path)"
  MARK="$(marker_path)"
  b="no"; [ -f "$ORIG" ] && b="yes"
  drift="no"
  if [ -f "$MARK" ] && [ -f "$TARGET_FILE" ]; then
    cur=$(md5sum "$TARGET_FILE" | cut -d' ' -f1)
    want=$(cat "$MARK" 2>/dev/null)
    [ "$cur" = "$want" ] || drift="yes"
  fi
  echo "profile: $TARGET_UUID"
  echo "patched: $st backup: $b drifted: $drift"
}

do_auto() {
  # v2.2.5: only repair a patch WE previously applied (marker exists).
  # Old logic re-applied ANY unpatched profile -> 27-retry storm on
  # 2026-10-28, and would silently overwrite a user's deliberate config
  # (e.g. domestic DoH) while the flag happens to be "on".
  # First-time patching is exclusively the WebUI "开启 DNS 集成" action.
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
      # content changed but still patched (e.g. subscription update) -> refresh marker
      md5sum "$TARGET_FILE" | cut -d' ' -f1 > "$MARK" 2>/dev/null
      log_event "INTEG" "marker refreshed after profile change ($TARGET_UUID)"
    fi
  fi
  return 0
}

case "$1" in
  apply) do_apply; exit $? ;;
  revert) do_revert; exit $? ;;
  status) do_status ;;
  auto) do_auto; exit $? ;;
  *) echo "Usage: config_toggle.sh {apply|revert|status|auto}"; exit 1 ;;
esac
exit 0
