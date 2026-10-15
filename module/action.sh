#!/system/bin/sh
# RMG NetGuard - KernelSU Manager Action button: one-shot full diagnostics.
MODDIR=${0%/*}
ui_print() { echo "$1"; }
ui_print "RMG NetGuard 一次性体检"
sh "$MODDIR/scripts/probe.sh" 2>&1 | while IFS= read -r line; do ui_print "$line"; done
ui_print "---- 规则健康审计 ----"
sh "$MODDIR/scripts/rules_audit.sh" 2>&1 | while IFS= read -r line; do ui_print "$line"; done
ui_print "完成。"
exit 0
