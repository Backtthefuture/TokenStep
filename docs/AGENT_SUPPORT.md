# TokenStep Agent 支持策略

TokenStep 的原则是：能从本地日志中稳定读到 token 数，才进入正式统计。不能稳定验证的 Agent 先放在候选区，不用猜测数据污染用户的总量。

## 当前正式支持

| Agent | 状态 | 数据来源 | 说明 |
| --- | --- | --- | --- |
| Codex | 已支持 | `~/.codex/sessions` / `~/.codex/archived_sessions`，必要时回退 SQLite | 读取本地 token_count 事件，只统计数量；可选读取 5h / 7d 额度。 |
| Claude Code | 已支持 | `~/.claude/projects` | 读取 assistant message 的 usage 字段，按 `message.id` 去重，避免 thinking / text / tool_use 多行重复累计；可选通过 Claude Code 本机钥匙串凭证读取 usage 额度。 |
| Kimi Code | 已支持 | `~/Library/Application Support/kimi-desktop/daimon-share/daimon/runtime/kimi-code/home/sessions/**/agents/main/wire.jsonl` | 读取 `usage.record` 事件，字段映射为 `inputOther`/`output`/`inputCacheRead`/`inputCacheCreation`。 |
| ZCode / GLM | 已支持 | `~/.zcode/cli/db/db.sqlite` → `model_usage` | 只读 SQLite `model_usage` 表的 token 数值列，不读 `message`/`part` 正文。 |
| Pi / SPI | 已支持 | `~/.pi/agent/sessions/**/*.jsonl` | 读取 `message` 事件中 assistant 角色的 `usage` 字段。 |
| Reasonix / DeepSeek | 已支持 | `~/.reasonix/sessions/*.events.jsonl` / `~/.reasonix/projects/**/*.events.jsonl` | 读取 `model.final` 事件的 `usage` 字段，并与 `model.turn.started` 关联模型名。 |

## 实验支持：CC Switch Proxy

TokenStep 对 CC Switch 的支持定位为实验性的高级统计来源，source 名称为 `CC Switch Proxy`。它用于识别 Claude Code / Codex / Gemini 等客户端通过 CC Switch 或类似第三方模型路由工具发起真实代理请求时的 token、上游计费模型和成本。

默认主统计仍以 Codex 与 Claude Code 的本地原生日志为准。CC Switch Proxy 不会把数据写回原生 `Codex` / `Claude Code` 口径，而是使用独立客户端名：

- `claude` -> `Claude Code via CC Switch`
- `codex` -> `Codex via CC Switch`
- `gemini` -> `Gemini via CC Switch`
- 其他 `app_type` 会保留原值并追加 experimental 标记

当前 MVP 只读 `~/.cc-switch/cc-switch.db` 的 `proxy_request_logs` 表，并且只统计：

- `status_code >= 200 and status_code < 300`
- `data_source` 为空或等于 `proxy`（老库没有该列时按 proxy 处理）
- `input_tokens + output_tokens + cache_read_tokens + cache_creation_tokens > 0`

Token 总量口径为 `input_tokens + output_tokens + cache_read_tokens + cache_creation_tokens`。模型显示优先使用 `pricing_model`，其次是 `model`、`request_model`，都为空时显示 `unknown`。成本使用 CC Switch 写入的 `total_cost_usd`。

CC Switch 的 `data_source` 在真实库里可能是 `codex_session`、`opencode_session`、`session_log` 等值。这些通常是 CC Switch 从本地会话日志二次导入的统计，容易和 TokenStep 已有 Codex / Claude Code 原生日志重复，所以 TokenStep 不把它们计入 `CC Switch Proxy`。`usage_daily_rollups` 不是 MVP 主数据源，后续如果要支持历史 rollup，必须先确认去重策略和来源边界。

TokenStep 只使用 SQLite 只读访问，不修改 CC Switch 配置，不开启代理接管。只有用户在 CC Switch 中开启 local routing 并实际产生代理请求后，`proxy_request_logs` 才会出现有效请求行；如果数据库存在但没有成功且 token 数大于 0 的请求行，source status 会显示为 `missing_valid_rows`。

## 已参考的项目

### CodeIsland

参考点：

- 灵动岛常驻窗口使用 non-activating panel，避免打断当前工作流。
- 展开层应该轻量，适合鼠标移入快速看一眼，不适合塞完整浮层。
- 刘海屏与非刘海屏要有降级策略，不能强依赖某一种屏幕结构。

TokenStep 采用：

- 菜单栏 / Token Island 二选一。
- Token Island 保持单圈、少占宽度。
- 鼠标移入后展开轻量 Island 面板，而不是完整仪表盘。

### cc-switch

参考点：

- 对 Claude Code 一类工具，代理层可以看到更完整的请求上下文。
- 对 OpenAI 兼容接口，流式返回如果没有打开 `stream_options.include_usage`，usage 可能缺失。

TokenStep 不主动接管代理：

- 当前定位是 local-first、低打扰、不开代理。
- CC Switch Proxy 只作为实验数据来源读取真实代理请求元数据，必须单独和原生统计区分。

### TokenTracker

参考点：

- Codex 额度可以从 ChatGPT 使用量接口中识别 5h / 7d 两类窗口。
- Claude Code 额度可参考 Anthropic OAuth usage 接口，但需要用户本机有可用 OAuth 信息。
- Roo / Kilo / Cline 这类 VS Code 扩展通常会把任务记录写到 `globalStorage` 下的 `ui_messages.json`。

TokenStep 采用：

- Codex 额度窗口按 duration 明确区分 5 小时和 7 天。
- Claude Code 额度在设置打开后，尝试读取本机 Keychain 里的 `Claude Code-credentials`，并调用 Anthropic OAuth usage 接口。
- VS Code 扩展类 Agent 先列为候选支持，等有真实本机样本后再接入。

## 候选支持

| Agent | 可行性 | 下一步 |
| --- | --- | --- |
| Roo Code | 较高 | 需要真实 `ui_messages.json` 样本确认字段。 |
| Cline | 较高 | 需要真实任务目录样本确认模型和 usage 字段。 |
| Kilo Code | 较高 | 可按 `api_req_started` 事件读取 token，但需要本机样本验证。 |
| CodeBuddy | 中 | 本机看到 VS Code secret buffer 和产品缓存，但不是明文 usage；需要官方 usage 文件或可验证字段。 |
| Cursor / Windsurf / Trae | 中 | 需要确认是否本地暴露 token usage，不应只按聊天字数估算。 |
| Hermes Agent | 待确认 | 本机日志存在 `tokens=~` 估算和压缩/错误记录，暂不进入正式总量。需要真实 API usage 或统一事件。 |
| WorkBuddy | 待确认 | 本机未找到稳定 token usage 日志；需要产品侧提供本地统计文件或事件。 |

## 接入规则

1. 优先读官方或工具本地写出的 usage 字段。
2. 不读取 prompt、代码、回复正文。
3. 不用“字数估算 token”作为默认统计口径。
4. 新 Agent 默认先进入实验区，至少用 2-3 台真实机器样本验证后再进入正式统计。
5. UI 上只展示有数据的 Agent，避免空状态造成误解。
