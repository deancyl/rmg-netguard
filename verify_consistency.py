#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Version + documentation consistency gate.

Rationale (2026-11-05): v2.2.2/v2.2.3 shipped code fixes (fail-open detach,
track-B classifier) without updating the UI text, README, wiki or version
strings. This script makes that class of drift fail in CI.

Checks:
  1. one version source (module/module.prop) reflected everywhere;
  2. no hardcoded version in the build/verify scripts;
  3. forbidden stale statements never return to user-facing docs;
  4. required new statements (fail-open, VPN restart, timings) stay present.

Exit 0 = all green, 1 = drift detected. Pure stdlib, LF, ASCII output only.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def read(rel):
    with open(os.path.join(HERE, rel), "r", encoding="utf-8") as f:
        return f.read()


def version():
    for line in read("module/module.prop").splitlines():
        if line.startswith("version="):
            return line.split("=", 1)[1].strip()
    raise SystemExit("FATAL: version= missing in module/module.prop")


V = version()
fails = []
passes = []


def check(name, ok, detail=""):
    (passes if ok else fails).append(name)
    print(("PASS  " if ok else "FAIL  ") + name + ((" -> " + detail) if detail and not ok else ""))


def has(rel, needle):
    return needle in read(rel)


# ---- 1. version is a single source of truth --------------------------------
prop = read("module/module.prop")
check("module.prop version present", bool(V), V)
check("module.prop description starts with version",
      ("description=RMG NetGuard " + V) in prop)
vc = [l.split("=", 1)[1].strip() for l in prop.splitlines()
      if l.startswith("versionCode=")]
check("module.prop versionCode present", bool(vc and vc[0].isdigit()), vc[0] if vc else "missing")

check("index.html static fallback version",
      ('id="ui_ver">' + V + "<") in read("module/webroot/index.html"))
try:
    pkg = json.loads(read("package.json"))
    check("package.json version", pkg.get("version") == V.lstrip("v"),
          "got %s, want %s" % (pkg.get("version"), V.lstrip("v")))
except ValueError as e:
    check("package.json version", False, str(e))

check("CHANGELOG contains current version", ("## " + V) in read("CHANGELOG.md"))
check("README version section", ("当前主线版本：`" + V + "`") in read("README.md"))
check("wiki/Home mainline version", ("主线版本：`" + V + "`") in read("wiki/Home.md"))

for rel in ("build_zip.py", "verify_zip.py"):
    body = read(rel)
    check(rel + " reads module.prop", "module.prop" in body and "module_version()" in body)
    check(rel + " has no hardcoded zip version",
          ("rmg-netguard-" + V + ".zip") not in body and 'OUT = os.path.join(HERE, "rmg-netguard-v2.' not in body)

# stale concrete versions in user-facing install docs
for rel in ("README.md", "wiki/安装与升级.md"):
    check(rel + " has no stale v2.2.1 download filename",
          "rmg-netguard-v2.2.1.zip" not in read(rel))

# ---- 2. statements that must NOT come back --------------------------------
FORBIDDEN = {
    "module/webroot/index.html": [
        "任何切换都会被拒绝",
        "零干预，只记录状态",
        "事件日志（最近 20 条）",
        "未安装 AGH/Clash 时模块为纯观测空载",
        "状态每 90 秒由后台刷新一次",
    ],
    "README.md": [
        "默认只观测、不修改网络",
        "任何方向的自动切换都会被拒绝",
        "当前版本：`v2.2.1`",
    ],
    "wiki/Home.md": [
        "动作前必须通过 AGH 健康门控",
        "最新发布：`v2.2.1`",
    ],
    "wiki/WebUI-使用.md": [
        "不上传网络规则，只记录状态",
        "每次动作前都会检查 AGH 进程和 5591 应答",
        "最近 20 条模块事件",
    ],
    "wiki/架构与工作模式.md": [
        "在 attach 与 detach 前都要求",
        "| `INCONSISTENT` | AGH 进程存在但劫持缺失 |",
        "前提：VPN 开启，AGH 劫持摘除，mihomo 上游指向 AGH。",
    ],
    "wiki/故障排查与恢复.md": [
        "只有在确认健康门控条件后才执行网络动作。",
        "含义：AGH 进程存在，但 `OUTPUT -> ADGUARD_REDIRECT_DNS` 不存在。",
    ],
    "module/scripts/controller.sh": [
        "# health gate: BOTH directions require AGH alive",
    ],
    "module/scripts/webui.sh": [
        "by the click-to-refresh button",
    ],
}

# ---- 3. statements that must STAY -----------------------------------------
REQUIRED = {
    "module/webroot/index.html": [
        "fail-open", "重开一次", "300 秒", "最近 50 条", "约 3 分钟", "version=",
    ],
    "README.md": ["fail-open", "重开一次", "独立于", "RESCUE"],
    "wiki/Home.md": ["fail-open", "术语对照"],
    "wiki/WebUI-使用.md": ["不会立即改变", "重开一次", "fail-open", "50 条"],
    "wiki/架构与工作模式.md": ["方向不对称", "不受健康门阻断", "NORMAL", "INCONSISTENT"],
    "wiki/故障排查与恢复.md": ["fail-open", "摘除 AGH 劫持", "NORMAL"],
    "wiki/安装与升级.md": ["重开一次", "verify_consistency.py"],
    "wiki/开发与验证.md": ["唯一版本源", "verify_consistency.py"],
    "module/scripts/webui.sh": ["version=", "最近 50 行"],
    "module/scripts/config_toggle.sh": ["patch_nameserver()", "block-list", "[ -f \"$MARK\" ] || return 0"],
    "module/scripts/rules_audit.sh": ["RULE-SET,(cn|cn-ip|china)", "有 RULE-SET/GEOSITE 国内直连覆盖"],
    "tests/test_config_toggle.sh": ["block-list", "auto: no marker", "re-apply"],
}

for rel, needles in FORBIDDEN.items():
    body = read(rel)
    for n in needles:
        check("no stale text in " + rel + ": " + n[:28], n not in body,
              "remove or rephrase")

for rel, needles in REQUIRED.items():
    body = read(rel)
    for n in needles:
        check("required text in " + rel + ": " + n[:28], n in body,
              "statement missing")

print("\nversion=%s  passed=%d  failed=%d" % (V, len(passes), len(fails)))
if fails:
    print("Consistency gate FAILED. Fix the items above before pushing.")
    sys.exit(1)
print("Consistency gate OK.")
