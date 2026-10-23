# Contributing

## Before changing device state

- 优先使用隔离目录、模拟环境和只读诊断。
- 任何会修改 `iptables`、Clash Meta profile、模块安装或设备重启的步骤都必须
  单独说明风险和回滚方式。
- 不要提交设备序列号、token、订阅地址、用户配置或未脱敏日志。

## Local checks

```sh
python build_zip.py
python verify_zip.py
npm install
npm run test:webui
```

提交前同时检查：

- shell 文件保持 LF 和 UTF-8，不含 BOM；
- `module.prop` 的 `version`、UI 版本、构建 zip 名和 tag 一致；
- 失败路径返回非零退出码，WebUI 显示红色结果；
- 不引入阻塞式 `confirm` / `alert`，不静默丢弃忙碌期间的点击；
- 不把 `*.bak`、编辑器临时文件或测试产物打进模块 zip。

## Pull requests

PR 描述应包含问题根因、行为变化、测试方式、设备侧影响和回滚步骤。只改变文档时
可不提供设备测试，但必须说明未执行真机验证。
