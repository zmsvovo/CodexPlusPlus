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

安装上游官方 Codex++ 更新会替换本地修复版 EXE；在上游合入等价修复前，
请从本 fork 合并更新并重新编译。不要直接把 GitHub 的“丢弃本地提交”同步操作用于本 fork。
