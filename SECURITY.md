# Security Policy

## Supported version

安全修复面向最新发布版本。旧版本可以继续使用，但不会获得针对性安全更新。

## Reporting

不要在公开 Issue 中提交以下内容：

- 设备序列号、账号、IP 地址或订阅链接；
- Clash profile、AGH 配置或备份文件；
- 可直接绕过健康门控的利用代码；
- 未脱敏的 `events.log`、`state.json` 或系统日志。

请通过 GitHub Security Advisory 私下报告漏洞，并附上受影响版本、复现条件、
预期行为、实际行为和最小化脱敏日志。

## Production safety

维护者不会在未确认的设备上执行重启、分区写入、模块批量迁移或破坏性网络测试。
涉及 `iptables`、profile 改写和卸载恢复的改动必须提供可回滚路径、静态检查结果
以及至少一轮交互或隔离环境验证。
