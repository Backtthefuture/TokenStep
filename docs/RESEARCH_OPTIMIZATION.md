# TokenStep 全网对标调研与优化方案

> 调研时间：2026-08-13
> 调研方式：GitHub 源码级调研（ccusage v17/v19/v20、vibe-usage 生态、TokenBar、codeburn、Maciek Monitor 等 30+ 仓库）
> 基线：TokenStep v0.1.48（main = ef13871）
> 关联文档：[PRD_TOKENSTEP_OPTIMIZATION.md](PRD_TOKENSTEP_OPTIMIZATION.md)（本轮不做清单见其 §0.5）

---

## 一、调研仓库全景

### 1.1 品类基准（大盘项目）

| 仓库 | Stars | 技术栈 | 对 TokenStep 的意义 |
|---|---|---|---|
| [ccusage/ccusage](https://github.com/ccusage/ccusage) | 17.9k | TS→Rust（v20 全面重写） | 品类事实标准；解析/去重/定价/blocks 算法源头 |
| [winfunc/opcode](https://github.com/winfunc/opcode)（原 claudia） | 22.4k | TS + Tauri | Claude Code 全功能 GUI，含 Usage Dashboard |
| [Maciek-roboblog/Claude-Code-Usage-Monitor](https://github.com/Maciek-roboblog/Claude-Code-Usage-Monitor) | 8.6k | Python | 5h 块预测标杆；Provenance 置信度分级首创 |
| [codeburn](https://github.com/…) | 9.3k | Node CLI | 40 工具解析、指纹缓存文档极佳 |
| [abtop](https://github.com/…) | 3.4k | TUI | htop 式实时监控 |

### 1.2 vibe-usage 生态（用户点名）

| 仓库 | Stars | 技术栈 | 要点 |
|---|---|---|---|
| [vibe-cafe/vibe-usage](https://github.com/vibe-cafe/vibe-usage) | 98 | Node CLI | 30+ 工具解析器之最；Codex 归档双扫 + per-rollout 增量缓存；30min 桶聚合 |
| [vibe-cafe/vibe-usage-app](https://github.com/vibe-cafe/vibe-usage-app) | 123 | **SwiftUI 菜单栏（最直接对标）** | CodexRateLimitReader（JSONL 读限额零网络）；Claude 子进程探针（keychain ACL 踩坑记录）；XCTest 全覆盖 |
| watkinsye/vibe-usage | 3 | SwiftUI + Go | 52 周热力图、per-branch 下钻、Cost⇄Tokens 切换 |
| cross-entropy-ai/vibe-usage | 3 | Rust 单二进制 | 本地 web dashboard |

### 1.3 macOS 菜单栏 Swift 同类（直接竞品）

| 仓库 | Stars | 亮点 |
|---|---|---|
| [tddworks/ClaudeBar](https://github.com/tddworks/ClaudeBar) | 1.4k | 15 家供应商探针聚合；阈值色（50%/20% 分档）；系统通知 |
| [AThevon/TokenEater](https://github.com/AThevon/TokenEater) | 462 | 连续风险评分（用量+投影+pacing 合成，早期窗口置信度阻尼）；WidgetKit；Agent Watchers（活跃会话浮窗+跳转终端）；分面×分事件通知 |
| [Nihondo/AgentLimits](https://github.com/Nihondo/AgentLimits) | 53 | 通知中心小组件；内部 API 端点情报（wham/usage 等） |
| TokenBar | 256 | Swift+Rust FFI；OAuth quota 全端点实现；tokens/min 实时；pace 预测 |
| ClaudeMeter / claude-codex-battery / usage-menubar | 17~132 | 电池图标、双值菜单栏、倒计时 |
| kenn-io/vibepulse | 52 | "若无订阅按 token 计价你会付多少" 成本视角 |

### 1.4 多源聚合 CLI

better-ccusage（76★，七源+多供应商定价）、opencode-stats（55★，365 天热力图）、par_cc_usage（84★）、ccNexus（980★，网关计量）、douglasmonsky/codex-usage-tracker（191★，MCP+SQLite 内核）。

---

## 二、TokenStep 现状对标结论

### 2.1 已领先业界的部分（保持）

| TokenStep 现状 | 业界对照 |
|---|---|
| Codex 逐会话增量 SQLite 缓存 + 异常重建 + rewritten timestamps 处理 | ccusage 每次全量解析（无状态）；vibe-usage 有等价 codex-cache 但在 Node 层。TokenStep 领先 |
| CC Switch proxy 数据源 + 跨源去重（原生记录 vs proxy 记录） | **全网唯一**，调研范围内无任何项目支持 cc-switch |
| collection checkpoint（源状态指纹未变则跳过采集）+ 能耗策略（接电 15min/电池 30min 下限） | 领先；同类多为固定间隔轮询 |
| usage.json 历史快照仓库 | Claude 本地日志只保留约 30 天（Maciek 项目证实）；TokenStep 快照天然是对抗清理的长期 warehouse，ccusage 无此能力 |
| 去重 key：response/request/uuid/line 多级 fallback | 与 ccusage `messageId:requestId` 方案等价 |
| archived_sessions 双目录联合处理 | 与 vibe-usage 的归档坑处理一致 |

### 2.2 核实过的差距

1. **Claude 路径只扫 `~/.claude/projects`**（UsageCollector.swift:121），不支持 XDG 路径 `~/.config/claude/projects` 与 `CLAUDE_CONFIG_DIR` 环境变量（ccusage 双路径 + 多值 env）。
2. **ClaudeQuotaService 只解析 `five_hour`/`seven_day` 两字段**；官方 `/api/oauth/usage` 还返回 `seven_day_sonnet`/`seven_day_opus`（分模型限额）、`extra_usage`（额外 credits）、`limits[]`、`rate_limit_tier`。
3. **CodexQuotaService 依赖 codex CLI app-server 子进程**；vibe-usage-app 证明可从本地 sessions JSONL 的 `token_count` 事件直接读 `rate_limits`（TokenStep 增量缓存已在解析这些行，边际成本≈0）。
4. **成本是"本地粗略估算"**；业界标准做法（ccusage auto 模式）：优先行内 `costUSD`，缺失用 LiteLLM/models.dev 单价计算，含 cache 读写两类单价与 fast 模式加价。
5. **无 5h blocks / burn rate / 耗尽预测**（PRD backlog）；无 usage_limit_reset_time 提取；无 provenance 置信度标签。
6. **刷新是纯定时轮询**（PRD backlog 的 FSEvents）；ccusage v17 live monitor 的 mtime 增量 + hash 去重集 + 24h 滚动窗口是已验证的轮询替代。

---

## 三、优化方案（按优先级）

### P0 —— 低成本高价值，可立即排期

#### P0-1 Codex 限额离线读取（来源：vibe-usage-app `CodexRateLimitReader.swift`）

从 `~/.codex/sessions/**/*.jsonl` 中 `payload.type == "token_count"` 事件携带的 `rate_limits` 对象读取 `primary`（5h 窗）/`secondary`（7d 窗）。

- 算法要点：按**事件时间戳取全局最新**（Codex Desktop 可能有多个并发 rollout）；按 mtime 排序文件做剪枝（文件 mtime 不再新于已找到的最佳事件时间戳即可跳过）；`resets_at` 已过期的窗口直接丢弃；双窗全过期显示 noData 而非渲染错误百分比；UI 标注"数据截至"时间。
- TokenStep 落地：Codex 增量缓存已在解析 token_count 行，持久化最近一次 rate_limits 即可；作为现有 app-server 方案的**离线兜底**（无 codex CLI / CLI 失败时不再显示空）。

#### P0-2 Claude quota 响应字段扩展（来源：TokenBar `agent_usage.rs` 实测结构）

`/api/oauth/usage` 追加解析：`seven_day_sonnet`/`seven_day_opus`/`seven_day_omelette`（窗口键名跨 plan 不稳定，按候选列表逐个尝试）、`extra_usage.{monthly_limit, used_credits, utilization, currency}`、`rate_limit_tier`。429 时遵循 `Retry-After`，last-good 缓存不清屏（TokenStep 已有 10min 缓存，补 429 语义即可）。

#### P0-3 Claude XDG 双路径 + `CLAUDE_CONFIG_DIR`（来源：ccusage `adapter/claude/paths.ts`）

`collectionState` 与采集路径改为 `~/.claude/projects` + `~/.config/claude/projects` 双扫；`CLAUDE_CONFIG_DIR`（支持逗号分隔）设置后仅用指定路径。修复使用 XDG 配置用户的 0 数据问题。

#### P0-4 成本计算升级为 auto 模式（来源：ccusage `pricing.ts`；PRD 边界内做法）

- 优先级：行内 `costUSD`（Claude Code JSONL 自带）> 计算（token × 单价）。
- 定价双源：models.dev `api.json`（USD/百万 token）为主、LiteLLM `model_prices_and_context_window.json`（USD/token）兜底；**单位相差 10^6，必须统一**。
- 符合 PRD"不做远程动态定价"的落地方式：**构建时内嵌定价快照**（ccusage Rust 版 build.rs 做法），发版时更新，零运行时网络请求；后续可选 24h TTL 缓存在线刷新作为 opt-in。
- 细节：四类 token 分别计价（input/output/cache_write/cache_read）；模型名先归一化再查价（`claude-sonnet-4-5-20250929` → 前缀匹配链）；`usage.speed == "fast"` 乘加价倍率。
- CC Switch 差异化机会：better-ccusage 的多供应商定价表思路——按 CC Switch 当前供应商分别计价。

#### P0-5 官方限额重置时间提取（来源：ccusage `getUsageLimitResetTime`）

Claude Code JSONL 中 `isApiErrorMessage == true` 且 content 含 `"Claude AI usage limit reached"` 的行，其后第一个 `|` 分隔的数字为 Unix 秒级重置时间。作为限额状态展示的**官方权威信号**（比任何本地预测都准），实现只需一个字节查找。

### P1 —— 与 PRD vNext/backlog 对齐，规划排期

#### P1-1 5h blocks + burn rate 预测（来源：ccusage `session-blocks.rs`）

```
切分：block 起点 = floor_to_hour(首条时间)（官方窗口按整点对齐）
      距起点 >5h 或距上一条 >5h → 封存（后者插入 gap block）
active = (now - 最后一条 < 5h) && (now < start+5h)
burn rate：tokens/min = 总量 / (首条→末条分钟数)   ← 用活动跨度，非窗口全长
projection（仅 active）：预计总量 = 当前 + rate × 剩余分钟
状态三档：exceeds / warning(>80%) / ok；限额可用历史峰值 block（"max"）个性化
```
定位：官方 quota API 不可用/未开启时的 `local_estimate` 补充（见 P1-2 标签体系），不做主显示。

#### P1-2 Provenance 置信度标签（来源：Maciek v4 "Usage-Ops"）

所有对外展示的数字标注四级之一：`official`（官方 API/行内 costUSD）/ `local_estimate`（本地解析计算）/ `experimental`（实验源）/ `unknown`。与 PRD vNext"可信可见"主任务**直接契合**，建议作为 V1 的展示层骨架，blocks 等功能上线时自然归位。

#### P1-3 事件驱动刷新（来源：ccusage v17 live monitor + TokenBar usage_tail）

- `DispatchSource.makeFileSystemObjectSource(.write)` 监视活跃 session 文件 + 会话根目录（新文件创建）；回调从上次 offset 续读。
- TokenBar 的稳态优化：目录拓扑+指纹哈希成 source_token，未变则只做 stat 扫描零解析；快照式重建事件窗口（1h + 300s 余量）而非增量 append，重复交给既有去重。
- 收益：消除 PRD 中"打开面板才刷新"的新鲜度焦虑——用时实时、闲时零开销，且比缩短轮询间隔省电（与 0.1.48 能耗优化方向一致）。

#### P1-4 解析性能对齐（来源：ccusage 性能清单，需先 profile 再取）

按需选用：① 行级字节 marker 预筛（含 `"usage":{` 才解析）；② 去重冲突时保留 tokenTotal 更大者 + sidechain（`msg_id:advisor:N` 重放）处理；③ 时间有序性单遍检测避免全排序；④ 文件按大小 LPT 贪心分片并行（UsageCollector 现为单线程）。注：TokenStep 有增量缓存，重解析仅发生在变化文件，收益需 benchmark 验证（docs/benchmarks 已有基准惯例）。

#### P1-5 通知系统（来源：ClaudeBar 阈值色 + TokenEater 细粒度通知）

阈值分档（如 >50% 剩余绿 / 20-50% 黄 / <20% 红）；通知按"面（5h/7d/分模型）× 事件（升级/恢复/重置提醒）"矩阵设计；配额刷新失败不清屏。TokenEater 的连续风险评分（绝对用量+投影速率+pacing 合成，早期窗口置信度阻尼）是静态阈值的进阶形态。

### P2 —— 产品差异化，长期 backlog

| 方案 | 来源 | 说明 |
|---|---|---|
| WidgetKit 桌面小组件 | TokenEater、AgentLimits | 菜单栏之外的第二展示面；PRD 已列 backlog |
| 活跃会话浮窗 + 点击跳转终端 | TokenEater Agent Watchers | hover 显示活跃 Claude Code 会话，点击跳 Terminal/iTerm2/tmux/Kitty/WezTerm；差异化体验 |
| 52 周热力图 + per-project/per-branch 下钻 | watkinsye/vibe-usage、opencode-stats | TokenStep 自有历史快照，天然支持长周期（竞品受 Claude 30 天日志清理限制） |
| 多源扩展架构 | ccusage adapter（detect→discover→parse→aggregate→return 五层生命周期） | ZCode/Hermes/WorkBuddy 转正或新增 Gemini/Qwen/Kimi 时参考；每源固定文件布局 |
| "若无订阅会花多少钱"视角 | vibepulse | 基于精确成本计算（P0-4）的营销差异化叙事 |
| Homebrew cask 分发 | ClaudeBar/TokenEater/vibepulse | 降低安装门槛，配合现有 DMG |
| 机器可读状态协议 | Maciek `--write-state` 版本化快照 JSON | 供脚本/其他工具集成 TokenStep 数据 |

---

## 四、执行建议

1. **P0 五项均不动采集主干**：P0-1/2/3/5 是小改，P0-4 是新增 PricingService + 成本来源优先级改造。可作为一个独立 Goal 排在 PRD vNext 的 V1 之前或并行（成本快照属构建期资产，不违反"本轮不做"清单中"远程动态定价"的边界）。
2. **P1-2（provenance 标签）建议提前**：它是 PRD vNext"可信可见"的最自然实现语言，先定标签规范，后续 blocks/FSEvents/定价功能各自归位，避免 retro-fit。
3. **P1-3（FSEvents）建议在 V2 采集可靠性 Goal 中一并设计**：事件驱动与现有 checkpoint/能耗策略有交互（事件唤醒是否受电池模式约束等），需要整体设计而非打补丁。
4. **保持并发扬独有优势**：CC Switch 支持、Codex 增量缓存、历史快照仓库是调研范围内无人具备的资产，宣传与产品叙事应围绕它们。

---

## 附：调研产物

- ccusage 本地克隆：`/tmp/ccusage`（main, Rust）、`/tmp/ccusage-ts`（v19.0.3）、`/tmp/ccusage-v17`（v17.2.1, 含 live monitor）
- 关键端点备忘：
  - Claude：`GET api.anthropic.com/api/oauth/usage`（Bearer + `anthropic-beta: oauth-2025-04-20`）；刷新 `POST platform.claude.com/v1/oauth/token`（client_id `9d1c250a-e61b-44d9-88ed-5944d1962f5e`）
  - Codex：`GET chatgpt.com/backend-api/wham/usage`（auth.json access_token）；或本地 JSONL `token_count` 事件 `rate_limits`
  - 定价：`models.dev/api.json`（USD/1M）、`raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json`（USD/token）
