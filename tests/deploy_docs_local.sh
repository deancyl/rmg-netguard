#!/usr/bin/env bash
# RMG NetGuard v2.2.4 documentation/UI hot-deploy (no guard logic change).
# Usage (after the device is connected and USB debugging authorized):
#   bash tests/deploy_docs_local.sh
# Safe: only replaces webroot/index.html, scripts/webui.sh,
#       scripts/controller.sh (comments only) and module.prop.
# Does NOT touch mode / integration / hijack / guard process.
set -euo pipefail
export MSYS_NO_PATHCONV=1
ADB="D:/WorkBuddy/RootMyGalaxy/porting/tools/platform-tools/adb.exe"
DEV="R5CW21C5WHB"
ROOT="D:/WorkBuddy/RootMyGalaxy/porting/rmg-netguard"

"$ADB" devices | grep -q "$DEV" || { echo "DEVICE NOT CONNECTED: $DEV"; exit 1; }

for f in module/webroot/index.html module/scripts/webui.sh \
         module/scripts/controller.sh module/module.prop; do
  "$ADB" -s "$DEV" push "$ROOT/$f" "/data/local/tmp/$(basename "$f")" >/dev/null
done

cat > /tmp/ng_install_docs.sh <<'EOS'
#!/system/bin/sh
M=/data/adb/modules/rmg_netguard
cat /data/local/tmp/index.html > $M/webroot/index.html
cat /data/local/tmp/webui.sh > $M/scripts/webui.sh
cat /data/local/tmp/controller.sh > $M/scripts/controller.sh
cat /data/local/tmp/module.prop > $M/module.prop
chmod 644 $M/webroot/index.html $M/module.prop
chmod 755 $M/scripts/*.sh
echo "== version =="; grep -E '^version' $M/module.prop
echo "== status_fast carries version =="; sh $M/scripts/webui.sh status_fast | grep '^version='
echo "== event log size =="; sh $M/scripts/webui.sh log | head -1
echo "== guard untouched =="; echo "pid=$(cat $M/run/guard.pid)"
echo DEPLOY_OK
EOS
"$ADB" -s "$DEV" push "$(cygpath -w /tmp/ng_install_docs.sh)" /data/local/tmp/ng_install_docs.sh >/dev/null
"$ADB" -s "$DEV" shell "su -c 'sh /data/local/tmp/ng_install_docs.sh'"
