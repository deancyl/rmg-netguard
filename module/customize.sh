# RMG NetGuard customize.sh (sourced by KernelSU installer)
SKIPUNZIP=0

# Read version dynamically from module.prop (single source of truth; v2.3.0+)
_VER=$(grep '^version=' "$MODPATH/module.prop" 2>/dev/null | cut -d= -f2)
_VER="${_VER:-unknown}"

ui_print "- RMG NetGuard ${_VER} (rmg_netguard)"
ui_print "- 双轨接管守护: 默认仅观测; 自动双轨/DNS 集成均需 WebUI 显式开启"
ui_print "- 设备: $(getprop ro.product.model) / Android $(getprop ro.build.version.release)"

# script permissions (webroot perms are managed by KernelSU automatically)
set_perm_recursive "$MODPATH/scripts" root root 0755 0755
set_perm "$MODPATH/service.sh" root root 0755
set_perm "$MODPATH/uninstall.sh" root root 0755
set_perm "$MODPATH/action.sh" root root 0755

mkdir -p "$MODPATH/run"
chmod 755 "$MODPATH/run"

# Migrate run-time data from previous installation (v2.3.0+).
# KernelSU installs to /data/adb/modules_update/<id> first; the old live
# module is still at /data/adb/modules/<id>/run until next reboot.
# We copy mode, integration, events.log, config, and backups/ so that
# the user's settings and history survive an in-place upgrade.
_OLD_RUN="/data/adb/modules/rmg_netguard/run"
_NEW_RUN="$MODPATH/run"
if [ -d "$_OLD_RUN" ]; then
  ui_print "- 升级迁移: 保留旧 run/ 数据"
  for _f in mode integration events.log config; do
    if [ -f "$_OLD_RUN/$_f" ]; then
      cp -a "$_OLD_RUN/$_f" "$_NEW_RUN/$_f" 2>/dev/null \
        && ui_print "  migrated: $_f"
    fi
  done
  if [ -d "$_OLD_RUN/backups" ]; then
    mkdir -p "$_NEW_RUN/backups"
    cp -a "$_OLD_RUN/backups/." "$_NEW_RUN/backups/" 2>/dev/null \
      && ui_print "  migrated: backups/"
  fi
fi

ui_print "- 安装完成。首次生效需重启或手动执行 service.sh (late-load 会话)"
ui_print "- WebUI: 管理器模块卡片 -> 打开面板; Action: 一键体检"
