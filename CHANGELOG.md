# Changelog

本项目使用语义化版本。发布记录以 GitHub Releases 为准；标注「主线提交」的版本已合入 `main` 并部署到验证设备，但未创建 Release tag。

## v2.3.0 - 2026-11-10（主线提交）

### 修复：代理节点流量异常增加（取证确认的三条根因）

**根因 1：AGH upstream 1.12.12.12 进入 tun0 走代理节点**
- AGH 的 `upstream_dns` 包含 `https://1.12.12.12/dns-query`；1.12.12.12 作为
  APNIC Anycast 地址进入 tun0 后，在 Fake-IP 轨道 B 下 cn-ip 规则带 `no-resolve`
  跳过，又无 `GEOIP,CN,DIRECT` 兜底，全部落入 `MATCH,proxy` 走代理节点。
  从设备端日志实证：AGH bin.log 大量 `1.12.12.12:443 timeout/EOF`，tun0 RX 达 944 MB。
- 修复：在设备端 `/data/adb/agh/bin/AdGuardHome.yaml` 中将 `upstream_dns` 移除
  `1.12.12.12`，统一使用纯 IP 格式国内 DoH（`223.5.5.5`、`223.6.6.6`）。

**根因 2：config_toggle apply 从未成功执行，DNS 集成名义 on 但内存无效**
- 取证实证：`status = unpatched backup=no drifted=no`，说明 NS5591 从未写入，
  marker 也不存在，do_auto 看门狗故意跳过（v2.2.5 的防风暴保护机制）。
- `patch_nameserver` 仅修改磁盘文件，CMFA 在 VPN 存活期间不会自动重载，
  导致即便磁盘已打补丁，mihomo 内存中依然跑原始配置。

**根因 3：GEOIP,CN,DIRECT 缺失导致 Fake-IP 轨道 B 国内流量落入 MATCH**
- 轨道 B（hijack=0）下 App 拿到 Fake-IP（198.18.x.x），cn-ip 规则带 `no-resolve`
  对 Fake-IP 直接跳过，若无不带 `no-resolve` 的 `GEOIP,CN,DIRECT`，所有未命中
  域名规则的国内流量 100% 落入 MATCH+proxy。

### 功能变更

- **`config_toggle.sh`（v2.3.0）**：
  - `do_apply` 新增 `patch_geoip_rule()`：在 `- MATCH` 前注入
    `- GEOIP,CN,DIRECT`（幂等，已存在时跳过），防止 Fake-IP 在轨道 B 下泄漏到代理。
  - `do_apply`、`do_revert`、`do_auto` 完成写盘后调用 `broadcast_reload()`，
    向 CMFA 发送 `ACTION_PROFILE_CHANGED` 广播，触发 mihomo 内存热重载，
    消除「磁盘已打补丁但内存仍跑旧配置」的盲区。
  - `do_auto` 增加内容漂移再打逻辑：订阅更新后 marker MD5 变化（即便 NS 仍在）
    也触发 `do_apply` 以恢复 GEOIP 规则并刷新 marker。
  - `do_status` 新增 `geoip: yes/no` 字段。
- **`env.sh`（v2.3.0）**：
  - PATH 预插 `/data/adb/ksu/bin`（KernelSU busybox，存在时才加）。
  - `dns_latency_ms` 改用 `--head` 只发 HEAD 请求，避免拉取页面正文穿透 tun0。
- **`customize.sh`（v2.3.0）**：
  - 版本号从 `module.prop` 动态读取，消除硬编码 `v2.2.1` 残留。
  - 安装时检测旧 `run/` 目录，自动迁移 mode/integration/events.log/config/backups
    到新模块路径，升级不再丢失用户设置与历史数据。
- **`tests/test_config_toggle.sh`（v2.3.0）**：
  - 新增：GEOIP 注入断言（inline/block 两形态）、幂等性断言、订阅漂移后 do_auto
    恢复 GEOIP 的场景、`status` 包含 `geoip:` 字段断言。

## v2.2.5 - 2026-11-06

### 修复（零网络干预，隔离回归 24/24 通过）

- `config_toggle.sh` 支持**块列表格式**的 `nameserver:`（此前只认行内数组，遇到
  `nameserver:` + `- item` 的 profile 会永久 `FAIL: ambiguous nameserver lines (0)`，
  即 10-28 那 27 次补丁风暴的根因）；新增 awk 生成器，同时保留行内数组支持，
  并用截断重写保留 uid/SELinux context。
- 集成看门狗改为「只重打本模块曾经打过、后被覆盖的补丁」（marker 存在才动作）：
  不再见到 unpatched 就重打，避免覆盖用户手工配置的国内 DoH、也杜绝空转风暴。
- `rules_audit.sh` 修正误报：`RULE-SET,cn` / `cn-ip` / `GEOSITE,CN` 属等价的
  域名层直连覆盖，输出 INFO 而非 WARN；仍建议补 `GEOIP,CN,DIRECT` 作为 IP 兜底。
- 新增 `tests/test_config_toggle.sh`（隔离目录，覆盖两种 YAML 形态、备份/还原、
  看门狗两类场景与审计判据）；`verify_consistency.py` 增加对应源码断言。

## v2.2.4 - 2026-11-05

### 文档与 WebUI 说明一致性（零守护逻辑改动）

- 修正安全边界的反向陈述：「AGH 不应答时任何切换都会被拒绝」改为 `attach` 需健康门、`detach` 为 fail-open 救援方向（AGH 不健康时仍执行并记 RESCUE）。UI、README、Wiki 全部同步。
- 修正「只看不动 = 零干预」的过度承诺：明确 DNS 集成的备份/漂移重打/还原独立于模式，采样本身会产生少量测试流量。
- 状态机说明补充 v2.2.3 的例外：`auto` 模式或存在 rescue 标志时，AGH 存活 + 劫持摘除判为 `NORMAL`（轨道 B），不再误报「不一致」。
- 补齐使用流程断点：开启/关闭 DNS 集成均需重开一次 VPN 生效；自动切换需连续 2 轮（约 3 分钟）且切换本身不立即改变拓扑；动作结果带增加后续预期提示。
- 区分「AGH 未运行」（探针 SKIP）与「AGH/Clash 均未安装」（300 秒退避空载）；后台采样周期说明补充空载例外。
- WebUI 版本号改为由 `webui.sh` 读取 `module.prop` 动态注入；`build_zip.py` / `verify_zip.py` 共用同一版本源；新增 `verify_consistency.py` 与 CI 断言，防止文档与代码再次漂移。
- 事件日志按钮扩展到最近 50 条；危险动作与只读诊断分组标注；探针/日志年龄徽章增加就地解释。

## v2.2.3 - 2026-10-29（主线提交，未打 tag）

- 状态分类器把 `auto` 模式 / rescue 标志下的轨道 B 判为 `NORMAL`，修复用户实际看到的「不一致」误报；`probe.sh` 同步输出轨道 B 说明。

## v2.2.2 - 2026-10-29（主线提交，未打 tag）

- `controller.sh` 的 detach 改为 fail-open：AGH 死亡/不应答时不再被健康门阻断 DNS 黑洞自救；attach 仍严格门控。WebUI 确认文案与底部边界同步。

## v2.2.1 - 2026-10-24

### 修复

- WebUI 启动时真正启用“每 30 秒自动刷新”；此前复选框默认勾选，但定时器未初始化。
- `webui.sh` 在体检、审计、统计、日志、模式切换、DNS 集成和劫持切换后正确传播
  退出码；界面不再把失败显示为成功。
- 模式显示统一采用 controller 的实时 `mode=`，避免切换后头部状态与详情卡相互矛盾。
- 首次打开时过滤探针显示“未检测”，不再使用容易误解的 `--`。
- `BLOCKED + UNKNOWN` 探针组合改为“双探针结果不一致”，移除未经证实的
  “AGH 退化，建议重启”结论。
- querylog 年龄不再单独触发黄色告警；无新查询不能直接判定 AGH 故障。

### 文档与发布

- README 重写为安装、使用、安全边界和开发入口。
- 新增 GitHub Wiki：安装升级、WebUI、架构、故障恢复、开发验证。
- 新增项目简介、仓库主题、自动发布流程和 WebUI Chromium 回归测试。
- 版本统一提升至 `v2.2.1`，`versionCode=23`。

## v2.2.0 - 2026-10-16

### WebUI 交互重做

- 新增轻量 `status_fast`，首屏跳过最慢的 DNS 探针，避免打开面板即占用全局操作锁。
- 新增 sticky 顶部状态条、快照年龄、就近结果反馈和面板内确认。
- 移除阻塞式 `window.confirm`；忙碌点击不再静默丢弃。
- 集成状态以活动 profile 是否实际含 `NS5591` 为准，标志文件仅作兜底。
- 构建脚本排除编辑器备份和点文件。

## v2.1.0 - 2026-10-15

### 性能与无依赖降级

- 过滤探针并行执行，DNS 延迟改为并发采样，端口探测与 querylog 统计减少遍历。
- WebUI 增加单飞任务锁、按钮忙碌态、进度提示和 90 秒看门狗。
- AGH / Clash 缺失时即时 SKIP 并进入纯观测空载，guard 使用 300 秒退避。
- 修复 toybox `flock -w` 不兼容、部分脚本无条件 `exit 0` 和硬编码路径问题。
- 空载模式不产生 netfilter 规则，实测 guard CPU 为零 ticks。

## v2.0.0 - 2026-10-15

### 双轨架构

- 引入 VPN 关闭 / 开启时的 DNS 双轨拓扑。
- 新增 `observe` 与 `auto` 模式，以及 VPN 滞留防抖和健康门控切换。
- 新增 Clash Meta 活动 profile 的 DNS 集成、原始备份、漂移检测和自动重打。
- 新增过滤探针、活动客户端识别、querylog 统计和规则审计。
- 卸载时自动还原 profile 补丁与模块摘除的 AGH 劫持。

## v1.0.1 - 2026-10-15

### 稳定性

- DNS 延迟探测降频，告警只使用新鲜样本。
- kill 旧 guard 前校验 PID 对应 cmdline，避免 PID 复用误杀。
- `run/config` 增加白名单校验，拒绝非赋值语句。
- 状态迁移时立即执行一次规则审计。

## v1.0.0 - 2026-10-15

- 首个 KernelSU DNS / VPN 观测守护版本。
