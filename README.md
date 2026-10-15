# RMG NetGuard (rmg_netguard) v2.0.0

DNS / VPN 双轨接管守护模块（KernelSU，late-load 兼容）。基于 2026-10-14/15 排查报告
`S9180_网络卡顿全面排查与优化模块设计报告_2026-10-14.md` 的四项约束设计。

## v2.0.0 架构（2026-10-15）

**双轨道拓扑**（切换只动 nat OUTPUT 上那一条 jump，链体永不触碰）：
- **轨道 A**（VPN 关 / 劫持 ON）：App 53 → AGH 过滤 → 国内 DoH 直连
- **轨道 B**（VPN 开 / 劫持 OFF）：App DNS → TUN → mihomo → **AGH:5591 过滤** → GEOIP 分流
  （前提：mihomo 上游指向 AGH，即"DNS 集成"，见下）

**模式**（`run/mode`，WebUI 切换）：
- `observe`（默认）：v1.0.1 行为，零干预
- `auto`：VPN 状态滞留 2 轮（防抖）后，经 **健康门**（AGH 进程存活 + 5591 UDP 应答，
  双向同门）执行 `controller.sh detach/attach`；flock 单写者；幂等；动作全程写 events.log

**DNS 集成开关**（`run/integration`，WebUI 切换；`config_toggle.sh`）：
- apply：备份活动 Meta profile（首份永不覆盖）→ nameserver 补丁为 `['127.0.0.1:5591']`
  （sed 到临时文件 + cat 截断重写，保留 uid/SELinux context）→ 记录 md5 marker
- 漂移看门狗：guard 每 5 轮 `config_toggle auto`——订阅更新覆盖 profile 后自动重打
- revert：从首份备份还原（还原前校验备份自身不含 NS5591，防污染备份）
- 卸载自动还原全部备份 + 劫持

**检测能力**（v2 较 v1 增强）：
- 过滤探针 `filter_probe`：向 AGH:5591 直接查询实测被拦域名（api.ad.xiaomi.com，
  0.0.0.0/TTL10 已验证），双信号判定（rcode3 NXDOMAIN / rdata 00000000）→ BLOCKED/OPEN/UNKNOWN
- 客户端识别（meta/flclash/none）、轨道判定（A/B/-）、AGH querylog 近段统计
  （total/filtered/loopback + top 拦截域名）
- WebUI：状态卡（含模式/轨道/客户端/探针徽章）、模式切换、集成开关（带确认与还原）、
  体检/审计/统计/日志四个输出面板、30s 自动刷新可选

**关键设计不变量**：
1. 两轨道各自功能完备——切换失败/延迟只是次优拓扑，不是故障（正确性不依赖切换）
2. AGH 不应答时任何方向的动作都会被拒绝（杜绝 DOWN_PORT 黑洞）
3. 集成补丁的原始备份永不覆盖；备份含 NS5591 时拒绝还原（防污染）
4. 全部动作可逆、可审计（events.log）

**已知遗留**：`nameserver-policy geosite:cn→[system]` 使国内域名绕过 AGH（订阅
profile 层配置，改动需评估 rule 命中面）；CMFA override.json 被 profile dns 段压制
（故集成走 profile 直补路径）。

## v1.0.1 变更（2026-10-15）

- **DNS 探测降频**：curl 延迟测量仅在状态迁移或每 `DNS_EVERY`（默认 5）轮执行，
  其余轮复用上次实测值；告警事件只对新鲜测量值触发，陈旧值不会重复告警。
  探测流量降 ~80%（960 → 约 200 次/日）。
- **PID 复用防护**：service.sh / uninstall.sh kill 旧实例前校验
  `/proc/<pid>/cmdline` 必须匹配本模块 guard 路径，消除理论误杀。
- **config 白名单**：`run/config` 仅接受空行/注释/`VAR=安全字符` 赋值行，
  含其他内容整份拒绝并记 WARN，杜绝经配置路径的代码注入。
- **审计自适应**：进入 RISK_COEXIST 状态的迁移轮立即执行一次规则审计，
  WARN 与风险态同帧对齐，便于取证。

## 设计要点

- **只观测**：guard.sh 循环采集 tun0（含 FlClash 命名）、AGH 劫持链（nat OUTPUT）、
  AGH 5591 / mihomo 1053 监听、AGH 进程、系统路径 DNS 延迟，写 run/state.json。
- **状态机**：`RISK_COEXIST`（VPN+劫持并存=串联风险）/ `INCONSISTENT`（AGH 进程在但规则不在，
  即 10-13 实证缺陷态）/ `DOWN_PORT`（劫持在挂但 5591 无监听=全机 DNS 黑洞）/ `NORMAL`。
- **事件**：仅状态迁移与 DNS 延迟 >800ms（可配）写 events.log（滚动 200 行）。
- **规则审计**（只读，30min 一次 + 手动）：扫描 FlClash 全部 profile 与 Clash Meta 活动
  profile 的 GEOIP,CN 兜底；检查 default-nameserver 是否误指 5591（冷启动死锁风险）；
  检查 AGH 境外 DoH fallback 与停止不对称缺陷态。
- **救援仅手动**：rescue.sh remove/restore 仅由 WebUI / Action 触发；只摘/插
  `OUTPUT -> ADGUARD_REDIRECT_DNS` 一条 jump（链体保留）；卸载时若曾摘除自动还原。

## late-load 适配（本机 KSU = late-load）

- 入口仅 `service.sh`（late_start，late-load 模式下确认执行）；**无 post-fs-data.sh、无 initrc/**
  （late-load 下不可用）。
- 单例保护：root 守护跨 KSU 软重启存活，service.sh 启动时按 pidfile + pkill 清理旧实例。

## 构建 / 安装 / 验证 / 回滚

```bash
# 构建（本机）
python build_zip.py            # 产出 rmg-netguard-v1.0.1.zip

# 安装（二选一）
# A. 管理器刷入 zip
# B. adb:
adb -s R5CW21C5WHB push rmg-netguard-v1.0.1.zip /data/local/tmp/
adb -s R5CW21C5WHB shell "su -c 'ksud module install /data/local/tmp/rmg-netguard-v1.0.1.zip'"

# 首次启动（不重启，late-load 会话内）
adb -s R5CW21C5WHB shell "su -c 'sh /data/adb/modules/rmg_netguard/service.sh'"

# 验证
adb -s R5CW21C5WHB shell "su -c 'sh /data/adb/modules/rmg_netguard/scripts/probe.sh'"
adb -s R5CW21C5WHB shell "su -c 'cat /data/adb/modules/rmg_netguard/run/state.json'"
adb -s R5CW21C5WHB shell "su -c 'sh /data/adb/modules/rmg_netguard/scripts/rules_audit.sh'"

# 回滚 / 卸载（无任何持久化系统修改）
adb -s R5CW21C5WHB shell "su -c 'ksud module disable rmg_netguard'"   # 禁用
adb -s R5CW21C5WHB shell "su -c 'ksud module uninstall rmg_netguard'" # 卸载(uninstall.sh 自动清理)
# 或 KSU 管理器操作；紧急情况：开机音量下×3 安全模式即全模块禁用
```

## 验收基准（部署后）

| 项 | 断言 |
|---|---|
| 单例 | 连续 3 次 `sh service.sh` 后 `pgrep -f guard.sh` 仅 1 个 |
| 状态判定 | 当前真机（VPN 开 + 劫持在挂）state.json 应为 `RISK_COEXIST` |
| 事件 | 开关 VPN 各一次，events.log 各记录一条 STATE 迁移 |
| 功耗 | 24h 后 `top -n 1` guard 相关 CPU 时间 < 30s |
| 零干预 | 72h 内 `iptables -S` 无本模块产生的任何链/jump |
