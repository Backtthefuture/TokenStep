# TokenStep v0.2 PRD：多 Agent 统计、项目维度与多设备同步

> 文档类型：Goal 目录与执行合同
> 文档版本：1.1
> 更新时间：2026-08-13
> 当前状态：PRD 已获用户确认（2026-08-13，"确认 /goal"）；未启动任何 Goal。
> 启动前核验记录：2026-08-13 live baseline `HEAD = origin/main = ef13871`（v0.1.48）✓；工作区存在 G-E0 未提交改动（8 个 tracked 文件），G-A1 激活条件未满足，等待用户裁决启动顺序（见 §2）。
> 顺序裁决：2026-08-13 用户确认按序推进 `G-E0 → G-V1 → G-V2 → G-A1 → G-B1 → G-A2 → G-S1`；G-A1 严格遵守"G-V2=complete"前置，不并行、不豁免。
> 当前范围：A1 Provider 架构与 T1 数据源、A2 T2 数据源、B1 项目维度、S1 多设备同步
> 上游文档：[PRD_TOKENSTEP_OPTIMIZATION.md](PRD_TOKENSTEP_OPTIMIZATION.md)（G-E0/G-V1/G-V2，本文所有 Goal 均排在其后）
> 决策基线：2026-08-13 用户已确认 4 项产品决策（见 §1.2）
> 情报来源：ccusage v20、vibe-cafe/vibe-usage（26+ 源路径表）、getagentseal/codeburn（40 Provider 与 provider docs 惯例）、tyuan511/vibe-usage（15 源 + WebDAV 同步）、tddworks/ClaudeBar。路径口径详见各任务引用与 `docs/agents/*.md`（本 PRD 交付物）。

---

## 0. 执行摘要

### 0.1 一句话目标

让用户在 TokenStep 的一个圆环里，看到**所有 AI Agent、所有项目、所有设备**的今日 Token 消耗——v0.2 主题："一个圆环看所有 Agent"。

### 0.2 本轮主任务

1. **多 Agent 统计（方案 A）**：T1 七源（Gemini CLI、Qwen Code、Kimi Code、OpenCode、Amp、Droid、Grok Build）+ T2 五源（GitHub Copilot、Cursor、Cline、Roo Code、Kiro/Antigravity 视样本可得性），全部走实验区、默认关闭、只读 usage 字段。
2. **项目维度（方案 B）**：从各源会话数据提取项目（只保留末级目录名），今日卡片"今天你的 token 走了这些路"、统计页按项目分布、分享卡带项目条目。
3. **多设备同步（方案 E）**：依托正安火账号体系（与 token-rank 共用身份、独立开关），上行按 `天×小时×Agent×模型×项目` 聚合的 token 计数，多台 Mac 数据合并展示；默认关闭、默认只看本机。

### 0.3 核心用户

- 同时使用 3 种以上 AI 编程工具（如 Codex + Claude Code + Gemini CLI）的重度用户；
- 在多个代码仓库间切换，想知道"今天的 token 花在哪个项目上"的人；
- 拥有多台 Mac（台式机 + 笔记本），希望圆环反映总消耗的人。

### 0.4 核心假设

"支持广度"已成为品类入场券（ccusage 16 源 / codeburn 40 源 / vibe-usage 26 源 / 4★ 新竞品 15 源）。TokenStep 以质量资产（增量缓存、去重、能耗策略）承接广度扩张后，"一个圆环看所有 Agent + 所有项目 + 所有设备"将成为 macOS 端独有的完整叙事。

### 0.5 本轮不做

- 新 Agent 源的**正式化**（转正仍按 B14：3 台真机 + 逐日对账）；
- task/任务维度（v0.3 backlog）；
- 成本计价改造（沿用现有估算，P0-4 属上游 PRD 范围）；
- 配额/限额对新源的适配（新源先只做用量统计）；
- Windows/Linux（TokenStep-Windows 由社区维护，另行同步）;
- 团队面板、榜单多人合计参赛（S1 仅设备间合并，榜单联动只留接口）；
- 通知、Widget、MCP、statusline、Homebrew（维持上游 Backlog）。

### 0.6 与上游 PRD 的关系

- 本 PRD 的所有 Goal 激活前提是上游 `G-V2 = complete`（或用户明确批准并行）；
- 上游 §0.5"本轮不做：新 Agent 数据源 / 项目路径"两条边界的**修订**集中声明在本文 §3，修订仅对 v0.2 范围生效；
- 上游 B14（新数据源）、B12 边界中"不读项目路径"的表述由本文 §3.2 取代。

---

## 1. 现状基线与已确认决策

### 1.1 编写时事实

| 项 | 已核验事实 |
|---|---|
| 基线 | `main = ef13871`（v0.1.48）；G-E0 改动尚未提交（见 git status） |
| 采集源 | Codex、Claude Code（正式）；CC Switch（实验）；ZCode/Hermes/WorkBuddy（实验，`showExperimentalAgentSources` 单一开关默认关） |
| 核心引擎 | `UsageCollector.swift` 4743 行；上游 V2-T04 将做最小 Collection Core 拆分 |
| 数据模型 | `UsageSnapshot` 七板块；无 project 维度 |
| 榜单身份 | `~/.token-rank/client-state.json`（id/昵称/头像），E0-T03 后严格 opt-in |

### 1.2 用户已确认的 4 项产品决策（2026-08-13）

| # | 决策 | 结论 |
|---|---|---|
| D1 | 项目名脱敏 | **只显示末级目录名**；完整路径不持久化、不展示、不上行、不进分享卡 |
| D2 | 多设备口径 | **默认只看本机**；"合并所有设备"为显式勾选，可分别控制今日圆环与历史统计，随时切回 |
| D3 | 分享卡 | **带项目条目**（脱敏目录名），风格与现有战报卡/节奏卡一致 |
| D4 | task 维度 | **v0.2 只做 project**；task 进 v0.3 backlog |

### 1.3 与上游 V1（可信可见）的衔接

V1 交付的四类证据标签（official / local_estimate / experimental / unknown）直接成为新源的展示语言：所有 T1/T2 源在 UI 上默认标 `experimental`。若 G-A1 先于 G-V1 启动（用户批准并行时），G-A1 必须自带最小 `experimental` 标签，不得出现无标签的新源数字。

---

## 2. Goal 模式执行总则

完全继承上游 PRD §2（同一时间一个 Active Goal；启动前展示完整 /goal 并获明确确认；estimated_minutes 非预算；Goal 启动不扩大权限；推送/PR/发布/使用签名凭据/上传数据需独立授权）。推荐顺序：

```
G-E0 → G-V1 → G-V2 → G-A1 → G-B1 → G-A2 → G-S1
                       └──────┬──────┘
                    （B1 可与 A2 并行，须用户批准）
```

G-S1 排最后：其上行 payload schema 依赖 B1 的项目维度定型，且依赖正安火服务端（外部依赖，见 S1-T01）。

---

## 3. 数据与隐私契约变更（v0.2 生效）

### 3.1 新增读取范围

| 读取对象 | 用途 | 红线 |
|---|---|---|
| 各 Agent 本地会话日志/数据库中的 usage 字段与 cwd/项目字段 | 用量统计与项目维度 | 只读；不读正文、prompt、回复、代码、凭据 |
| `~/.gemini`、`~/.qwen`、`~/.kimi-code`、`~/.local/share/opencode`、`~/.local/share/amp`、`~/.factory`、`~/.grok`、`~/.copilot`、Cursor `state.vscdb`、Cline/Roo globalStorage、`~/.kiro`、`~/.gemini/antigravity` 等 | 新数据源 | 见 §4/§5 各源 allowlist |

### 3.2 项目路径边界（取代上游 B14 "不读项目路径"表述）

1. 读取路径字符串后**立即截取末级目录名**（如 `.../03-工具与效率/token-usage-monitor` → `token-usage-monitor`）；
2. `usage.json`、缓存、快照、分享卡、上行 payload 中**只允许出现目录名**；
3. 完整路径仅存在于采集过程的内存中，进程结束即消失；
4. 目录名为空或不可解析时记为 `未命名项目`，不猜疑、不拼接；
5. 同名目录名跨机器合并时即为同一项目桶（这是 D1 决策接受的语义）。

### 3.3 多设备同步边界（新增网络能力，全 PRD 唯一新增网络点）

1. 默认关闭；关闭时**零身份读取、零网络请求**（对齐 E0-T03 榜单模式，测试同规格）；
2. 开启后上行内容仅限：设备名（用户可改）、`天×小时×Agent×模型×项目目录名` 的 token 计数、schema 版本；
3. **不上行**：金额（成本估算永远只在本机算）、完整路径、会话正文、凭据、本机其他 App 数据；
4. 解绑即删除本机同步状态并向服务端发送删除请求（best-effort，UI 明示）;
5. 服务端域名沿用 `zhenganhuo.com`，端点契约冻结于 S1-T01，变更需新 Goal。

### 3.4 版本契约

| 契约 | 变更 |
|---|---|
| `codexAccountingRevision` | **不动**（Codex 口径零变化） |
| 各新源 | 各自 `sourceAccountingRevision`，初值 1；口径修复才 bump |
| usage snapshot schema | minor bump：新增 `projects` 板块、`sources[]` 扩展；旧文件可读，缺字段按空处理 |
| settings schema | `showExperimentalAgentSources: Bool` → `experimentalSources: [String]`（按源开关）；legacy 迁移：旧值为 true 时**不**自动开启任何新源，保持等价的最小集（ZCode/Hermes/WorkBuddy），并提示用户 |
| sync payload schema | `syncPayloadVersion = 1`，冻结于 S1-T01 |

---

## 4. Goal G-A1：Provider 架构与 T1 数据源

### 4.1 激活条件

- `G-V2 = complete`（或用户批准并行，此时须先完成 V2-T04 Collection Core 拆分）；
- live baseline 与上游 Goal 产出一致；
- 用户确认本 contract。

### 4.2 Goal Contract

```yaml
goal_id: G-A1
contract_version: 1
goal_type: coding + artifact + test
launch_status: draft
launch_requested: false

outcome:
  must_be_true:
    - AgentSource 协议（detect → discover → parse → aggregate）与 AgentSourceRegistry 落地，现有六源行为与数字不变
    - T1 七源全部可用：Gemini CLI、Qwen Code、Kimi Code、OpenCode、Amp、Droid、Grok Build
    - 每个新源：默认关闭、开启后计入总量并标 experimental、有 fixture 测试、有 docs/agents/*.md
    - 设置新增「数据来源」卡：正式/实验分区、按源开关、三态状态（已采集/已安装无数据/未检测到）
    - 现有 Codex/Claude/CC Switch 的 totals 与 daily 逐字节不变（基准证明）
  release_scope: release_ready
  excluded_outcomes:
    - 不转正任何新源（转正走 B14）
    - 不做 T2 源、不做项目维度、不做同步
    - 不推送、不发布

constraints:
    - 不改变现有六源的 Token 计算结果
    - 新源只读 usage 字段；不读正文/代码/凭据
    - 单文件超 800 行的 Provider 必须拆分（避免重蹈 UsageCollector.swift 覆辙）
    - 新源解析失败不得影响其他源采集（源级隔离，失败进 SourceInfo 状态）
    - 保持旧 settings/usage snapshot 可读

boundaries:
  writable_repository: /Users/superhuang/Documents/黄叔知识库/03-工具与效率/token-usage-monitor
  prohibited_actions:
    - push、PR、merge、tag、GitHub Release、签名、公证
    - 读取真实用户目录之外的数据做开发验证（开发用 fixture，真机验证单独授权）

iteration:
  - 先协议与 Registry + 一个参考实现（Gemini CLI），评审后再批量铺其余六源
  - 每源独立提交候选、独立测试，禁止一次 diff 混多源
  - 任何现有源数字变化立即停止（同上游规则）

blocked:
  - V2-T04 拆分方向与 Provider 协议冲突，需要架构人工裁决
  - 任一 T1 源在本机无真实数据且拿不到授权样本（该源降级为 not_activated，不阻塞其余源）
```

### 4.3 任务 A1-T01：AgentSource 协议与 Registry

```yaml
id: A1-T01
title: 定义 AgentSource 生命周期协议并接入现有六源
priority: P0
activation: required
depends_on: []
estimated_minutes: 240
allowed_paths:
  - TokenStepSwift/Sources/TokenStepSwift/Services/AgentSources/
  - TokenStepSwift/Sources/TokenStepSwift/Services/UsageCollector.swift
  - TokenStepSwift/Tests/TokenStepSwiftTests/
verification:
  commands:
    - swift test --filter AgentSourceRegistry
    - swift test（全量，现有 39 测试零回归）
  evidence:
    - 协议文档注释（detect/discover/parse/aggregate 四阶段 + SourceInfo 映射）
    - 现有六源 totals/daily 等价性测试输出
stop_condition:
  - 协议接入导致现有源任何数字变化且 30 分钟内无法定位
```

设计要点：`AgentSource` 协议参考 ccusage adapter 五层与 codeburn "一个 Provider 一个文件"；`detect()` 返回 `.found(paths)/.installedNoData/.notInstalled`；Registry 负责扫描注册、按设置过滤。**不重写现有采集逻辑**，现有六源以适配器形式挂入（满足上游"禁止全量重构"边界）。

### 4.4 任务 A1-T02：数据来源设置卡与按源开关

```yaml
id: A1-T02
title: 设置页「数据来源」卡 + experimentalSources 按源开关 + legacy 迁移
priority: P0
activation: required
depends_on: [A1-T01]
estimated_minutes: 180
allowed_paths:
  - TokenStepSwift/Sources/TokenStepSwift/Views/Settings/
  - TokenStepSwift/Sources/TokenStepSwift/Models/UsageModels.swift
verification:
  commands:
    - swift test --filter SettingsMigration
    - script/build_swiftui_and_run.sh --no-launch
  evidence:
    - 原型 4 对应的 UI 截图
    - legacy 布尔→数组迁移测试（true 只映射旧三实验源，不开启任何新源）
```

### 4.5 任务 A1-T03～T05：T1 七源实现（每源一个候选提交）

```yaml
id: A1-T03
title: Gemini CLI Provider（参考实现）
priority: P0
activation: required
depends_on: [A1-T01]
estimated_minutes: 240
allowed_paths:
  - TokenStepSwift/Sources/TokenStepSwift/Services/AgentSources/Gemini/
  - TokenStepSwift/Tests/Fixtures/Gemini/
  - TokenStepSwift/Tests/TokenStepSwiftTests/GeminiSourceTests.swift
  - docs/agents/gemini-cli.md
verification:
  commands:
    - swift test --filter GeminiSource
```

关键口径（来源：codeburn `docs/providers/gemini.md` + vibe-usage 源表，须以 fixture 复核）：
- 路径 `~/.gemini/tmp/<project_hash>/chats/session-*.jsonl`（新）与 `session-*.json`（旧），按文件首字符 sniff 格式；递归子代理会话；
- **cached token 含在 promptTokenCount 内，需做减法**对齐 Anthropic 语义（TokenStep 的 input/cached/output 三分口径）；
- thoughts 按输出价计（成本仍走估算层）；
- 去重键 `sessionId`。

```yaml
id: A1-T04
title: Qwen Code + Kimi Code Provider
priority: P0
activation: required
depends_on: [A1-T03]
estimated_minutes: 300
allowed_paths:
  - TokenStepSwift/Sources/TokenStepSwift/Services/AgentSources/Qwen/
  - TokenStepSwift/Sources/TokenStepSwift/Services/AgentSources/Kimi/
  - TokenStepSwift/Tests/Fixtures/Qwen/ 与 Kimi/
  - docs/agents/qwen-code.md、docs/agents/kimi-code.md
verification:
  commands:
    - swift test --filter "QwenSource|KimiSource"
```

关键口径：Qwen `~/.qwen/tmp/`（旧 `~/.qwen/projects/` 并存）；Kimi 新 `~/.kimi-code/sessions/wd_*/session_*/agents/*/wire.jsonl` 读 `usage.record` 增量 + 旧 `~/.kimi/sessions/` **双目录合并**（kimi migrate 不带用量，两库永远并存）。

```yaml
id: A1-T05
title: OpenCode + Amp + Droid + Grok Build Provider
priority: P1
activation: required
depends_on: [A1-T03]
estimated_minutes: 360
allowed_paths:
  - TokenStepSwift/Sources/TokenStepSwift/Services/AgentSources/OpenCode|Amp|Droid|Grok/
  - 对应 Tests/Fixtures 与 docs/agents/*.md
verification:
  commands:
    - swift test --filter "OpenCodeSource|AmpSource|DroidSource|GrokSource"
```

关键口径：OpenCode `~/.local/share/opencode/opencode.db`（SQLite，`json_extract`，复用现有 SQLite wrapper 经验）；Amp `~/.local/share/amp/threads/`；Droid `~/.factory/sessions/`；Grok `~/.grok/sessions/<encoded-cwd>/<id>/updates.jsonl` 的 `turn_completed.usage`（含 per-model modelUsage 与 cache reads）。

### 4.6 任务 A1-T06：文档与基准

```yaml
id: A1-T06
title: docs/agents/*.md（每源路径/格式/坑）+ 新源采集基准
priority: P1
activation: required
depends_on: [A1-T03, A1-T04, A1-T05]
estimated_minutes: 180
allowed_paths:
  - docs/agents/
  - docs/AGENT_SUPPORT.md
  - docs/benchmarks/
verification:
  evidence:
    - 每源一文档（数据位置/存储格式/去重键/已知坑/版本差异），格式对齐 codeburn provider docs 惯例
    - 全源 cold/warm 采集基准（对齐 docs/benchmarks 惯例）
```

### 4.7 人工门 MG-AGENTS

T1 源合并前向用户展示：每源 fixture 测试结果、真实机器样本对比（如有授权）、设置卡截图、AGENT_SUPPORT 更新。`approve / reject / defer`。

### 4.8 G-A1 可复制 Goal

```text
/goal 以重新核验的 origin/main 为唯一基线（前提 G-V2=complete 或用户批准并行），完成 TokenStep Provider 架构与 T1 数据源：定义 AgentSource 四阶段协议（detect/discover/parse/aggregate）与 AgentSourceRegistry，现有六源以适配器挂入且 totals/daily 逐字节不变；实现 Gemini CLI、Qwen Code、Kimi Code、OpenCode、Amp、Droid、Grok Build 七个新源，全部默认关闭、只读 usage 字段、有 fixture 测试与 docs/agents/*.md；设置新增数据来源卡（正式/实验分区、按源开关、三态状态），legacy showExperimentalAgentSources 布尔迁移为按源数组且不自动开启任何新源；新源开启后计入总量并标 experimental。先协议加 Gemini 参考实现评审通过，再逐源独立提交。任何现有源数字变化立即停止。不得推送、发 PR、合并、打 tag、发布、签名或公证。所有 required tasks 与 MG-AGENTS 通过才完成；同一阻塞连续三轮停止并报告。
```

---

## 5. Goal G-A2：T2 数据源（IDE 与复杂格式）

### 5.1 激活条件

- `G-A1 = complete`；
- A2-T01 fixture 样本就绪（每源至少 1 份授权真实 schema，满足上游 B14 前半）。

### 5.2 Goal Contract（摘要）

```yaml
goal_id: G-A2
contract_version: 1
goal_type: coding + artifact + test
outcome:
  must_be_true:
    - GitHub Copilot、Cursor、Cline、Roo Code 四源可用（默认关闭 + experimental + fixture + docs）
    - Kiro、Antigravity 为 conditional：样本可得才激活
    - SQLite 类源（Cursor/Copilot OTel/Kiro）只读打开，不写、不锁库（WAL 只读模式）
  excluded_outcomes:
    - 不做 Windsurf、Trae IDE、Zed（样本渠道未建立，进 Backlog）
constraints:
  - IDE 数据库读取失败（锁定/损坏/schema 变更）必须降级为 notInstalled/failed 状态，不得崩溃不得阻塞其他源
  - Cursor 180 天界限、25 万 bubble 上限等上游 quirk 原样尊重并写入文档
iteration:
  - 先 A2-T01 样本池，后逐源实现；Copilot 与 Cursor 因多数据源优先级逻辑复杂，各自独立评审
blocked:
  - 任一源 schema 与公开情报不符且无真实样本（该源 not_activated）
```

### 5.3 任务清单

| ID | 任务 | 优先级 | estimated_minutes | 关键口径（来源：codeburn provider docs） |
|---|---|---|---|---|
| A2-T01 | T2 fixture 样本池与脱敏规范 | P0 | 180 | 每源 ≥1 份真实 schema；样本脱敏流程写入 docs/agents/README |
| A2-T02 | GitHub Copilot | P0 | 420 | 五位置：`~/.copilot/session-state/*/events.jsonl`、VS Code `chatSessions/*.jsonl`、`GitHub.copilot-chat/transcripts/`、OTel `agent-traces.db`（token 最全，**存在则优先**）、JetBrains nitrite `.db`；JSONL 仅 output token，OTel 才有四类完整拆分 |
| A2-T03 | Cursor | P0 | 360 | `state.vscdb`（bubbles 表为主 + agentKv 兜底；bubbleId/requestId 去重；仅回看 180 天；25 万 bubble 上限；指纹 = dbMtime+dbSize） |
| A2-T04 | Cline + Roo Code | P1 | 300 | 独立 `~/.cline/` + 各 VSCode-fork `globalStorage/saoudrizwan.claude-dev/`、`rooveterinaryinc.roo-cline/tasks/`（walk 所有 host：VSCode/Cursor/Windsurf 路径） |
| A2-T05 | Kiro + Antigravity | conditional | 420 | Kiro：`~/.kiro/sessions/cli/*.jsonl`（文本估算）→ `data.sqlite3` → credits 兜底，三级降级；Antigravity：`~/.gemini/antigravity/conversations/*.db` 离线解析 |
| A2-T06 | T2 文档 + 基准 + MG-AGENTS-2 人工门 | P1 | 120 | 同 A1-T06 惯例 |

### 5.4 G-A2 可复制 Goal

```text
/goal 前提 G-A1=complete 且样本池就绪。完成 TokenStep T2 数据源：实现 GitHub Copilot（五数据位置、OTel 优先）、Cursor（state.vscdb bubbles+agentKv、180 天与 25 万上限）、Cline、Roo Code 四个默认关闭的实验源，Kiro 与 Antigravity 视授权样本激活；SQLite 一律只读打开，失败降级不崩溃；每源 fixture 测试与 docs/agents/*.md；尊重上游 quirk 并写入文档。逐源独立提交候选并评审。不得推送、发 PR、合并、发布。所有 required tasks 与人工门通过才完成；样本不可得的源以 not_activated 记录证据。
```

---

## 6. Goal G-B1：项目维度

### 6.1 激活条件

- `G-A1 = complete`（协议层提供统一的项目提取钩子）；可与 G-A2 并行（需用户批准）。

### 6.2 Goal Contract

```yaml
goal_id: G-B1
contract_version: 1
goal_type: coding + artifact + product
outcome:
  must_be_true:
    - UsageSnapshot 新增 projects 板块；DailyUsage 带 projects 字段；schema minor bump 且旧文件可读
    - 今日页「今日项目」全宽卡（原型 2）、统计页「按项目」分布（原型 3）、Popover「今日路线」行（原型 1）
    - 分享卡（今日战报/节奏卡）带项目条目，仅目录名
    - 全链路（持久化/分享/导出/上行预留）只出现目录名，无完整路径（§3.2 五条规则全部成立）
    - PRIVACY.md、DATA_TRUST.md、AGENT_SUPPORT.md 同步修订
  excluded_outcomes:
    - 不做 task 维度；不做项目手动归组/重命名（v0.3 backlog）
constraints:
    - 各源项目提取失败不影响 token 计数（项目未知 → 未命名项目桶）
    - 快照体积增长 ≤ 15%（projects 只存聚合，不存明细）
iteration:
  - 先提取层 + 模型 + 迁移测试，后 UI；分享卡最后
blocked:
  - 某源 cwd 语义歧义（如远程容器路径）且无法用 fixture 裁决 → 该源项目列记未命名项目并记录
```

### 6.3 任务清单

| ID | 任务 | 优先级 | estimated_minutes | 要点 |
|---|---|---|---|---|
| B1-T01 | 项目提取与脱敏层 | P0 | 240 | 各源 cwd/session 路径 → 末级目录名；Codex rollout 目录名、Claude `~/.claude/projects/<编码路径>` 解码、Gemini `<project_hash>` 无法反解（记哈希短名或未命名——以 fixture 裁决）、CC Switch 行内 cwd |
| B1-T02 | 数据模型与迁移 | P0 | 180 | `ProjectUsage`（name/tokens/models/agents/lastUsed）；`DailyUsage.projects`；schema bump + 缺字段按空 |
| B1-T03 | UI 三处落地 | P0 | 300 | 今日项目卡（Top3+其他折叠，含"哪些 Agent 在此工作"）、统计按项目、Popover 今日路线 |
| B1-T04 | 分享卡项目条目 | P1 | 180 | 战报卡/节奏卡新增"今日路线"区段；目录名渲染；screenshot 回归 |
| B1-T05 | 隐私文档同步 | P0 | 120 | §3.2 规则写入 PRIVACY/DATA_TRUST；MG-PRIVACY-2 人工门 |

### 6.4 G-B1 可复制 Goal

```text
/goal 前提 G-A1=complete。完成 TokenStep 项目维度：建立各源项目提取与脱敏层（只保留末级目录名，完整路径不持久化不展示不分享），UsageSnapshot 新增 projects 板块并保持旧快照可读；落地今日项目全宽卡、统计页按项目分布、Popover 今日路线行；分享卡带项目条目（仅目录名）；同步 PRIVACY/DATA_TRUST/AGENT_SUPPORT。项目提取失败不影响 token 计数。先模型与迁移测试后 UI，分享卡最后。不得推送、发布。所有 required tasks、隐私人工门通过才完成。
```

---

## 7. Goal G-S1：多设备同步（正安火账号）

### 7.1 激活条件

- `G-B1 = complete`（上行 schema 含项目维度，一次定型）；
- `G-E0 = complete`（榜单 opt-in 身份体系已就绪，S1 复用其账号绑定与"关闭即零请求"测试模式）；
- **S1-T01 服务端契约冻结**（外部依赖：zhenganhuo 服务端需新增设备桶端点；本仓库只写客户端，服务端排期由用户另行安排——这是本 Goal 唯一外部阻塞）。

### 7.2 Goal Contract

```yaml
goal_id: G-S1
contract_version: 1
goal_type: coding + artifact + privacy-critical
outcome:
  must_be_true:
    - 默认关闭；关闭时零身份读取、零网络请求（对齐 E0-T03 测试规格，新增 DeviceSync 同规格测试）
    - 开启后：上行仅 聚合桶 + 设备名 + schema 版本；下行他机桶；增量水位续传
    - 合并层：默认只看本机；「今日/圆环合并」「历史/统计合并」两个独立开关（D2）；切回即时生效
    - 服务端不可达时本地一切照旧，仅 ☁ 状态变灰并显示最后成功时间
    - 解绑清除本机状态并向服务端发删除请求（best-effort，UI 明示）
  excluded_outcomes:
    - 不做榜单多人合计参赛（仅留 checkbox 占位，默认关）
    - 不做团队面板、不做云存储（WebDAV/S3）方案
constraints:
    - 金额永不上行；上行频率跟随现有采集节奏（不新增后台唤醒，受 EnergyRefreshPolicy 约束）
    - 上行 payload ≤ 256KB/次（gzip 后），超限分批
    - 合并只发生在展示层（MergeView），usage.json 本机仓库永远是权威源、永远只存本机数据
iteration:
  - 先契约冻结与 mock server 测试，再上行，再下行，最后合并层与 UI
  - 隐私测试与功能测试同 PRD 分开记录（上游 §9.2 惯例）
blocked:
  - 服务端端点未就绪或契约评审未过（本 Goal 整体 waiting_external）
  - 账号体系与 token-rank 身份的权限模型需要产品决策（同步开但榜单不开的用户路径）
```

### 7.3 任务清单

| ID | 任务 | 优先级 | estimated_minutes | 要点 |
|---|---|---|---|---|
| S1-T01 | 同步契约冻结（外部门） | P0 | 120 | `docs/sync/CONTRACT.md`：端点（注册设备/上行桶/拉取桶/删设备）、`syncPayloadVersion=1`、错误码、水位语义；**需正安火服务端确认，MG-SYNC 人工门** |
| S1-T02 | DeviceSyncService 上行 | P0 | 360 | 从 usage.json 派生聚合桶（天×小时×Agent×模型×项目目录名）；增量水位 `cache/sync-watermark.json`；gzip；失败退避 |
| S1-T03 | 下行与 MergeView | P0 | 300 | 拉取他机桶 → 只读 `remote-buckets.json`；MergeView 在 AppState 层求和，本机/合并口径切换；设备级隐藏 |
| S1-T04 | 设置卡与设备管理 UI | P0 | 240 | 原型 5 全部交互：绑定/设备列表/隐藏/双合并开关/榜单占位/立即同步/解绑；Popover 底栏 ☁ 状态 |
| S1-T05 | 隐私压力测试与文档 | P0 | 180 | 关闭零请求测试（对齐 AgentWorkRankServiceTests 模式）；PRIVACY.md 新增"多设备同步"章节；MG-PRIVACY-SYNC 人工门 |

### 7.4 G-S1 可复制 Goal

```text
/goal 前提 G-B1=complete 且 MG-SYNC 契约冻结获批。完成 TokenStep 多设备同步：DeviceSyncService 以正安火账号上行仅聚合桶（天×小时×Agent×模型×项目目录名的 token 计数，不含金额/正文/完整路径/凭据），增量水位续传；下行他机桶进只读存储；MergeView 默认只看本机，今日与历史合并为两个独立显式开关；默认关闭且关闭时零身份读取零网络请求（与榜单同规格测试）；服务端不可达本地照旧；解绑清除并发删除请求。先契约与 mock 测试再实现。金额永不上行，本机 usage.json 永远是权威源。不得推送、发布。所有 required tasks、MG-SYNC、MG-PRIVACY-SYNC 通过才完成；服务端未就绪则整体 waiting_external。
```

---

## 8. 条件 Backlog（v0.3 候选）

| ID | 候选能力 | 激活证据 | 边界 |
|---|---|---|---|
| C01 | task/任务维度 | 各源会话标题 schema 验证 ≥3 源 | 只存标题级元数据 |
| C02 | Windsurf / Trae IDE / Zed 源 | 授权样本各 1 份 | 同 B14 纪律 |
| C03 | 新源配额/限额适配 | 用户对某源配额需求成立 | 只做官方口径 |
| C04 | 榜单多设备合计参赛 | S1 稳定 + 榜单公平性方案 | 独立 opt-in |
| C05 | 项目手动归组/重命名 | 用户反馈混淆案例 ≥5 | 本机映射表，不上行 |
| C06 | MCP server / statusline / Homebrew | 维持上游 B05/B07/B12 边界 | — |

## 9. 人工门目录（新增）

| 门 | 触发点 | 决策内容 |
|---|---|---|
| MG-AGENTS / MG-AGENTS-2 | A1 / A2 合并前 | 每源 fixture 结果、真机样本对比、设置卡 UI、AGENT_SUPPORT 更新 |
| MG-PRIVACY-2 | B1 合并前 | §3.2 五条规则逐条证据（持久化/分享/导出无完整路径） |
| MG-SYNC | S1-T01 | 同步契约（端点/字段/删除语义）与服务端排期确认 |
| MG-PRIVACY-SYNC | S1 合并前 | 关闭零请求测试报告 + PRIVACY.md 修订 |

## 10. 证据与验收

继承上游 §9 全部惯例（五类验收分开记录；每次候选构建跑 `swift test` 全量 + 相关 shell 验收脚本）。新增：

1. **等价性**：A1/A2 期间现有源 totals/daily 逐字节不变（基准脚本进 docs/benchmarks）；
2. **隐私**：B1 的"全链路无完整路径"扫描脚本（grep 快照/缓存/导出产物）；S1 的关闭零请求测试；
3. **体积**：usage.json 与上行 payload 大小基准；
4. **真机**：每个转正候选按 AGENT_SUPPORT 纪律执行 2-3 台真机验证（转正仍走 B14，不在本 PRD 内）。
