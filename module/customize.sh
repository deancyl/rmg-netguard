# RMG NetGuard customize.sh (sourced by KernelSU installer)
SKIPUNZIP=0

ui_print "- RMG NetGuard v2.0.0 (rmg_netguard)"
ui_print "- 双轨接管守护: 默认仅观测; 自动双轨/DNS 集成均需 WebUI 显式开启"
ui_print "- 设备: $(getprop ro.product.model) / Android $(getprop ro.build.version.release)"

# script permissions (webroot perms are managed by KernelSU automatically)
set_perm_recursive "$MODPATH/scripts" root root 0755 0755
set_perm "$MODPATH/service.sh" root root 0755
set_perm "$MODPATH/uninstall.sh" root root 0755
set_perm "$MODPATH/action.sh" root root 0755

mkdir -p "$MODPATH/run"
chmod 755 "$MODPATH/run"

ui_print "- 安装完成。首次生效需重启或手动执行 service.sh (late-load 会话)"
ui_print "- WebUI: 管理器模块卡片 -> 打开面板; Action: 一键体检"
