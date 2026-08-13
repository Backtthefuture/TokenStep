# TokenStep vNext PRD：可信可见与采集可靠性

> 文档类型：Goal 目录与执行合同  
> 文档版本：2.0  
> 更新时间：2026-08-13  
> 当前状态：待确认，未启动任何 Goal  
> 当前范围：E0 工程与隐私前置门、V1 可信可见、V2 采集可靠性缺口  
> 基线快照：`origin/main = v0.1.48 = ef13871`。这只是编写 PRD 时的快照；每个 Goal 启动前必须重新核验 live checkout。

---

## 0. 执行摘要

### 0.1 一句话目标

让每天在 macOS 上重度使用 Codex 或 Claude Code 的个人用户，在 5 秒内判断：**TokenStep 当前展示的数据还能不能信。**

### 0.2 本轮唯一主任务

用户扫一眼菜单栏或浮层，就能回答：

1. 数据是否新鲜；
2. 今天的本地使用是否被完整记录；
3. 当前数字属于官方数据、本地记录、估算还是旧数据；
4. 采集或额度刷新失败时，界面展示的是最后一次成功数据，而不是伪装成实时值。

### 0.3 核心用户

- 每天持续使用 Codex 或 Claude Code；
- 已经或愿意让 TokenStep 常驻菜单栏；
- 关心使用节奏和额度，但不想研究日志、缓存和统计口径；
- 接受 local-first，默认不上传使用数据。

### 0.4 核心假设

如果 TokenStep 能把数据来源、新鲜度、失败状态和估算边界一眼说清楚，重度用户会持续常驻，并把它用于判断“今天的数据是否可信”，而不只是偶尔查看 Token 总数。

### 0.5 本轮不做

下列功能全部移出当前执行范围，仅保留在条件 Backlog：

- 远程动态定价；
- 本地 5 小时活动块、燃烧速率和预测；
- 配额消耗与时间进度对比；
- ZCode 转正式；
- FSEvents / DispatchSource 事件刷新；
- Sparkle、Homebrew cask；
- 主存储迁移 SQLite；
- 全量 SQLite C API 改造；
- 通知、Widget、公开 CLI；
- 活跃时长估算；
- 新 Agent 数据源；
- String Catalog；
- `UsageCollector.swift` 全量模块重构；
- 正式 GitHub Release。

这些条目不得因为出现在 Backlog 就自动创建任务或进入排期。

---

## 1. 现状基线与已知事实

### 1.1 编写时 Git 快照

| 项 | 已核验事实 |
|---|---|
| 当前 checkout | `main` |
| `HEAD` / `origin/main` | `ef13871` |
| 版本 | `v0.1.48` |
| tracked dirty | 无 |
| 未跟踪内容 | `.agents/`、`brand/logo-concepts/qiaomu-tokenstep-icon-options/`、本 PRD |
| checkpoint | `c540f98`，单次提交涉及 55 个路径，不是 12 个待提交文件 |

### 1.2 v0.1.48 已具备、禁止重复建设的能力

当前主线已经具备：

- Codex SQLite 增量缓存 `cache/codex-incremental.sqlite3`；
- Codex 文件追加检测、prefix fingerprint 与 byte-offset 尾读；
- 残缺尾行保护；
- `CodexIncrementalStore` staging transaction、提交与回滚；
- full-content validation 与缓存损坏自愈；
- collection checkpoint，无变化时跳过采集；
- Codex incremental 与 full reference 的比较入口；
- `EnergyRefreshPolicy`：AC 后台最短 15 分钟、电池或低电量最短 30 分钟，前台 tick 最长 60 秒。

因此，V2 不得再建立第二套 Codex offset、cursor、SQLite store 或 JSON checkpoint。任何增量开发必须先由基准或故障证据证明现有能力存在缺口。

### 1.3 当前必须解决的契约冲突

1. `TokenStepSettings.defaults.agentWorkRankVisibility = .automatic`，可能读取本地排行榜身份并请求榜单；`docs/PRIVACY.md` 却承诺未来公开排名应 opt-in 并单独确认。
2. 当前成本是本地 API 列表价粗略估算，不是实际账单，但 UI 与文档需要统一、常驻地表达这一边界。
3. 配额刷新失败时会保留旧值，但缺少完整的“失败 + 最后成功时间”状态模型。
4. 本地采集失败会保留上次快照，但来源级新鲜度、部分失败和从未成功等状态尚未形成统一产品语言。
5. `codexAccountingRevision`、SQLite schema version 与未来 pricing revision 是三个不同概念，不得混用。

---

## 2. Goal 模式执行总则

### 2.1 Goal 单位

本文是 **Goal 目录**，不是一次性自动执行整个路线图的授权。

- 同一时间只启动一个 Active Goal。
- 推荐顺序：`G-E0` → `G-V1` → `G-V2`。
- 后续 Goal 只有在前置 Goal 以证据完成、且用户确认最新版 Goal contract 后才能启动。
- PRD 获批不等于 Goal 已启动。每个 Goal 启动前必须展示完整 `/goal`，并收到明确的“开始”或“确认并启动 Goal vN”。
- 未明确给出 token budget 时，不为 Goal 自动设置预算。
- `estimated_minutes` 只用于排期，不是 token budget，也不是完成证据。
- Goal 启动不扩大权限。推送、发 PR、合并、打 tag、发布、使用签名凭据、删除 worktree、删除历史或上传数据都需要独立授权。

### 2.2 通用完成规则

一个 Goal 只有同时满足以下条件才可标记 `complete`：

1. Outcome 中所有必须为真的结果已经成立；
2. 所有 Required Task 均为 `verified`；
3. Conditional Task 已验证，或因触发条件未成立而以证据标记 `not_activated`；
4. 所有适用的自动测试、数据等价性、性能门和人工门均通过；
5. 没有未解决的 P0；
6. 文档与实现一致；
7. 没有剩余必要工作。

以下情况都不等于完成：代码写完、任务列表跑完、预算将尽、manual gate 未决、测试无法运行、只生成报告但未满足 Outcome。

### 2.3 通用迭代策略

每一轮必须：

1. 先重新核验 live baseline 和工作区状态；
2. 选择一个最小、可回滚、可验证的主要变量；
3. 记录假设、改动、命令、结果、结论和下一路径；
4. 失败后根据新证据处理最高影响缺口，不盲目重复同一命令；
5. 不通过扩大范围、降低测试强度、修改阈值或改写验收定义来换取通过；
6. Conditional Task 先验证激活条件，条件不成立就保持 `not_activated`。

### 2.4 通用阻塞停止条件

只有在以下条件同时成立时，Goal 才可标记 `blocked`：

- 同一阻塞条件连续出现至少三个 Goal turn；
- 已没有安全、范围内、能产生新证据的替代路径；
- 继续需要新的用户选择、权限、凭据或外部状态变化。

阻塞报告必须包含：

- 已完成且已验证的部分；
- 未完成项；
- 三轮尝试及去敏后的证据；
- 仍未被破坏的约束；
- 唯一或最小的解锁输入。

困难、耗时、暂时失败或预算接近耗尽，都不自动构成阻塞。

### 2.5 通用禁止事项

- 禁止完整 merge 或 cherry-pick `c540f98`；
- 禁止把 PRD 中记录的 Git 快照当作执行时事实；
- 禁止把“里程碑完成”解释为“必须发布”；
- 禁止未经当次明确授权删除旧 worktree；
- 禁止重建 v0.1.48 已有的 Codex 增量引擎；
- 禁止读取、记录或输出 prompt、回复正文、代码正文、凭据或私钥；
- 禁止新增默认开启的网络请求或数据目录扫描；
- 禁止把官方额度、本地记录、估算和过期值混称；
- 禁止通过修改本 Goal 之外的模块顺带重构；
- 禁止在 manual gate 未通过时自动继续或把 Goal 标记完成。

---

## 3. 全局数据与信任契约

### 3.1 用户可见的四类证据状态

| 状态 | 定义 | UI 最低要求 |
|---|---|---|
| 官方数据 | 服务商接口或本机官方 rate-limit 接口返回 | 显示来源、最后成功时间；失败时显示旧数据状态 |
| 本地记录 | TokenStep 从本机日志或数据库读取的使用记录 | 显示最后成功扫描时间、覆盖来源和部分失败 |
| 估算 | 依据规则、模型价格或统计公式计算 | 数字附近常驻“估算”及口径；不得称为账单或官方额度 |
| 已过期 | 最近一次尝试失败，当前展示最后成功值 | 同时显示失败状态、最后成功时间和数据年龄 |

### 3.2 强制业务规则

1. 官方额度获取失败时，不得用本地 5 小时活动块替代。
2. 从未成功获取时显示“暂无数据”或“等待首次同步”，不得显示为 0。
3. 部分来源失败不能被总状态“成功”掩盖。
4. 采集失败不得覆盖最后一次完整快照。
5. 错误文案和诊断不得暴露本地敏感路径、prompt、代码或会话正文。
6. 成本统一表达为“按内置 API 列表价估算，不代表订阅或实际账单”。
7. 新增持久化字段必须使用兼容解码，旧 `usage.json` 和 `settings.json` 必须可读。
8. 默认关闭的功能在关闭时必须保持零网络请求、零身份读取、零额外数据目录扫描。

### 3.3 版本契约

| 版本 | 作用 | 何时变化 |
|---|---|---|
| accounting revision | 某来源的 Token 计算语义 | 该来源的 Token 结果可能变化时 |
| storage schema version | SQLite / JSON 的物理存储结构 | 表、字段或编码结构迁移时 |
| pricing snapshot revision | 估价数据集与日期 | 价格快照变化时 |

当前 Goal 不实施远程定价，但 E0 必须把三者写入 `docs/DATA_TRUST.md`，并确认后续不得用 `codexAccountingRevision` 为其他来源或价格变化兜底。

---

## 4. Goal G-E0：工程与隐私前置门

### 4.1 Goal Contract

```yaml
goal_id: G-E0
contract_version: 1
goal_type: migration/refactor + audit
launch_status: draft
launch_requested: false

outcome:
  must_be_true:
    - 执行时核验的 origin/main 是唯一代码基线，c540f98 仅作为只读差异来源；若 origin/main 已不再是 ef13871，则先记录新基线与差异并停止等待人工确认
    - 只移植经 allowlist 批准且能独立验证的 Helper 事务能力
    - 新安装默认不读取排行榜身份、不请求排行榜接口、不显示排行榜
    - PRIVACY、DATA_TRUST、AGENT_SUPPORT 与当前运行行为一致
    - 形成可重复的 v0.1.48 采集正确性与性能基准
  release_scope: release_ready
  excluded_outcomes:
    - 不推送、不创建 PR、不合并、不打 tag、不发布
    - 不删除旧 worktree
    - 不实施 V1/V2 产品功能

constraints:
  - 不改变 Codex、Claude Code、CC Switch、Hermes、WorkBuddy 的 Token 计算结果
  - 不新增网络能力
  - 不读取会话正文、代码或凭据
  - 保持旧 settings 与 usage snapshot 可读取
  - tracked scope 必须符合 allowlist

boundaries:
  writable_repository: /Users/superhuang/Documents/黄叔知识库/03-工具与效率/token-usage-monitor
  baseline: 执行时重新核验的 origin/main，预期为 ef13871
  read_only_ref: c540f98
  prohibited_actions:
    - 完整 merge/cherry-pick c540f98
    - push、PR、merge、tag、GitHub Release
    - 签名、公证、读取签名凭据
    - 删除 worktree、历史、用户数据或缓存

iteration:
  - 先产出 live baseline 和 55 路径裁决证据，再做任何代码移植
  - Helper 能力必须按最小 patch 重新实现或逐 hunk 移植
  - 隐私修复与 Helper 移植分开提交候选、分开验证
  - 任何统计结果变化先停止并定位，不以 accounting bump 掩盖

blocked:
  - live baseline 不再是 ef13871，或与 PRD 快照存在未解释差异，需要 MG-BASELINE 人工确认
  - Helper 独有能力无法从 checkpoint 与重复实现中可靠分离
  - 隐私默认行为与现有用户迁移策略需要新的产品决策
```

### 4.2 任务 E0-T01：执行前基线与 55 路径裁决

```yaml
id: E0-T01
title: 核验 live baseline 并产出 checkpoint 路径裁决
priority: P0
activation: required
depends_on: []
estimated_minutes: 120
allowed_paths:
  - docs/M0_RECONCILIATION.md
verification:
  commands:
    - git status --short --branch
    - git rev-parse HEAD origin/main c540f98
    - git show --format= --name-only c540f98
    - git diff --stat origin/main...c540f98
  evidence:
    - docs/M0_RECONCILIATION.md
stop_condition:
  - 任一 ref 不存在或工作区状态无法解释时停止代码移植
```

`docs/M0_RECONCILIATION.md` 必须：

- 覆盖 `c540f98` 的全部 55 个路径；
- 分别标记 `main 已有`、`候选移植`、`明确排除`；
- 对每个候选移植路径写清具体 hunk、价值、风险和验收；
- 明确排除 `.agents/`、品牌资产、旧 PRD、`skills-lock.json` 和重复的 WorkBuddy/能耗实现；
- 记录当前未跟踪文件归属，禁止误入候选 diff。

### 4.3 人工门 MG-BASELINE

执行任何代码移植前，向用户展示：live `HEAD`、`origin/main`、工作区状态、checkpoint 55 路径分类与拟议 allowlist。人工决策为 `approve / reject / defer`。

- `approve`：只授权按 allowlist 进入 E0-T02/E0-T03；
- `reject`：返回 E0-T01 修订裁决；
- `defer`：Goal 状态为 `waiting_manual`；
- 本门不授权 push、PR、发布、删除或任何 allowlist 外改动。

### 4.4 任务 E0-T02：选择性移植 Helper 事务能力

```yaml
id: E0-T02
title: 从干净基线选择性移植 Helper 事务安装能力
priority: P0
activation: required
depends_on:
  - E0-T01: verified
  - MG-BASELINE: approve
estimated_minutes: 300
allowed_paths:
  - TokenStepSwift/Sources/TokenStepHelper/main.swift
  - script/test_update_helper_transaction.sh
  - script/build_swiftui_and_run.sh
  - .github/workflows/ci.yml
  - docs/M0_RECONCILIATION.md
stop_condition:
  - Helper patch 不能与 checkpoint 其余 54 路径解耦
  - 事务测试需要改变 Token 会计或用户数据
```

验收：

- `git diff --name-only <baseline>...HEAD` 只包含裁决表批准的路径；
- 必须新增并通过 `./script/test_update_helper_transaction.sh`；
- 故障注入覆盖：下载/解压失败、替换前失败、替换后启动失败、回滚成功；
- 失败后原 App 仍存在且可执行；
- 不改变 Helper `collect` stdout 的 `CollectionRunOutcome` 协议；
- 不引入 `.agents/`、品牌资产、旧 PRD、`skills-lock.json` 或 checkpoint 的旧采集实现。

### 4.5 任务 E0-T03：排行榜默认关闭与隐私一致性

```yaml
id: E0-T03
title: 让排行榜身份读取和网络请求严格 opt-in
priority: P0
activation: required
depends_on:
  - E0-T01: verified
  - MG-BASELINE: approve
estimated_minutes: 240
allowed_paths:
  - TokenStepSwift/Sources/TokenStepSwift/Models/UsageModels.swift
  - TokenStepSwift/Sources/TokenStepSwift/Stores/AppState.swift
  - TokenStepSwift/Sources/TokenStepSwift/Services/TokenRankService.swift
  - TokenStepSwift/Sources/TokenStepSwift/Views/Settings/
  - TokenStepSwift/Tests/
  - docs/PRIVACY.md
  - docs/DATA_TRUST.md
  - docs/AGENT_SUPPORT.md
manual_gate: MG-PRIVACY
```

业务规则：

- 新安装默认 `.hidden`；
- 未显式开启时：本地身份读取 0 次、榜单请求 0 次、排行榜卡片不显示；
- 用户显式开启后才允许读取白名单身份字段并请求公开排行榜；
- 关闭后立即清空内存中的身份、榜单和错误状态；
- 旧设置迁移不得把不存在的 legacy 字段自动迁成 `.automatic`；
- 不上传 TokenStep 本地统计或生成待上传 payload。

验收：

- 自动测试注入 identity loader 与 leaderboard client，断言默认启动零读取、零请求；
- 显式开启后恰好按现有刷新策略读取/请求；
- 再次关闭后状态清空且后续刷新不再读取/请求；
- `docs/PRIVACY.md`、PrivacyView 和设置页文案与测试行为一致；
- 人工门 `MG-PRIVACY` 审核默认状态、开启说明和关闭行为。

### 4.6 任务 E0-T04：冻结数据契约与 v0.1.48 基准

```yaml
id: E0-T04
title: 建立可重复的数据等价性与性能基准
priority: P0
activation: required
depends_on:
  - E0-T01: verified
estimated_minutes: 300
allowed_paths:
  - script/benchmark_energy_efficiency.sh
  - TokenStepSwift/Tests/Fixtures/EnergyEfficiencyBenchmark.swift
  - TokenStepSwift/Tests/
  - docs/benchmarks/
  - docs/DATA_TRUST.md
```

固定 corpus 至少覆盖：

- Codex cold scan；
- Codex 无变化 warm scan；
- Codex append scan；
- Claude cold scan；
- Claude 无变化 warm scan；
- Claude append 后 scan；
- 损坏缓存、截断行和来源在采集中变化。

每组记录：

- commit、macOS、硬件；
- corpus hash、文件数和字节数；
- cold 1 次、warm 至少 5 次；
- median、p95、max RSS、logical write bytes；
- 对 Codex：incremental 与 full rebuild 的 totals、daily、model、tool、source diagnostics 等价性；
- 对 Claude：当前 full-scan 的 cold / 无变化 / append 基线。E0 不虚构 Claude incremental 对照；只有 V2-T02 被激活并实现后才要求 incremental 与 full rebuild 等价。

强制结论分类：`v0.1.48 已具备`、`有证据的缺口`、`无须开发`。后续 V2 任务只能由“有证据的缺口”激活。

### 4.7 E0 自动验收

```bash
swift test --package-path TokenStepSwift
./script/test_ccswitch_proxy_collector.sh
./script/test_codex_cumulative_collector.sh
./script/test_usage_recalibration_migration.sh
./script/test_update_helper_transaction.sh
./script/benchmark_energy_efficiency.sh
./script/build_swiftui_and_run.sh --no-launch
python3 script/check_localization.py
python3 script/check_language_refresh.py
```

若某命令因已知环境问题无法运行，不得默认为通过；必须记录原始错误、使用的替代证据及尚未验证的 gate。

### 4.8 E0 人工门 MG-PRIVACY

审核材料：

- `docs/M0_RECONCILIATION.md`；
- `docs/DATA_TRUST.md`；
- 更新后的 `docs/PRIVACY.md`；
- 默认关闭、显式开启、再次关闭三个状态的截图或录屏；
- 自动测试报告。

人工决策：`approve / reject / defer`。通过仅授权进入 V1，不授权 push、PR、发布或清理。

### 4.9 G-E0 可复制 Goal

```text
/goal 以执行时重新核验并经 MG-BASELINE 批准的 origin/main 为唯一基线，完成 TokenStep 工程与隐私前置门：审计 c540f98 的全部 55 个路径，禁止完整 merge 或 cherry-pick，只按批准的 allowlist 选择性移植并验证 Helper 事务安装能力；让排行榜在新安装和未显式开启时保持零身份读取、零网络请求、零卡片展示，关闭后清空状态；同步 PRIVACY、DATA_TRUST、AGENT_SUPPORT；建立可重复的 Codex/Claude cold、warm、append、损坏和中断基准，证明 incremental 与 full rebuild 的 totals、daily、model、tool 和 source diagnostics 等价。若 origin/main 不再是 PRD 快照 ef13871，先记录差异并等待 MG-BASELINE，不自行沿用旧基线。保持现有 Token 会计结果、旧数据兼容和 local-first，不读取会话正文、代码或凭据，不新增网络能力。每轮先核验 live baseline，只改变一个主要变量并记录假设、改动、命令、结果和下一路径。不得推送、发 PR、合并、打 tag、发布、签名、公证或删除 worktree。只有所有 required tasks、自动验收、MG-BASELINE 和 MG-PRIVACY 人工门通过且无未解决 P0 时才完成；若同一阻塞连续三轮且无安全替代路径，停止并报告三轮证据、未完成项和最小解锁输入。
```

---

## 5. Goal G-V1：可信可见

### 5.1 激活条件

- `G-E0 = complete`；
- `MG-PRIVACY = approve`；
- 用户明确确认 G-V1 最新 contract；
- live baseline 与 E0 产出的候选提交一致。

### 5.2 Goal Contract

```yaml
goal_id: G-V1
contract_version: 1
goal_type: coding + artifact + product validation
launch_status: draft
launch_requested: false

outcome:
  must_be_true:
    - 用户可在 5 秒内区分官方数据、本地记录、估算和已过期值
    - 本地采集或额度刷新失败时保留最后成功值并显示失败与数据年龄
    - 从未成功、全部成功和部分失败均有不同且一致的状态
    - 成本文案明确是 API 列表价估算而非账单
    - 至少 8/10 目标 Beta 用户通过理解测试
  release_scope: release_ready
  excluded_outcomes:
    - 不新增远程定价、本地 5h block、配额预测、通知或 Widget
    - 不改 Token 会计口径
    - 不发布正式版本

constraints:
  - 不新增静默遥测
  - 不新增默认网络请求
  - 不用新卡片堆叠代替信息层级设计
  - 失败不得覆盖最后完整快照
  - 旧 snapshot/settings 必须兼容

iteration:
  - 先建立状态模型和 fixtures，再修改 UI
  - 用户理解度不足时先简化标签和层级，不增加功能
  - 状态持久化只保存必要元数据，不保存敏感路径或正文

blocked:
  - 状态模型无法区分最后尝试与最后成功且需要数据 schema 产品决策
  - Beta 招募或人工测试需要用户提供参与者
```

### 5.3 任务 V1-T01：统一新鲜度与失败状态模型

```yaml
id: V1-T01
title: 建立本地采集与官方额度的统一状态模型
priority: P0
activation: required
depends_on:
  - G-E0: complete
estimated_minutes: 360
```

状态模型至少表达：

- `neverSucceeded`；
- `fresh(lastSucceededAt)`；
- `aging(lastSucceededAt)`；
- `stale(lastSucceededAt, lastAttemptedAt, errorKind)`；
- `partial(lastSucceededAt, successfulSources, failedSources)`；
- `disabled`。

默认时间规则：

- `fresh`：距离最后成功时间不超过当前能力的正常刷新 TTL；本地采集采用用户设置的 refresh interval，并受现有 EnergyRefreshPolicy 约束；额度采用现有 quota TTL；
- `aging`：已超过正常 TTL，但最近一次尝试没有明确失败；
- `stale`：最近一次尝试失败且仍展示旧值，或数据年龄超过正常 TTL 的 2 倍；
- `partial`：同一刷新周期内至少一个已启用来源成功、至少一个已启用来源失败；
- 具体阈值必须集中在可测试的 policy 中，不得散落为 UI 魔法数字。

实现要求：

- 区分 `lastAttemptedAt` 与 `lastSucceededAt`；
- 配额的 Codex 与 Claude 成功/失败分别记录，不能互相掩盖；
- 本地采集来源级失败保留现有 source diagnostics；
- `UsageSnapshot` 新字段必须 `decodeIfPresent` 带默认值；
- 只持久化状态所需时间和分类，不保存敏感路径或原始错误正文；
- 用户可见错误使用安全分类，详细诊断仅保留去敏信息。

验收 fixtures：首次启动、刚成功、数据老化、请求失败有旧值、采集失败有旧快照、Codex 成功但 Claude 失败、部分本地源失败、功能关闭、旧快照读取。

### 5.4 任务 V1-T02：可信标签与现有界面整合

```yaml
id: V1-T02
title: 在现有信息层级中展示来源、新鲜度和估算边界
priority: P0
activation: required
depends_on:
  - V1-T01: verified
estimated_minutes: 300
manual_gate: MG-UX
```

UI 要求：

- Popover 顶部或相关现有卡片显示最后成功时间；
- 有旧值的失败状态必须同时显示“同步失败”与最后成功时间；
- 从未成功显示“暂无数据”，不显示 0；
- Codex/Claude 额度分别显示状态，部分失败不被隐藏；
- 成本附近显示“API 列表价估算”，tooltip 或说明补充“不代表订阅或实际账单”；
- 不新增与现有信息重复的大卡片；
- 浮层、主窗口、设置隐私页和诊断文档使用同一套术语；
- 三语本地化完整，切换后即时刷新。

人工门 `MG-UX` 审核全部 fixture 状态的截图或可运行候选。

### 5.5 任务 V1-T03：Trust 与 Privacy 同步

```yaml
id: V1-T03
title: 让 DATA_TRUST、PRIVACY、AGENT_SUPPORT 与 UI 术语一致
priority: P0
activation: required
depends_on:
  - V1-T01: verified
  - V1-T02: verified
estimated_minutes: 180
```

`docs/DATA_TRUST.md` 至少覆盖：

- 四类证据状态；
- 每个正式/实验源的数据来源、统计口径和已知边界；
- source diagnostics 解释；
- accounting/storage/pricing revision 的区别；
- 成本估算声明；
- 本地数据、网络请求和保存期限；
- “解决可见性，不提供结算级账单”的定位。

同时修正 `docs/AGENT_SUPPORT.md` 与实现不一致的状态，不能把只有实现、尚未达到真实机器门槛的来源写成正式支持。

### 5.6 任务 V1-T04：10 人理解度测试

```yaml
id: V1-T04
title: 验证用户能否在 5 秒内判断数据是否可信
priority: P0
activation: required
depends_on:
  - V1-T02: verified
  - V1-T03: verified
estimated_minutes: manual
manual_gate: MG-BETA
```

方法：

- 10 名符合核心用户描述的 Beta 用户；
- 使用固定截图任务 + 至少一次真实使用后的简短访谈；
- 同一组截图随机排序；计时从截图完整出现开始，5 秒到时立即记录第一答案；
- 不新增静默遥测；
- 只记录题目答案和产品反馈，不收集原始使用日志、身份或会话内容。

通过条件：

- 至少 8/10 在 5 秒内正确指出官方数据、本地记录、估算、是否过期；
- 至少 7/10 认为比 v0.1.48 更容易判断数据是否可信；
- 0 人把本地估算误认为官方额度或实际账单。

若不足 8/10：返回 V1-T02，先简化标签和层级，再复测；不得通过增加新卡片绕过。

### 5.7 V1 自动验收

运行 E0 全部自动验收，并增加：

- 状态模型单测；
- 旧 snapshot/settings 兼容测试；
- Codex/Claude quota 独立失败 fixtures；
- 本地采集部分失败 fixtures；
- 三语状态渲染或截图 fixture。

### 5.8 G-V1 可复制 Goal

```text
/goal 在已完成并验收的 G-E0 基线上，让 TokenStep 用户能在 5 秒内区分官方数据、本地记录、估算和已过期值：建立区分最后尝试与最后成功的统一状态模型，覆盖首次同步、正常、老化、失败有旧值、部分来源失败和关闭状态；本地采集或 Codex/Claude 额度刷新失败时保留最后成功值并同时显示失败与数据年龄；把成本统一标为 API 列表价估算、不代表订阅或实际账单；同步浮层、主窗口、设置页、PRIVACY、DATA_TRUST 和 AGENT_SUPPORT。保持现有 Token 会计口径、旧数据兼容和 local-first，不新增远程定价、本地 5h block、配额预测、通知、Widget、静默遥测或默认网络请求。先建状态 fixtures 再改 UI；若用户理解度不足，先简化标签和层级而非增加新卡片。只有自动验收、MG-UX 通过，且 10 名目标 Beta 用户中至少 8 人能在 5 秒内正确判断四类状态、至少 7 人认为更易理解、无人把估算当官方额度或账单时才完成。不得推送、发布或删除 worktree；若同一阻塞连续三轮且无安全替代路径，报告证据和最小解锁输入。
```

---

## 6. Goal G-V2：采集可靠性缺口

### 6.1 激活条件

- `G-V1 = complete`；
- E0 基准报告存在；
- 至少一个 Conditional Task 的量化触发条件成立；
- 用户确认本 Goal 最新 contract。

如果所有 Conditional Task 均未触发，G-V2 不启动；这视为正确停止，不是失败。

### 6.2 Goal Contract

```yaml
goal_id: G-V2
contract_version: 1
goal_type: performance + coding
launch_status: draft
launch_requested: false

outcome:
  must_be_true:
    - 对所有被激活的采集缺口，incremental 与 full rebuild 零差异
    - 不产生静默丢失、重复计数或半完成快照
    - 失败时最后完整快照始终可读并明确标记
    - 未被证据激活的优化保持不实施
  release_scope: release_ready
  excluded_outcomes:
    - 不重写现有 Codex incremental store
    - 不做主存储 SQLite、全量模块重构或新数据源
    - 不发布正式版本

constraints:
  - totals、daily、model、tool、source diagnostics 与 full rebuild 等价
  - cold scan、max RSS、logical writes 不劣化超过 10%
  - 不降低现有 staging transaction 原子性
  - 不读取或上传原始正文

iteration:
  - 先测触发条件，再激活具体任务
  - 一次只优化一个来源或一个故障模式
  - 每轮执行增量/全量黄金对账和故障注入

blocked:
  - 无法构造合法 full reference
  - 优化无法保持等价性或原子性且无安全替代方案
  - 真实 Beta 验收需要用户提供机器与授权
```

### 6.3 任务 V2-T01：v0.1.48 能力矩阵审计

```yaml
id: V2-T01
title: 证明现有 Codex 增量路径哪些已达标、哪些仍有缺口
priority: P0
activation: required
depends_on:
  - G-V1: complete
estimated_minutes: 180
allowed_paths:
  - docs/benchmarks/
  - docs/COLLECTION_GAP_AUDIT.md
  - tests and benchmark fixtures only when evidence is missing
```

能力矩阵必须覆盖：byte-offset 尾读、残缺 JSONL 尾行、文件截断/替换、prefix/full fingerprint、parent/child session、staging 原子性、缓存损坏重建、collection checkpoint、summary record 粒度、Helper 120 秒超时。

每项只能标记：

- `verified_existing`；
- `verified_gap`；
- `not_relevant`；
- `unverified`。

没有证据不得写“已完成”。已达标能力不得建立第二套实现。

### 6.4 任务 V2-T02：Claude 尾部增量读取

```yaml
id: V2-T02
title: 仅在真实瓶颈成立时实现 Claude JSONL 尾部增量
priority: P1
activation: conditional
depends_on:
  - V2-T01: verified
activation_condition:
  - 固定 corpus 的 Claude 无变化或 append warm scan p95 超过 2 秒，或占完整采集 p95 的 50% 以上
  - 且 7 天 Beta 至少出现 3 次用户可感知的 Claude 采集延迟或 Helper 超时
estimated_minutes: 480
```

若任一触发条件不成立，状态为 `not_activated`。

验收：

- append scan 与 full rebuild 的记录数、Token、日期、模型完全一致；
- 截断、替换、inode 变化时退化为全量；
- 残缺尾行不提前计入，补全后只计一次；
- 缓存版本不兼容或损坏时安全重建；
- cold scan、max RSS、logical writes 相对 E0 基线不劣化超过 10%；
- 不保存消息正文。

### 6.5 任务 V2-T03：Helper 跨轮恢复

```yaml
id: V2-T03
title: 仅在真实中断问题成立时实现完整代际的跨轮恢复
priority: P1
activation: conditional
depends_on:
  - V2-T01: verified
activation_condition:
  - E0 故障注入或 7 天 Beta 出现 Helper 超时、进程终止或大目录反复全扫
  - 且该问题无法通过缩短单次工作量或现有 Codex store 安全解决
estimated_minutes: 600
```

设计约束：

- 未完成 generation 不得被 App 读取；
- 最后完整快照始终可用；
- checkpoint 带 generation、schema version、accounting revision 与 completeness manifest；
- 不把“每 25 文件写一次旧 JSON 缓存”作为默认方案；
- 不破坏当前 staging transaction 的原子性。

验收：在固定位置强制 `SIGTERM` / `SIGKILL` 后，当前完整快照仍可读；下次运行可以继续或安全重建；最终与 full rebuild 零差异；无重复、无半成品发布。

如果实现复杂度会降低原子性或没有真实触发证据，则取消该任务并保留整轮回滚。

### 6.6 任务 V2-T04：最小 Collection Core 拆分

```yaml
id: V2-T04
title: 只为已激活任务做必要的共享编译边界调整
priority: P1
activation: conditional
depends_on:
  - V2-T02 or V2-T03: activated
activation_condition:
  - 已激活任务无法在不造成明显重复或 Helper 漏编译的情况下安全实现
estimated_minutes: 240
```

只允许最小拆分。必须同时更新：

- 主 App 编译源；
- Helper 的硬编码 source manifest；
- fixture 和 benchmark 编译入口。

不得以本任务启动 `UsageCollector.swift` 全量重构。测试 diff 为零不是硬指标；行为与数据等价才是硬指标。

### 6.7 V2 可靠性验收

自动门：

- E0/V1 全部自动验收继续通过；
- incremental 与 full rebuild 黄金对账零差异；
- 缓存损坏、截断行、文件替换、来源变化、SIGTERM、SIGKILL 故障注入；
- 旧 snapshot/cache/schema 兼容；
- cold scan、max RSS、logical writes 不劣化超过 10%；
- warm scan p95 不劣于 E0 基线，已激活性能任务必须达到其触发问题对应的改善目标。

人工 soak：

- 至少 3 台经明确授权的真实 Beta Mac；
- 连续 7 天；
- 原始日志和消息正文不离开本机；
- 每台只提交去敏的 totals/delta/status/benchmark 结果。

通过条件：

- incremental 与 full rebuild 零差异；
- 零静默数据丢失；
- 零重复计数；
- 零不可恢复缓存损坏；
- 失败时 100% 保留并标记最后完整快照。

### 6.8 G-V2 可复制 Goal

```text
/goal 在已完成的 G-V1 与 E0 基准之上，只修复被量化证据激活的 TokenStep 采集可靠性缺口：先审计并证明 v0.1.48 现有 Codex byte-offset 尾读、残缺行保护、fingerprint、SQLite staging、缓存自愈和 collection checkpoint，不得建立第二套 Codex 增量引擎；只有当固定基准和 7 天 Beta 同时证明 Claude warm scan 构成真实瓶颈时，才实现 Claude 尾读；只有真实出现 Helper 超时或中断且现有机制无法安全解决时，才设计带 generation、schema/accounting revision 和 completeness manifest 的跨轮恢复，未完成代不得对 App 可见。保持 incremental 与 full rebuild 的 totals、daily、model、tool、source diagnostics 零差异，零静默丢失、零重复、最后完整快照始终可读，cold scan、max RSS 和 logical writes 不劣化超过 10%。未满足触发条件的任务必须标记 not_activated，不以排期替代证据。不读取或上传正文，不做主存储迁移、新数据源、全量重构、推送或发布。每轮只改变一个来源或故障模式并执行黄金对账；只有自动故障注入和至少 3 台真实 Beta Mac 连续 7 天 soak 全部通过时才完成。连续三轮遇到相同阻塞且无安全替代路径时，报告尝试、证据和最小解锁输入。
```

---

## 7. 条件 Backlog

| ID | 候选能力 | 激活前必须具备的证据 | 关键边界 |
|---|---|---|---|
| B01 | 远程价格更新 | 用户明确需要跨新模型估价；内置快照已造成可量化错误 | 独立开关、默认关闭；签名 manifest；pricing revision；不得称账单 |
| B02 | 本地 5h 活动块 | 至少 6/10 Beta 用户需要本地节奏预测 | 只能叫本地估算，不得替代官方额度；固定窗口规则无歧义 |
| B03 | 配额消耗 vs 时间 | 官方窗口起点可可靠得到或明确标为推导 | 只使用官方额度；推导值标估算 |
| B04 | ZCode 转正式 | 至少 3 台机器、2 个版本、与原生统计逐日对账 | 独立 source accounting revision |
| B05 | 事件刷新 | 7 天 Beta 证明刷新延迟是主要问题 | 先做 FSEvents spike；不破坏电池地板 |
| B06 | Sparkle | 有真实更新失败率或维护成本证据 | 独立于 Homebrew；签名、appcast、回滚单独 Goal |
| B07 | Homebrew cask | 用户获取渠道需求成立 | 独立增长 Goal，不与更新框架绑定 |
| B08 | 主存储 SQLite | JSON 读写成为量化瓶颈 | 单一事实源；按天/historyDays 保留；隐私迁移单独 Goal |
| B09 | SQLite C API 提取 | 外部 DB 子进程成为瓶颈或新任务必需 | 复用现有 Codex wrapper；typed API；busy timeout |
| B10 | 通知 | 配额守卫或习惯方向已通过用户验证 | 用户主动授权；跨重启去重；默认全关 |
| B11 | Widget | Xcode/XcodeGen、App Group、签名链已解决 | 最小 WidgetSnapshot；不直读主库；不承诺 1 分钟 SLA |
| B12 | Helper CLI | 有明确终端用户和安装路径 | 不破坏 collect outcome 协议；schema version；并发锁 |
| B13 | 活跃时长 | 用户理解并认可“记录活跃时长（估算）” | 不叫 AI 生成时间；需要事件粒度 |
| B14 | 新数据源 | 每源至少 1 份授权真实 schema；正式化至少 3 台机器 | 每源独立开关；默认关闭；不读正文和项目路径 |
| B15 | String Catalog | 构建链能编译并打包本地化资源 | 不把 xcstrings 当运行时普通 JSON |
| B16 | 全量模块重构 | 有明确维护瓶颈且功能 Goal 不再频繁改同一区域 | 先解决 Helper/source manifest；单独重构 Goal |
| B17 | Agent 交付 | 本地元数据能稳定表达交付、检查和尝试，用户价值验证成立 | Beta 口径，不宣称绝对事实；隐私与 opt-in 单独设计 |

每个 Backlog 条目进入新 Goal 前必须重新回答：

1. 它解决哪个唯一用户任务？
2. 当前有什么证据证明问题存在？
3. 成功指标是什么？
4. 什么情况下停止？
5. 是否新增网络、数据访问、权限、存储或迁移风险？

---

## 8. 人工门目录

### MG-PRIVACY

- 审核：排行榜默认关闭、显式开启说明、关闭后清空；
- 通过只授权进入 V1；
- 不授权网络扩展、发布或清理。

### MG-BASELINE

- 审核：live Git refs、工作区状态、checkpoint 55 路径裁决与拟议 allowlist；
- 必须在 E0 任何代码移植前通过；
- 只授权 allowlist 内改动，不授权 push、发布或清理。

### MG-UX

- 审核：全部新鲜度/失败 fixture 的 UI、信息层级和三语文案；
- `approve / reject / defer`；
- reject 返回 V1-T02，defer 状态为 `waiting_manual`。

### MG-BETA

- 审核：10 人测试方案、去敏记录和结果；
- 不足阈值必须迭代，不得人工豁免成通过。

### MG-RELEASE

不属于当前三个 Goal 的完成条件。若用户另行决定发布，必须创建独立 Release Goal，并至少验证：

- 候选 SHA 与已批准提交一致；
- 版本、tag、artifact manifest 一致；
- CI 全绿；
- 签名、公证、staple、Gatekeeper；
- 从公开 Release 重新下载 DMG/ZIP 后再次验证 SHA-256、挂载、冷安装、启动和升级；
- release notes 只写相对上一正式版本的净新增；
- 失败时回滚到已签名公证的上一正式 artifact，而不是开发 checkpoint。

### MG-CLEANUP

删除旧 worktree、缓存或历史文件前必须单独确认。确认前须证明目标 clean、提交已被目标分支包含、路径精确且操作可恢复。当前 PRD 不授权任何清理。

---

## 9. 通用验收与证据目录

建议所有稳定证据写入：

```text
docs/goal-runs/<goal-id>/<YYYY-MM-DD>/
  baseline.md
  task-status.md
  verification.md
  benchmark.json
  manual-gates.md
  blockers.md
```

不得写入：凭据、本机用户名、绝对会话路径、prompt、代码正文、私聊、原始用户身份或未经去敏的真实日志。

### 9.1 每次候选构建的基础命令

```bash
swift test --package-path TokenStepSwift
./script/test_ccswitch_proxy_collector.sh
./script/test_codex_cumulative_collector.sh
./script/test_usage_recalibration_migration.sh
./script/build_swiftui_and_run.sh --no-launch
python3 script/check_localization.py
python3 script/check_language_refresh.py
```

`test_update_helper_transaction.sh` 在 E0-T02 实际纳入后加入基础命令。

### 9.2 五类验收必须分开记录

1. 本地静态与单元测试；
2. 数据口径与 full/incremental 等价性；
3. 性能与能耗代理指标；
4. UI / 用户人工验收；
5. 正式发布验收。

前四项通过不代表第五项已完成。正式发布未授权时，正确状态是 `release_ready`，不是 `published`。

---

## 10. Goal 导入说明

推荐不要一次导入 E0、V1、V2。按以下顺序逐个复制对应 Goal：

1. 先确认并启动 `G-E0`；
2. E0 有证据完成后，重新核验并确认 `G-V1`；
3. V1 完成且 V2 至少一个触发条件成立时，才确认 `G-V2`；
4. 所有 Backlog 另立 Goal，不继承本 PRD 的执行授权。

当前文档生成不代表任何 Goal 已启动，也不授权代码实现、Git 操作、外部发布或数据删除。

---

## 11. 变更记录

| 日期 | 版本 | 变更 |
|---|---|---|
| 2026-08-13 | 2.0 | 基于 v0.1.48 真实代码与 Git 状态重写；从 F01–F17 功能清单收敛为 G-E0/G-V1/G-V2 三个独立 Goal；增加六字段合同、条件任务、人工门、停止条件和可复制 `/goal`；将动态定价、blocks、Sparkle、SQLite、Widget、新源等移入条件 Backlog。 |
