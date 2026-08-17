# TokenStep 0.2.0 PRD · 多源用量 + 横版浮窗

状态：待开发
撰写：Ptii
基线代码：0.1.48（`TokenStepSwift`）
文档定位：**交接给开发用的执行文档**。第 0 章是工程约束和已核实的代码事实，动手前必须读完。

---

## 0. 给接手开发的人

### 0.1 工程约束（不可违反）

| 项 | 值 | 说明 |
|---|---|---|
| 语言/工具链 | Swift 6.2.4，`swift-tools-version: 5.9` | `TokenStepSwift/Package.swift` |
| 最低系统 | macOS 14 | `platforms: [.macOS(.v14)]` |
| **外部依赖** | **零** | `Package.swift` 无 `dependencies`。**不要引入任何第三方包**，SQLite 用 `import SQLite3`，网络用 `URLSession`，JSON 用 `Codable` |
| Target | `TokenStepSwift`（executable）+ `TokenStepSwiftTests` | `TokenStepHelper` 由构建脚本单独打包，不在 `Package.swift` 里（它故意共享 app 内部源码，SwiftPM 无法二次持有） |
| UI 框架 | SwiftUI，无 storyboard | |

### 0.2 构建与测试

```bash
# 构建并运行（会打 .app 到 TokenStepSwift/dist/TokenStep.app）
script/build_swiftui_and_run.sh

# 只跑测试
cd TokenStepSwift && swift test

# 单个测试
cd TokenStepSwift && swift test --filter UsageCollectorCodexTests
```

现有测试 8 个文件，都在 `TokenStepSwift/Tests/TokenStepSwiftTests/`：

```
AgentWorkRankServiceTests.swift          UsageCollectorCCSwitchTests.swift
EnergyRefreshPolicyTests.swift           UsageCollectorClaudeCodeTests.swift
MainWindowNavigationTests.swift          UsageCollectorCodexTests.swift
UsageSnapshotRefreshPolicyTests.swift    UsageCollectorExperimentalAgentTests.swift
```

**测试模式**：运行时在临时目录建真的 jsonl / sqlite 文件，然后调 `UsageCollector` 上的 `*ForTests` 入口（如 `collectUsageSnapshotForTests`、`collectCodexUsageSnapshotForTests`、`collectCCSwitchProxyUsageSnapshot(databaseURL:)`）。新增源必须照这个模式补测试，不要 mock 掉 SQL 层。

### 0.3 已核实的代码事实（引用这些，不要凭记忆）

动手前这些都在 0.1.48 真机核对过。**行号是 0.1.48 的，改完代码会漂移，认符号名不认行号。**

| 事实 | 位置 |
|---|---|
| `UsageCollector.collect()` 硬编码 6 个源 | `Services/UsageCollector.swift` L41 |
| 6 个采集函数 | 同文件：`collectCodex` L447 · `collectClaudeCode` L1628 · `collectCCSwitchProxyUsage` L1705 · `collectZCodeUsage` L1856 · `collectHermesUsage` L1964 · `collectWorkBuddyUsage` L2079 |
| **读外部只读库的统一 helper** | `sqliteJSONRows(database:query:)` L3203 —— 起 `/usr/bin/sqlite3 -readonly -json` 子进程。**Cursor 两个服务直接复用它** |
| `UsageRecordSource` enum | 同文件 L4314 |
| `UsageSnapshot` / `DailyUsage` / `DailyAgentWork` | `Models/UsageModels.swift` L3 / L94 / L221 |
| `DailyAgentWork` 未用字段 | `outputTokens` L227 · `modelRequestCount` L230 · `toolCallCount` L231 |
| `SourceInfo` | 同文件 L483 |
| `CodexQuotaSnapshot` / `.unavailable` / `CodexQuotaWindow` | 同文件 L541 / **L550** / L553 |
| `TokenRankLeaderboard` | 同文件 L582 |
| `TokenStepSettings` | 同文件 L811（`historyDays` L814、`showCodexQuota` L821） |
| **设置的手写 Codable**（见 0.4） | `CodingKeys` L827 · `defaults` L845 · `init` L862 · `init(from:)` L894 · `encode(to:)` L927 |
| 迁移先例（照抄这个写法） | `legacyShowAgentWorkRank` → `agentWorkRankVisibility`，L915–L921 |
| `AppState.codexQuota` / `claudeQuota` | `Stores/AppState.swift` L12 / L13 |
| 额度刷新入口（改造点） | `AppState.refreshCodexQuota` L240；前台入口 `refreshForForeground` L214 |
| `quotaTTL = 15min` / `rankTTL = 30min` | `Support/EnergyRefreshPolicy.swift` **L12** / L13 |
| 电池地板 30min / AC 15min | 同文件 L11 / L10 |
| `tokenToolColor` | `Views/Components.swift` L653 |
| `orderedToolEntries` | 同文件 L672 |
| **`uniqueToolNames` 写死 fallback** `["Codex", "Claude Code"]` | 同文件 L685 |
| `ContributionWallView` | 同文件 L576（34 周 × 7 天，见 R7.5） |
| `contributionColor(tokens:goal:)` | 同文件 L639 |
| `ToolUsage.displayColor` + **`ModelUsage.displayColor`** | `Support/Formatters.swift` L116 / **L122**（两处都要改，别只改第一处） |
| `PopoverAgentWorkStrip` | `Views/AgentWorkViews.swift` L265 |
| `AgentWorkSourceFilter` | 同文件 L857 |
| 榜单 client 名映射 switch | `Views/Popover/PopoverTokenRankCard.swift` `primaryClientName` L212–L222 |
| 「全榜今日 Token」小胶囊（要升级为主视觉） | 同文件 **L137** |
| `rankContext`（超过 N% 算法，沿用） | 同文件 L191 |
| `historyDays` clamp（有字段无 UI） | `Services/DataService.swift` `normalize` L285，clamp 在 L291 |
| 榜单服务：**文件名 `TokenRankService.swift`，类型名 `AgentWorkRankService`** | `Services/TokenRankService.swift` |
| 灵动岛额度 mini：**类型名 `TokenIslandQuotaMiniView`，且是 `private`** | `Views/TokenIslandView.swift` L298 |
| 今日分解卡：**类型名 `TodayBreakdownCard`（单数）** | `Views/TodayBreakdownCards.swift` L3 |
| 额度服务形状（照抄）：`enum X { static func read() throws -> ... }` | `Services/CodexQuotaService.swift` L3 · `Services/ClaudeQuotaService.swift` L3 |
| **可复用的额度缓存模式** | `ClaudeQuotaService.readFreshCache` L109 / `writeCache` L123 |

`SourceInfo.status` 的**真实取值全集**（设置页要显示这些，别自己编）：

```
ok_sqlite · missing · missing_db · unreadable_db · missing_table
schema_unreadable · schema_mismatch · schema_missing_data_source
query_failed · disabled · incremental_cache_error
```

### 0.4 最容易踩的坑：给 `TokenStepSettings` 加字段要改 6 处

`TokenStepSettings` 没用编译器合成的 Codable，是全手写的。加一个字段（本版要加 `enabledQuotaProviders`、`cursorQuotaEnabled`、`cursorCodeSignalEnabled`）必须同步改：

1. 属性声明（L812 起）
2. `enum CodingKeys`（L827）—— 注意是 snake_case 映射
3. `static let defaults`（L845）
4. `init(...)` 全参数列表（L862）—— **改这里会打断所有调用点，编译器会报一片错，属正常**
5. `init(from decoder:)`（L894）—— 用 `decodeIfPresent ?? defaults.x`，缺字段不能抛错
6. `encode(to:)`（L927）

漏任何一处的表现：能编译但设置**静默丢失**（存了读不回来）。改完必须补一个「写入 → 重新解码 → 值不变」的测试。

### 0.5 设计稿

浏览器打开 `design-drafts/index.html`（本地起 `python3 -m http.server 8765`）。

| 稿件 | 覆盖 | 对应需求 |
|---|---|---|
| `prd-v2-popover.html` | 浮窗全状态（默认 / 0·2·6 家额度 / 无榜 / 预警 / 失败 / 通知条）+ 灵动岛 + 菜单栏图标 | R4 R5 R6 |
| `prd-v2-windows.html` | 仪表盘今日·历史·隐私 + 设置数据源·额度·通用 | R6 R7 R7.5 R8 |
| `d3-actions-board.html` | 横版四栏 + 固定底栏的定稿方向 | R4 |

其余 `d3-wide.html` / `horizontal-popover*.html` / `default-rank-quota3.html` 是过程稿，**已废弃**，不要照着做。

### 0.6 执行顺序

M1 → M2 → M4 →（M3 与 M5 并行）。理由见第 6 章：先做纯重构和 UI，把 Cursor 这类非官方外部依赖后置，避免它拖住整版。

---

## 1. 这一版要解决什么

0.1.48 的问题不是功能少，是**能看到的太窄**：

1. 只有 Codex 和 Claude Code 进正式统计。用户实际同时在用 Cursor、GLM、Kimi、Grok，圆环只反映了一部分。
2. 额度只覆盖 Codex 5h/7d + Claude OAuth，模型写死两个窗口，装不下别家。
3. 浮窗竖版 412 宽，卡片纵向堆叠，信息密度低，宽度空间完全没用。
4. `DailyAgentWork` 已经采到请求数、工具调用数、分时桶，UI 几乎没展示。

目标：**把已有数据用出来，把够得着的新数据源接进来，并且不牺牲 local-first 的可信度。**

---

## 2. 前置结论：Cursor 不能按 Codex 的方式采集

`docs/AGENT_SUPPORT.md` L85 把 Cursor 列在候选区，写着「需要确认是否本地暴露 token usage」。本次已真机实测，结论如下。

### 2.1 实测结果（2026-08-17）

| 位置 | 内容 | 有 token 吗 |
|---|---|---|
| `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`（**253MB** + 6MB WAL） | `ItemTable` 有 `cursorAuth/accessToken`(412B)、`refreshToken`(412B)、`cachedEmail`、`stripeMembershipType`、`stripeSubscriptionStatus`；`cursorDiskKV` 有 `composerData:`、`bubbleId:`、`agentKv:` | ❌ 无 usage / token / cost 键 |
| `~/.cursor/ai-tracking/ai-code-tracking.db` | `ai_code_hashes` 9122 行；`scored_commits` 0 行 | ❌ 无 token，✅ 有**代码块数与模型** |
| `~/.cursor/projects/*/agent-transcripts/*.jsonl` | 每行只有 `message` / `role`，另有 `turn_ended` | ❌ 明确不含 tool call 与 usage |

顺带实测的其他源：

- **Grok** `~/.grok/sessions/*/chat_history.jsonl`：有 `model_id`、`model_fingerprint`、`reasoning_effort`，**无 usage**。`~/.grok/auth.json` 存在，可用于额度。
- **Kimi** `~/.kimi/sessions/*/wire.jsonl`：顶层只有 `message`/`protocol_version`/`timestamp`/`type`，需拆 `message` 内层才可能有 usage，**未验证成功**。
- **Copilot / Gemini CLI / Qwen**：`~/.copilot`、`~/.gemini`、`~/.qwen` 只有配置与凭证，**无本地用量**。

### 2.2 两个推翻常规做法的实测结论

**结论 A：读 Cursor 的库不需要复制，`-readonly` 就够。**

实测：Cursor 进程（PID 92329）正持有 `state.vscdb` 写句柄、WAL 有 6MB 未 checkpoint 数据时，`/usr/bin/sqlite3 -readonly -json` 连读 3 次全部成功，253MB 库耗时 **9ms**。

所以**不要**为了绕锁去复制这个 253MB 的库——那是纯浪费。直接复用现有的 `sqliteJSONRows`（`UsageCollector.swift` L3203），它已经是 `-readonly` 子进程方案，天然只读、不碰 WAL、不可能写坏用户数据。

**结论 B：`ai_code_hashes` 每天零点被清空。**

实测 `tracking_state` 表：`trackingStartTime = 2026-08-17 00:00:22`，正好当天零点；表内 9122 行的时间跨度是 `07:12:04` → `11:50:43`，全在当天。

推论与硬约束：

- L3 **只能做「今日」**，做不了历史趋势、做不了「昨天 vs 今天」。
- 若产品要留 Cursor 产出历史，**必须 TokenStep 自己落盘累积**。本版**不做**（见第 3 章 Out），先只显示今日，把复杂度压住。
- 用户当天没开过 TokenStep，那天的 Cursor 产出数据就永久没了。这是 L3 的固有性质，**接受它**，不要为此加后台常驻采集。

### 2.3 由此确立的产品原则：三层数据源模型

沿用现有规则「能从本地稳定读到 token 才进正式统计」，但把「不能读到 token」再细分。**这是本版架构主干**：

| 层 | 名称 | 判定 | 进圆环/总量 | 展示位置 | 例子 |
|---|---|---|---|---|---|
| **L1** | 本地账本 Local Ledger | 本地日志有可核对的 token 数 | ✅ 计入 | 圆环、Agent 表、榜单 | Codex、Claude Code、CC Switch、ZCode |
| **L2** | 配额探针 Quota Probe | 只能拿到百分比/额度/花费 | ❌ 不计入 | 仅额度栏 | **Cursor**、GLM、Kimi、Grok |
| **L3** | 产出信号 Output Signal | 不是 token，是产出量 | ❌ 不计入 | 独立卡片 | **Cursor AI 代码块数** |

**为什么必须分层**：如果把 Cursor 的美元花费折算成 token 塞进圆环，圆环就不再是「本地可核对的 token」，整个产品的可信度基础就没了。Cursor 用户想看的其实是「这个月额度还剩多少」，那属于额度栏。

### 2.4 Cursor 接入方案

**L2 额度（opt-in，默认关）**

1. 用 `sqliteJSONRows` 读 `state.vscdb`：`select value from ItemTable where key='cursorAuth/accessToken'`。**不复制库**（见结论 A）。
2. userId 从 accessToken 的 JWT payload `sub` 解出。不要依赖 `storage.json`——实测那里只有 `telemetry.machineId`，没有 userId。
3. 请求 `GET https://cursor.com/api/usage?user={userId}`，Cookie `WorkosCursorSessionToken={userId}::{accessToken}`；套餐信息 `GET https://cursor.com/api/auth/stripe`。
4. **风险明示**：这些端点非官方公开契约，随时可能变。UI 必须能表达「Cursor 额度暂不可用」，且该失败不影响其他栏。

**L3 AI 代码产出（opt-in，默认关）**

只读 `~/.cursor/ai-tracking/ai-code-tracking.db`，实测 schema：

```sql
CREATE TABLE ai_code_hashes (
  hash TEXT PRIMARY KEY, source TEXT NOT NULL, fileExtension TEXT,
  fileName TEXT, requestId TEXT, conversationId TEXT,
  timestamp INTEGER, model TEXT, createdAt INTEGER NOT NULL
)
```

- 落日期用 **`createdAt`**（NOT NULL，比 `timestamp` 可靠；实测两者有 3503/9122 条不一致）。
- `count(*)` 是**代码块数，不是行数**（实测同一 `timestamp` 会有多条 hash）。文案不许写成「行」。
- 可用维度：块数、`count(distinct model)`、`count(distinct conversationId)`、`count(distinct requestId)`、`count(distinct fileName)`。本机实测今日：9122 块 / 3 模型 / 2 会话 / 12 请求 / 35 文件。
- ⚠️ **`fileName` 存的是完整绝对路径**（如 `/Users/xxx/Documents/项目名/docs/x.md`）。只允许 `count(distinct fileName)`，**不读取、不缓存、不展示、不写日志任何路径原文**。这条写进隐私页。
- `scored_commits`（`composerLinesAdded` / `humanLinesAdded` / `v2AiPercentage`，注意 `v2AiPercentage` 是 **TEXT**）本机 0 行，**可选增强，不作为验收项**。
- 不读 `tracked_file_content`（代码正文）、不读 `conversation_summaries`（摘要文本）。

**不做**：不从 transcript 估算 token，不按聊天字数折算。

---

## 3. 范围

### In

- R1 数据源框架泛化（L1/L2/L3 抽象）
- R2 Cursor 接入（额度 + AI 代码产出）
- R3 额度模型泛化 + GLM / Kimi / Grok
- R4 横版浮窗 D3（浅色四栏 + 固定操作底栏）
- R5 消耗榜改为「全榜今日消耗」
- R6 Agent Work 已采字段补全展示
- R7 设置页新增数据源与额度管理
- R7.5 历史页保护现状（只允许两处增量）
- R8 隐私页同步

### Out（本版不做）

- 云同步、账号体系
- 代理接管（继续不开代理）
- Roo / Cline / Kilo（仍缺真机样本）
- Kimi 本地 token 采集（`wire.jsonl` 未验证成功，只做额度）
- **Cursor L3 历史累积落盘**（见 2.2 结论 B，本版只显示今日）
- 燃尽率预测（P1）

---

## 4. 详细需求

### R1 数据源框架泛化

**现状**：无统一抽象。6 个源硬编码在 `UsageCollector.collect()`（L41），新增一个源要改 14 处：

采集函数、`collect` 接线、`aggregate` sources dict、`collectionState` 文件枚举、`UsageRecordSource` enum、设置字段、设置 UI、`AppState` setter、`DataService` 传参、`tokenToolColor`、`orderedToolEntries`、`uniqueToolNames` 的写死 fallback、`AgentWorkSourceFilter`、榜单 client 映射。

**要求**：

1. 新增 `AgentSourceDescriptor`：`id`、`displayName`、`tier`(L1/L2/L3)、`colorToken`、`isExperimental`、`probePaths`。集中登记所有源，消灭散落的 switch。
2. 下列全部改为查 descriptor：
   - `tokenToolColor`（`Components.swift` L653）
   - `orderedToolEntries`（同文件 L672）
   - `uniqueToolNames` 的 `fallback: ["Codex", "Claude Code"]`（同文件 L685）
   - `ToolUsage.displayColor`（`Formatters.swift` L116）**和 `ModelUsage.displayColor`（L122）**——两处都改
   - `AgentWorkSourceFilter`（`AgentWorkViews.swift` L857）
   - `primaryClientName`（`PopoverTokenRankCard.swift` L212–L222）
3. L2/L3 源**不得**进入 `UsageRecord` 流水线，从类型上隔离，避免误计入 `totals`。

**验收**：新增一个 L1 源，只需登记 descriptor + 写 collect 函数 + 加测试，不改任何 UI switch。

### R2 Cursor 接入

实现细节见 2.4。补充工程要求：

1. 两个新服务互不依赖，各自失败各自降级：
   - `Services/CursorQuotaService.swift`（L2，走网络）
   - `Services/CursorCodeSignalService.swift`（L3，纯本地）
2. 形状照抄现有额度服务：`enum X { static func read() throws -> Y }`（见 `CodexQuotaService.swift` L3）。缓存照抄 `ClaudeQuotaService.readFreshCache`（L109）/ `writeCache`（L123）。
3. 读库统一走 `sqliteJSONRows`，**只读、不复制、不写**。任何情况下不得对 Cursor 的库做写操作。
4. accessToken **不落盘、不进日志、不进快照**，仅内存持有当次请求。
5. 两个开关独立：`cursorQuotaEnabled`、`cursorCodeSignalEnabled`，默认都关（加字段记得改 0.4 那 6 处）。
6. 首次开启时弹一次说明：额度需要访问 cursor.com，代码产出为纯本地。

### R3 额度模型泛化

**现状硬约束**：`CodexQuotaSnapshot`（`UsageModels.swift` L541）只有 `fiveHour` / `sevenDay`；Claude 复用同一类型；`AppState` 写死 `codexQuota`(L12) / `claudeQuota`(L13)；设置只有一个 `showCodexQuota` Bool 管两家。

**目标模型**：

```swift
struct ProviderQuota { var provider: ProviderID; var windows: [QuotaWindow]; var status: QuotaStatus; var fetchedAt: Date? }
struct QuotaWindow  { var kind: QuotaWindowKind; var usedPercent: Double; var remaining: Double?; var total: Double?; var resetsAt: Date? }
enum QuotaWindowKind { case fiveHour, sevenDay, session, weekly, monthlyCredits, tokenWindow, spend }
```

`AppState.quotas: [ProviderID: ProviderQuota]` 取代两个写死字段。改造入口是 `AppState.refreshCodexQuota`（L240），改成按 `enabledQuotaProviders` 并发拉取、独立失败。

**设置迁移**：`showCodexQuota: Bool` → `enabledQuotaProviders: Set<ProviderID>`。`true` 迁移为 `[.codex, .claude]`，`false` 为空集。**照抄 L915–L921 的 `legacyShowAgentWorkRank` 写法**，并遵守 0.4 的 6 处改动。

**接入清单**（全部 opt-in、只读本机登录态）：

| 提供商 | 凭证来源 | 窗口 |
|---|---|---|
| Codex | 现有 `codex app-server` JSON-RPC | 5h / 7d |
| Claude | 现有 Keychain OAuth | 5h / 7d |
| **Cursor** | `state.vscdb` accessToken（`-readonly`） | 周期额度 / 花费 |
| **GLM** | `ZAI_API_KEY`（Coding Plan ≠ 按量 key；区分 global/cn） | Token 窗 / 日 / 月 |
| **Kimi** | `~/.kimi` OAuth（**不要**用 Moonshot 开放平台 key） | Session / Weekly |
| **Grok** | `~/.grok/auth.json`（`grok login` 产生，普通 xAI key 无效） | Credits |

**失败态铁律**：失败绝不显示成 0%。必须显示「暂不可用」并保留上次成功值与时间。现有 `CodexQuotaSnapshot.unavailable`（L550）的语义要完整延续到新模型。

**刷新**：复用 `EnergyRefreshPolicy.quotaTTL`（L12，15min）与电池 30min 地板（L11）。**不得新增任何计时器**，全部挂在 `AppState.refreshForForeground()`（L214）。各提供商并发但独立失败。

### R4 横版浮窗 D3

定稿方向见 `design-drafts/d3-actions-board.html` 与 `prd-v2-popover.html`。

- 宽度 **900**，浅色卡片，四栏用发丝分隔线，**不允许整列深色**。
- 四栏：今日消耗（环画在浅底）| Agent 用量 | 订阅额度 | 消耗榜。
- 底栏固定：`本地统计` / `刷新 5 分钟` 一行 + 主按钮「打开仪表盘」靠左（定宽，**不拉满**）+ 刷新/设置/退出靠右。改 `Popover/PopoverFooterView.swift`。
- 深色仅两处：菜单栏 T 标识、榜栏「全榜今日消耗」小卡。

**额度栏数量规则**：0 家整栏消失；1–2 家全宽竖排；3 家竖排不留空格；4+ 才 2×2 并显示 +N。

**结构分层**（高度必须稳定）：

```
标题   TokenStep · 已同步 · 截图
通知   错误 / 重算 / 更新（有才出现，插在四栏与底栏之间）
四栏   只读信息
底栏   只做动作，永不隐藏
```

**铁律**：任何内容栏消失（无榜、0 额度、采集失败）都不得影响底栏四个动作的存在与位置。

### R5 消耗榜：全榜今日消耗

**明确不做**邻近名次（#127 / 你 / #129）——`entries` 通常是榜首切片 + 自己，前后名次不稳定，且不是用户第一问题。

榜栏三层，字段全部来自现有 `TokenRankLeaderboard`（L582），无需改服务：

1. 我的名次 `entry.rank` + `超过 N%`（沿用 `rankContext` 算法，L191）
2. **全榜今日消耗**（深色小卡主视觉）：`totalTokens` + `totalRankedUsers`
3. 我的今日：`entry.totalTokens`

现有把「全榜今日 Token」做成并排小胶囊（L137），本版升级为该栏主视觉。点击行为不变：点名次进个人页，其余进全榜页。

### R6 Agent Work 字段补全

已采但 UI 完全没用的字段（`DailyAgentWork` L221）：

- `modelRequestCount`（L230）❌ 未用
- `toolCallCount`（L231）❌ 未用
- `outputTokens`（L227）❌ 未单独展示

浮窗 Agent 栏表格列定为：来源 / Token / 请求 / 工具 / 缓存，直接消化前两项。仪表盘今日页补「输入 / 输出 / 缓存」三段。

`activeHours` 存在两套算法（`DailyAgentWork.activeHours` 字段 L229 vs Today 卡从 `hourlyBuckets` 重算）——本版**统一为 `hourlyBuckets` 重算**，避免两处数字不一致。

### R7 设置页

新增两张卡，改造一张：

1. **数据源**（新）：按 L1/L2/L3 分组列出所有源，每行显示真实状态。状态文案必须映射 0.3 里 `SourceInfo.status` 的真实取值全集（`ok_sqlite` / `missing_db` / `schema_mismatch` / …），**不要自己编 `ok`、`all_deduped` 这种不存在的值**。Cursor 两个开关放这里。
2. **订阅额度**（改造 `Settings/SettingsDisplayRefreshCards.swift` 里的单 toggle）：改成 6 家清单，每行独立开关 + 凭证状态 + 最近成功时间。
3. `historyDays` 目前有字段无 UI（默认 180，`DataService.normalize` L291 只做 clamp 到 7–365），本版补入口。

### R7.5 历史页：结构不许动

这页现在就是对的，本版属于「保护现状」而非重设计。写清红线免得被顺手改坏（对照 `prd-v2-windows.html` 的历史页）：

- 活动墙就是 GitHub 式贡献图：**34 列（周）× 7 行（周一→周日）**，方块 15×15、间距 5、圆角 4。列是时间推进、行是周几，不要改成「31 列按日」那种排法。
- 起始日要回退到周一对齐（现有 `mondayOffset = (weekday + 5) % 7`），否则同一行不再是同一个周几，整面墙的语义就没了。
- **未来日期留空**（`Color.clear`），不是灰块；**今天带描边**（`tokenGreenDark`，1.5pt）。
- 图例 **6 档**：0 / 25% / 70% / 目标 / 2× / 3×，由 `contributionColor(tokens:goal:)`（L639）统一出色，跟着每日目标走，不写死阈值。
- 页面三块顺序不变：活动墙 → `StatsView` → 全部明细。
- 全部明细保持 **4 列**（日期 / Token 消耗 / 消耗金额 / 主力工具）。不要按来源拆成一堆数字列——那是今日页和 `StatsView` 的职责，明细表要能一眼扫日期。

本版只允许两处增量，都不改结构：

1. 工具图例改为查 descriptor，新增源（GLM / Kimi / Grok）自动出现，不再写死 Codex/Claude 二分色。
2. 墙格 hover 提示补「当天各来源占比」，数据用已有的 `DailyUsage.tools`，不新增采集。顺带补月份标签（现在缺，8 个月的墙没有月份很难定位）。

### R8 隐私页

必须逐条写明新增读取（`Views/PrivacyView.swift`）：

- **Cursor 额度**：以只读方式读 `state.vscdb` 取 accessToken，向 cursor.com 发请求；token 不存储、不上传第三方；非官方端点，可能失效。
- **Cursor 代码产出**：只读 `ai_code_hashes` 的**计数与模型名**；**不读取代码内容**（`tracked_file_content`）、**不读摘要**（`conversation_summaries`）、**不记录任何文件路径**（`fileName` 含完整绝对路径，只做去重计数）。
- 说明 Cursor 该表**每天零点被 Cursor 自己清空**，TokenStep 不做历史留存。
- 明确「所有新增源默认关闭」。

---

## 5. 页面清单与改动

| 页面 | 文件 | 本版改动 |
|---|---|---|
| 菜单栏浮窗 | `Views/PopoverPanelView.swift` | 重构为 900 宽四栏 + 固定底栏 |
| 今日环卡 | `Popover/PopoverTodayRingCard.swift` | 收进第 1 栏，保持浅底 |
| Agent 条 | `AgentWorkViews.swift` L265 | 升级为表格（请求/工具列） |
| 额度卡 | `Popover/PopoverQuotaCard.swift` | 改多提供商竖排 + 数量规则 |
| 消耗榜 | `Popover/PopoverTokenRankCard.swift` | 全榜今日消耗为主视觉 |
| 底栏 | `Popover/PopoverFooterView.swift` | 横版布局，主按钮定宽靠左 |
| 灵动岛 | `Views/TokenIslandView.swift` → **`TokenIslandQuotaMiniView`**（L298，`private`） | 额度 mini 改多提供商；动作集合不变。⚠️ 该文件里**没有** `TokenIslandView` 这个类型，入口是 `TokenIslandWindowView`(L17) / `TokenIslandPopoverWindowView`(L41) |
| 仪表盘·今日 | `Views/TodayView.swift`(L3) + `TodayBreakdownCards.swift` → **`TodayBreakdownCard`**(L3，单数) / `TodayBreakdownRow`(L54) | 补输入/输出/缓存；Cursor 产出卡 |
| 仪表盘·历史 | `Views/HistoryView.swift` | 结构不动；仅工具图例改查 descriptor |
| 活动墙 | `Views/Components.swift` → `ContributionWallView` L576 | 保持 34×7；补月份标签 + hover 来源占比 |
| 仪表盘·隐私 | `Views/PrivacyView.swift` | 按 R8 更新 |
| 设置 | `Views/SettingsView.swift` + `Views/Settings/*` | 新增数据源卡、额度提供商卡、`historyDays` |
| 菜单栏图标 | `Support/StatusBarIconRenderer.swift` | 额度 <20% 加预警点 |

---

## 6. 开发拆解

| 阶段 | 内容 | 依赖 | 风险 |
|---|---|---|---|
| **M1** | 额度模型泛化（`ProviderQuota`/`QuotaWindow`）+ 设置迁移。纯重构，UI 行为不变 | — | 低。迁移有先例；注意 0.4 的 6 处 |
| **M2** | `AgentSourceDescriptor` 抽象，收敛 R1 的 14 处硬编码 | — | 中。改动面广，靠测试兜 |
| **M3** | Cursor L2 + L3 两个服务；GLM/Kimi/Grok 额度 | M1 | **高**。端点非官方 |
| **M4** | 横版浮窗 + 榜栏改造 + Agent 表格 | M1 | 中。状态矩阵多 |
| **M5** | 设置页两张新卡 + 隐私页 + 菜单栏预警点 | M2/M3 | 低 |

**顺序**：M1 → M2 → M4 →（M3 与 M5 并行）。先把重构和 UI 做完，Cursor 这类不稳定外部依赖后置，避免它拖住整版。

**测试要求**：

- 每个新源按 0.2 的 fixture 模式补测（临时目录建真 sqlite/jsonl）。
- Cursor L3：造一个含 `ai_code_hashes` 的临时库，字段照 2.4 的 schema。
- Cursor L2 走网络的部分必须可注入假响应，不许在测试里真连 cursor.com。
- 设置迁移必须有测试：旧 JSON（只有 `show_codex_quota: true`）解码后 `enabledQuotaProviders == [.codex, .claude]`。
- 加字段后补「编码 → 解码 → 全字段不变」的往返测试（防 0.4 静默丢设置）。

---

## 7. 验收标准

1. 关闭所有新开关时，行为与 0.1.48 完全一致，`usage.json` 口径不变。
2. 旧设置文件（`show_codex_quota: true`）升级后，额度显示与 0.1.48 一致。
3. Cursor 额度失败时，只有该额度行显示「暂不可用」，圆环、Agent 表、榜单、底栏全部正常。
4. 额度提供商开 0/1/2/3/4/5/6 家，浮窗高度稳定，底栏四个按钮始终可点。
5. 无榜身份时右栏整列消失，不留「尚未关联」空白，底栏不动。
6. Cursor 的美元花费**不出现**在圆环、`totals`、榜单任何位置。
7. Cursor L3 的数字单位是「代码块」不是「行」。
8. 浮窗任一状态下不出现整列深色背景。
9. 新增源后 `grep` 不到新的 `switch` 硬编码分支。
10. 15 分钟内重复打开浮窗不触发重复网络请求（`quotaTTL` 生效）。
11. 全程不对 Cursor 的任何数据库产生写操作（可用 `fs_usage` 或改文件 mtime 前后比对验证）。
12. 日志、崩溃报告、`usage.json` 中 `grep` 不到 accessToken 片段与任何 Cursor 文件路径。

---

## 8. 边界与失败态

| 场景 | 表现 |
|---|---|
| Cursor 未登录 / 无 accessToken | 额度行「未登录 Cursor」，不报错弹窗 |
| Cursor 正在运行、WAL 未 checkpoint | 正常读取（实测可行，见 2.2 结论 A） |
| `state.vscdb` 不存在或损坏 | 「暂不可用」，不影响其他栏 |
| cursor.com 端点变更 | 「Cursor 额度暂不可用」+ 保留上次值与时间 |
| `ai_code_hashes` 为空（当天刚被清 / 未启用追踪） | 产出卡显示「今日暂无」，不显示 0 块 |
| GLM 用了按量 key 而非 Coding Plan | 明确提示「当前 key 非订阅计划」，不显示 0% |
| Grok 用普通 xAI key | 提示需 `grok login` |
| 榜单请求失败 | 仅榜栏内报错，保留缓存 |
| 全部额度失败 | 额度栏整栏消失，不留空壳 |
| 低电量 | 后台 30 分钟地板，前台打开仍即时刷 |

---

## 9. 遗留问题

1. Kimi `wire.jsonl` 的 `message` 内层是否含 usage，需要再验一台机器。若有，Kimi 可升为 L1。
2. `ai_code_hashes` 的清空规则只在本机观察到一次（`trackingStartTime` = 当天 00:00:22）。需要跨天再验一次，确认是「每日重置」而非「安装/升级后重置」。若实际能留多天，L3 可以考虑做趋势。
3. `scored_commits` 本机 0 行，需确认 Cursor 在什么条件下写入（可能需要 git commit 后台评分完成）。它是唯一能给出「AI 写了多少行 / 占比」的表，值得再探。
4. `config/pricing.json` 仍是粗估。Cursor 接入后「花费」会有两套口径（本地估算 vs Cursor 实际计费），UI 必须区分措辞，避免用户以为是账单。
