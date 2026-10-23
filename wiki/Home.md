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

- 最新发布：`v2.2.1`
- `versionCode`：`23`
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

- 默认不干预。
- 动作前必须通过 AGH 健康门控。
- 只改变一条 `nat OUTPUT` 跳转，不重建 AGH 链体。
- profile 修改先备份，漂移可重打，卸载可恢复。
- 失败必须返回非零状态并在 WebUI 红色显示。
- 不使用阻塞式 `confirm` / `alert`。

## 相关链接

- [README](https://github.com/deancyl/rmg-netguard#readme)
- [Releases](https://github.com/deancyl/rmg-netguard/releases)
- [变更记录](https://github.com/deancyl/rmg-netguard/blob/main/CHANGELOG.md)
- [安全策略](https://github.com/deancyl/rmg-netguard/blob/main/SECURITY.md)
