# RMG NetGuard Wiki

RMG NetGuard 是面向 KernelSU 的 DNS / VPN 双轨守护模块，用于协调
AdGuard Home 与 Clash Meta / mihomo 的 DNS 路径。默认 `observe`，只有用户明确
操作后才会自动切换劫持或修改活动 profile。

## 快速入口

- [安装与升级](安装与升级)：前置条件、刷入、升级、卸载和回滚。
- [WebUI 使用](WebUI-使用)：状态含义、按钮、确认条和自动刷新。
- [架构与工作模式](架构与工作模式)：双轨拓扑、健康门控和配置集成。
- [故障排查与恢复](故障排查与恢复)：DNS 黑洞、状态不一致、探针异常。
- [开发与验证](开发与验证)：构建、测试、发布和代码结构。

## 当前版本

- 主线版本：`v2.3.2`（`versionCode=30`，已合入 `main` 并部署验证设备）
- 最新 Release tag：`v2.2.1`；v2.2.2–v2.3.1 为主线提交，尚未打 tag，见 [CHANGELOG](https://github.com/deancyl/rmg-netguard/blob/main/CHANGELOG.md)
- 模块 ID：`rmg_netguard`
- 已验证环境：KernelSU 3.3.1 late-load、Android 16、SM-S9180
- 默认模式：`observe`（只看不动）

## 安装前检查

1. KernelSU 能正常打开模块 WebUI。
2. AdGuard Home 已运行，5591 能响应 DNS。
3. 如需 DNS 集成，Clash Meta 活动 profile 可读。
4. 已记录当前 `iptables`、活动 profile 和模块状态。
5. 已确认设备的安全模式或模块禁用方式可用。

生产设备请先在 `observe` 下运行，确认状态稳定后再启用 `auto` 或 DNS 集成。

## 设计原则

- 默认不干预：不自动改变劫持拓扑；但 DNS 集成一旦开启，其漂移重打独立于模式。
- `attach`（恢复劫持）必须通过 AGH 健康门控；`detach`（摘除劫持）是 fail-open 救援方向，不受门控阻断。
- 只改变一条 `nat OUTPUT` 跳转，不重建 AGH 链体；profile 修改先备份、可还原。
- 失败必须返回非零状态并在 WebUI 红色显示。
- 不使用阻塞式 `confirm` / `alert`。

## 术语对照

| WebUI 用语 | 脚本 / 日志用语 | 含义 |
|---|---|---|
| 只看不动 | `observe`、`MODE_FILE=observe` | 不自动摘/挂劫持 |
| 自动切换 | `auto`、`double-track` | VPN 稳定态后自动摘/挂劫持 |
| 摘除 AGH 劫持 | `detach`、`track B`、`RESCUE` | 移除 OUTPUT 跳转 |
| 恢复 AGH 劫持 | `attach`、`track A` | 插回 OUTPUT 跳转 |
| DNS 集成 | `NS5591`、`integration`、`profile 补丁` | 活动 profile 上游指向 AGH:5591 |
| AGH 53 劫持 | `ADGUARD_REDIRECT_DNS` 链跳转 | nat OUTPUT 上的那一条 jump |

## 相关链接

- [README](https://github.com/deancyl/rmg-netguard#readme)
- [Releases](https://github.com/deancyl/rmg-netguard/releases)
- [变更记录](https://github.com/deancyl/rmg-netguard/blob/main/CHANGELOG.md)
- [安全策略](https://github.com/deancyl/rmg-netguard/blob/main/SECURITY.md)
