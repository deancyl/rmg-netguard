#!/system/bin/sh
# RMG NetGuard v2.0 - DNS integration toggle for Clash Meta active profile.
# Applies/reverts nameserver -> 127.0.0.1:5591 in the ACTIVE profile's
# config.yaml so mihomo routes its upstream through AGH (track B filter).
#
# apply  : backup once (never overwrite first backup), patch, record md5
# revert : restore from first backup (user data wins)
# status : patched? backup? drifted? (profile changed since last apply)
# auto   : re-apply when drifted (guard-loop watchdog entry point)
#
# Notes learned on-device (2026-10-15):
# - CMFA override.json is SUPPRESSED by the profile's own dns: section, so
#   patching the profile file is the only working hook.
# - subscription updates rewrite the imported profile -> drift detection +
#   auto-reapply is mandatory (WebUI "integration" toggle owns this).
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

# count top-level nameserver list lines (guard against ambiguous yaml)
ns_line_count() {
  grep -cE '^[[:space:]]*nameserver: \[' "$TARGET_FILE" 2>/dev/null
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
  # patch via truncate-rewrite (preserves inode, uid, SELinux context)
  sed -E "s/^([[:space:]]*)nameserver: \[.*\]$/\1nameserver: ['$NS5591']/" \
      "$TARGET_FILE" > "$RUN/.integ.tmp" || { echo "FAIL: sed error"; return 1; }
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
  # guard-loop watchdog: keep integration consistent when enabled
  [ "$(integ_get)" = "on" ] || return 0
  target_file || return 0
  MARK="$(marker_path)"
  st=$(integration_check)
  if [ "$st" = "unpatched" ]; then
    log_event "INTEG" "drift detected (unpatched), re-applying"
    do_apply >/dev/null 2>&1
  elif [ -f "$MARK" ] && [ -f "$TARGET_FILE" ]; then
    cur=$(md5sum "$TARGET_FILE" | cut -d' ' -f1)
    want=$(cat "$MARK" 2>/dev/null)
    if [ "$cur" != "$want" ] && grep -q "$NS5591" "$TARGET_FILE"; then
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
