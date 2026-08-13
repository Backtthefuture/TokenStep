# Agent 数据源档案（G-A1 T1）

> 纪律（AGENT_SUPPORT）：只读 usage 字段；不读正文/代码/凭据；默认关闭；逐源开关；
> 解析失败只影响该源。真实机器核验状态见 goal-runs/G-A1。

| 源（source 名） | 数据位置 | 格式 | 口径要点 | 验证状态 |
|---|---|---|---|---|
| Gemini CLI | `~/.gemini/tmp/<hash>/chats/session-*.{json,jsonl}` | 单文档 JSON（messages[].tokens{input,output,cached,thoughts,tool,total}）/ JSONL usageMetadata | input 含 cached（减法口径）；total 显式优先；按 msg id 去重 | **本机真实样本核验**（2 记录/16,276 tokens） |
| Qwen Code | `~/.qwen/tmp/`、`~/.qwen/projects/` | usageMetadata（Gemini 分叉） | 同 Gemini | 公开 schema（本机无数据）；待真机 |
| Kimi Code | `~/.kimi-code/sessions/**/wire.jsonl` 的 `usage.record` 事件 | message.type≈UsageRecord | input 不含 cached；cwd→项目名；旧版 `~/.kimi` 无 usage 事件不扫 | 公开 schema；旧版行为本机核验（如实无数据） |
| OpenCode | `~/.local/share/opencode/opencode.db` | SQLite `message.data` JSON：tokens{input,output,reasoning,cache.read/write}+modelID+path | sqlite3 -readonly json_extract；path→项目名 | **本机真实样本核验**（3056 记录/247,106,022 tokens） |
| Amp | `~/.local/share/amp/threads/**/*.jsonl` | 通用 usage 行提取 | input/output/cached 宽容键名 | 公开 schema（本机无数据） |
| Droid | `~/.factory/sessions/**/*.jsonl` | 通用 usage 行提取 | 同上 | 公开 schema（本机无数据） |
| Grok Build | `~/.grok/sessions/<URL-encoded-cwd>/<sid>/updates.jsonl` | `_x.ai/session/update` → `turn_completed.usage{inputTokens,outputTokens,cachedReadTokens,reasoningTokens,modelUsage}` | input 含 cached；prompt_id 去重；目录名解码→项目名 | **本机真实样本核验**（132 记录/87,885,053 tokens） |

状态词：`ok` / `missing`（目录不存在）/ `missing_db` / `missing_valid_rows`（有文件无 usage 行）。
