# RMG NetGuard

面向 KernelSU 的 DNS / VPN 双轨守护模块，用于协调 AdGuard Home（AGH）与
Clash Meta / mihomo 的 DNS 接管关系。默认只观测、不修改网络；自动切换与
DNS 集成都必须由用户在 WebUI 中显式开启。

[![Latest release](https://img.shields.io/github/v/release/deancyl/rmg-netguard?sort=semver)](https://github.com/deancyl/rmg-netguard/releases/latest)
[![KernelSU](https://img.shields.io/badge/KernelSU-late--load-2ea44f)](https://kernelsu.org/zh_CN/guide/module.html)
[![Android](https://img.shields.io/badge/Android-16-3ddc84)](https://github.com/deancyl/rmg-netguard)
[![Shell](https://img.shields.io/badge/runtime-Android%20sh-4eaa25)](https://github.com/deancyl/rmg-netguard)

> 这是会修改 `iptables` 和 Clash Meta 活动配置的生产级模块。安装前请阅读
> [安全边界](#安全边界) 与 [故障恢复](https://github.com/deancyl/rmg-netguard/wiki/故障排查与恢复)。

## 功能

- **双轨拓扑**：VPN 关闭时由 `nat OUTPUT` 劫持 DNS 到 AGH；VPN 开启时可摘除
  劫持，让 mihomo 的上游继续经过 AGH。
- **默认只观测**：`observe` 模式不下发任何网络规则，适合先部署、看状态、再启用。
- **健康门控自动切换**：AGH 进程与 5591 DNS 应答都正常时才允许
  `attach` / `detach`；VPN 状态需连续两轮稳定后才动作。
- **DNS 集成可逆**：修改 Clash Meta 活动 profile 前自动备份，检测订阅更新导致的
  漂移并重打补丁，卸载时恢复原配置。
- **KernelSU WebUI**：顶部常驻状态、快照时间、就近操作反馈、面板内确认、
  自动刷新和单飞任务锁。
- **可观测**：状态机、事件日志、规则审计、过滤探针和 AGH querylog 统计。
- **空载友好**：未安装 AGH / Clash 时进入纯观测空载，不等待探针、不写 netfilter。

## 工作模式

| 模式 | 行为 | 适合场景 |
|---|---|---|
| `observe` | 只采样状态，不摘取或恢复劫持 | 首次安装、排障、稳定优先 |
| `auto` | VPN 稳定开启后摘除劫持；VPN 关闭后恢复劫持 | AGH 与 Clash Meta 已稳定共存 |

两条轨道的目标拓扑：

| 轨道 | 条件 | DNS 路径 |
|---|---|---|
| A | VPN 关闭，AGH 劫持启用 | App 53 → AGH → 上游 DNS |
| B | VPN 开启，AGH 劫持摘除 | App DNS → TUN → mihomo → AGH:5591 → GeoIP |

轨道 B 的过滤效果依赖 **DNS 集成**。若活动 profile 没有指向
`127.0.0.1:5591`，模块会把集成状态显示为“未打补丁”，不会把它误报为已开启。

## 安装

### 前置条件

- KernelSU 环境，支持模块与 WebUI；本项目已在 KernelSU 3.3.1 late-load 上验证。
- 已安装并启动 AdGuard Home，默认监听 `127.0.0.1:5591`。
- 使用 DNS 集成时，需要 Clash Meta 包名
  `com.github.metacubex.clash.meta` 及可读的活动 profile。
- 首次安装前准备可用的模块禁用/安全模式方式，并保留当前网络配置快照。

不同 KernelSU 版本的支持范围请以
[KernelSU 模块文档](https://kernelsu.org/zh_CN/guide/module.html) 为准。

### 刷入

1. 从 [Releases](https://github.com/deancyl/rmg-netguard/releases/latest) 下载
   `rmg-netguard-v2.2.1.zip`。
2. 在 KernelSU 管理器中安装 zip。
3. 让模块在下一轮启动中加载，或在 late-load 会话里手动启动一次：

```sh
su -c 'sh /data/adb/modules/rmg_netguard/service.sh'
```

4. 打开模块 WebUI，先保持“只看不动”，确认状态、AGH 与轨道信息正常。
5. 需要自动切换时再打开“自动切换”；需要轨道 B 过滤时再打开“DNS 集成”。

升级时直接刷入新 zip。升级会保留 `run/mode`、`run/integration`、事件日志和
DNS 集成备份；卸载会停止 guard、还原模块持有的 profile 备份，并在必要时恢复
AGH 劫持。

## WebUI

- **顶部状态条**：状态、模式、轨道、AGH、探针和快照年龄始终可见。
- **只看不动 / 自动切换**：切换前显示面板内确认条，不调用阻塞式原生对话框。
- **DNS 集成**：以活动 profile 的实际补丁状态为准，可直接开启或还原。
- **刷新状态**：执行完整状态采集，包含 DNS 过滤探针。
- **一键体检 / 规则审计 / 拦截统计 / 事件日志**：结果立即显示在顶部结果区，
  完整文本位于“详细输出”。
- **每 30 秒自动刷新**：默认开启；后台状态采样周期仍由 guard 的 90 秒间隔决定，
  页面右上角显示的是最近一次后台快照的时间。

操作进行中会锁定动作按钮并显示秒数。重复点击会得到明确提示；命令超过 90 秒
未返回时自动解除锁定。失败时界面显示红色错误，不再把非零退出码或无输出当作成功。

## 安全边界

1. 自动切换只摘取或插入 `nat OUTPUT` 上的一条
   `OUTPUT -> ADGUARD_REDIRECT_DNS` 跳转，不修改链体。
2. AGH 不存活或不响应 5591 时，任何方向的自动切换都会被拒绝。
3. DNS 集成只处理当前活动的 Clash Meta profile；首份备份不会被覆盖，备份自身
   含 `NS5591` 时拒绝还原。
4. `observe` 模式不主动改写网络规则；无 AGH / Clash 时进入 300 秒退避空载。
5. 所有改动均可通过 WebUI、模块卸载或安全模式回退。不要把未经验证的生产设备
   当作测试机。

## 状态与诊断

| 状态 | 含义 | 建议 |
|---|---|---|
| `NORMAL` | 观测到的进程、端口和拓扑一致 | 继续观察 |
| `RISK_COEXIST` | VPN 与 DNS 劫持同时存在，形成串联拓扑 | 可工作，但建议评估是否切到 `auto` |
| `INCONSISTENT` | AGH 进程存在，但劫持规则缺失 | 检查 AGH 模块与 netfilter |
| `DOWN_PORT` | 劫持存在，但 5591 未监听 | 优先恢复分辨率，避免 DNS 黑洞 |

过滤探针显示 `BLOCKED / UNKNOWN` 时只表示两个测试域名结果不一致，可能是域名
策略或单域名超时，不能单独据此判定 AGH 整体故障。querylog 长时间没有新记录也
可能只是设备无 DNS 流量。

## 构建与验证

```sh
python build_zip.py
python verify_zip.py
```

WebUI 回归测试：

```sh
npm install
npx playwright install chromium
npm run test:webui
```

测试使用真实 Chromium、设备 CSS 视口和 KernelSU `exec(cmd, "{}", callback)`
桥接桩，覆盖首屏轻量刷新、自动刷新、点击反馈、确认流程、失败状态、实时模式、
布局和 JavaScript 异常。

## 配置与文件

| 路径 | 用途 |
|---|---|
| `/data/adb/modules/rmg_netguard/run/mode` | `observe` / `auto` |
| `/data/adb/modules/rmg_netguard/run/integration` | DNS 集成标志 |
| `/data/adb/modules/rmg_netguard/run/state.json` | 最近一次 guard 快照 |
| `/data/adb/modules/rmg_netguard/run/events.log` | 状态与动作事件 |
| `/data/adb/modules/rmg_netguard/run/backups/` | Clash Meta profile 原始备份 |
| `/data/adb/modules/rmg_netguard/run/config` | 可选的 guard 参数覆盖 |

## 文档

- [Wiki 首页](https://github.com/deancyl/rmg-netguard/wiki)
- [安装与升级](https://github.com/deancyl/rmg-netguard/wiki/安装与升级)
- [WebUI 使用](https://github.com/deancyl/rmg-netguard/wiki/WebUI-使用)
- [架构与工作模式](https://github.com/deancyl/rmg-netguard/wiki/架构与工作模式)
- [故障排查与恢复](https://github.com/deancyl/rmg-netguard/wiki/故障排查与恢复)
- [开发与验证](https://github.com/deancyl/rmg-netguard/wiki/开发与验证)
- [完整变更记录](CHANGELOG.md)

## 项目结构

```text
module/
  module.prop          KernelSU 模块元数据
  service.sh           late-load 服务入口
  scripts/
    guard.sh           观测与自动切换循环
    controller.sh      健康门控的 attach / detach
    config_toggle.sh   Clash Meta profile 集成
    webui.sh           WebUI 命令分发
  webroot/index.html   KernelSU WebUI
tests/webui/           Chromium 交互回归测试
build_zip.py           构建模块 zip
verify_zip.py          校验 zip 与源码一致
```

## 已知限制

- `nameserver-policy geosite:cn -> [system]` 等 profile 策略会让部分国内域名绕过
  AGH；这是订阅配置层面的行为，改动前需要评估规则命中范围。
- CMFA `override.json` 可能被 profile 自身的 `dns:` 段压制，因此集成直接处理活动
  profile，并依赖备份和漂移检测保证可逆。
- 本项目不是 AdGuard Home 或 Clash Meta 的替代品，也不负责修复第三方模块自身
  的进程、pidfile 或端口问题。

## 版本

当前版本：`v2.2.1`（`versionCode=23`）。版本号使用 SemVer；发布 zip 应与
Git tag、`module.prop` 和 Release 标题保持一致。

作者：`deanc` · 项目地址：
[deancyl/rmg-netguard](https://github.com/deancyl/rmg-netguard)
