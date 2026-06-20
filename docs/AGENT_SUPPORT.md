# TokenStep Agent 支持策略

TokenStep 的原则是：能从本地日志中稳定读到 token 数，才进入正式统计。不能稳定验证的 Agent 先放在候选区，不用猜测数据污染用户的总量。

## 当前正式支持

| Agent | 状态 | 数据来源 | 说明 |
| --- | --- | --- | --- |
| Codex | 已支持 | `~/.codex/sessions` / `~/.codex/archived_sessions`，必要时回退 SQLite | 读取本地 token_count 事件，只统计数量。 |
| Claude Code | 已支持 | `~/.claude/projects` | 读取 assistant message 的 usage 字段，只统计数量。 |

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

TokenStep 暂不采用代理方案：

- 当前定位是 local-first、低打扰、不开代理。
- 后续如果做“高级统计模式”，可以考虑可选代理，但必须单独授权。

### TokenTracker

参考点：

- Codex 额度可以从 ChatGPT 使用量接口中识别 5h / 7d 两类窗口。
- Claude Code 额度可参考 Anthropic OAuth usage 接口，但需要用户本机有可用 OAuth 信息。
- Roo / Kilo / Cline 这类 VS Code 扩展通常会把任务记录写到 `globalStorage` 下的 `ui_messages.json`。

TokenStep 采用：

- Codex 额度窗口按 duration 明确区分 5 小时和 7 天。
- VS Code 扩展类 Agent 先列为候选支持，等有真实本机样本后再接入。

## 候选支持

| Agent | 可行性 | 下一步 |
| --- | --- | --- |
| Roo Code | 较高 | 需要真实 `ui_messages.json` 样本确认字段。 |
| Cline | 较高 | 需要真实任务目录样本确认模型和 usage 字段。 |
| Kilo Code | 较高 | 可按 `api_req_started` 事件读取 token，但需要本机样本验证。 |
| CodeBuddy | 中 | 如果完全复用 Claude Code 日志结构，可以作为 Claude Code 变体接入。 |
| Cursor / Windsurf / Trae | 中 | 需要确认是否本地暴露 token usage，不应只按聊天字数估算。 |
| Hermes Agent / WorkBuddy | 待确认 | 当前未找到稳定 token 日志路径，需要产品侧提供本地统计文件或事件。 |

## 接入规则

1. 优先读官方或工具本地写出的 usage 字段。
2. 不读取 prompt、代码、回复正文。
3. 不用“字数估算 token”作为默认统计口径。
4. 新 Agent 默认先进入实验区，至少用 2-3 台真实机器样本验证后再进入正式统计。
5. UI 上只展示有数据的 Agent，避免空状态造成误解。

