# 自定义供应商空账号的原生 Fast 修复

本 fork 修复 Codex++ 1.11.1 在纯自定义供应商模式下的 Fast 按钮缺失。
使用 `experimental_bearer_token` 等认证配置时，Codex 可以正常请求模型，
但其 UI 的 `authMethod` 和 `account/read` 的 `account` 可以为 null。
原补丁只接受 `apikey` / `apiKey`，因此已经声明 priority 的模型仍没有速度选项。

## 行为

- 注入时从本机 Codex 配置识别活动供应商（含选中的 profile）。
- 仅为有合法 HTTP(S) base_url、非 openai、且不要求官方认证的自定义供应商增加空账号放行。
- 只向 renderer 传入一个布尔值，不传接口地址、API Key 或 token。
- UI、直接请求读取、默认队列、显式队列共用放行条件；旧版队列仍只读取一次账号。
- 仍要求本地主机、增强总开关及原生 Fast 开关，保留模型档位和 requirements 限制、Standard 和 Copilot 行为。
- 供应商配置的识别在注入时执行；修改供应商后应通过 Codex++ 重新启动 Codex。

## 本地验证

在 Windows、Codex 26.1016.8622.0 上验证：

- Fast 相关 Rust/JS 测试通过（8 项通过，1 项既有 Chromium 测试按默认标记忽略）。
- 原生速度选项从空列表恢复为 Standard / Fast，Fast 对应 priority。
- 使用本机真实 Codex app-server、隔离配置和本地 HTTP 接收端验证，
  `turn/start` 的 `serviceTier: "priority"` 生成了以下实际 HTTP 请求字段：

```json
{"method":"POST","path":"/v1/responses","model":"gpt-6-astra","service_tier":"priority"}
```

此验证确认客户端实际序列化并发送参数，不代表上游是否兑现优先调度或其计费行为。

## Windows 自编译

```powershell
cd apps/codex-plus-manager
npm install --package-lock=false --no-audit --no-fund
npm run vite:build
cd ../..
cargo test --release -p codex-plus-core native_fast --lib --test native_fast_unlock --locked
cargo build --release -p codex-plus-manager --bin codex-plus-plus --locked
```

主程序是 `target/release/codex-plus-plus.exe`。退出旧 Codex++ 后运行新程序，
配置仍沿用本机原目录。官方 Codex 安装包不需要改动。

本 fork 的更新检查与下载使用 `zmsvovo/CodexPlusPlus` 的 Release，
入口为 `https://github.com/zmsvovo/CodexPlusPlus/releases/latest/download/latest.json`，
不会回退到上游安装包。关于页的项目链接也指向本 fork。

后续更新流程：合并上游并保留本地修复，推送提交，为该提交创建新的 fork 标签，
运行 Release assets 工作流（platform=windows、draft=true、publish=true）。
安装包、ZIP 和 latest.json 齐备后才公开发布；本 fork 不构建需要上游 Apple 凭据的 macOS 包。
仅推送代码不会产生客户端更新；必须完成 Release 发布。
版本比较仍沿用上游的数字版本规则，`-fork.1` 等标签后缀不参与比较，
同一上游版本的补发不会触发升级提示，下一次更高数字版本的 Release 才会提示更新。

首次从旧构建迁移需要手动运行本 fork 的新版 EXE；旧 EXE 内置的上游地址不会自动改变。
手动安装上游官方包仍会覆盖修复和更新来源。
不要直接把 GitHub 的“丢弃本地提交”同步操作用于本 fork。
