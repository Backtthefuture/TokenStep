# Collection Gap Audit（G-V2 / V2-T01，2026-08-13）

> 依据：PRD_TOKENSTEP_OPTIMIZATION.md §6.3。证据来源：E0-T04 固定语料基准
> （`docs/benchmarks/fixed-corpus-2026-08-13.md`）、`benchmark_energy_efficiency.sh`
> cache-compare/database-compare 模式、CodexCumulativeFixtureCheck、
> `test_update_helper_transaction.sh`、代码核验。
> 分类词表：`verified_existing` / `verified_gap` / `not_relevant` / `unverified`。

## 能力矩阵

| 能力 | 分类 | 证据 |
|---|---|---|
| Codex byte-offset 尾读（append 只读增量） | `verified_existing` | 固定语料 append 场景 55ms、generation 1→2、逻辑写 430KB（vs cold 4.7MB） |
| 残缺 JSONL 尾行保护 | `verified_existing` | truncated 场景 status=ok、records 精确 -1、等价对账通过 |
| 文件截断/替换（rewritten timestamps） | `verified_existing` | rewrite 场景 records 7613→7578、七板块等价 |
| prefix/full fingerprint | `verified_existing` | CodexCumulativeFixtureCheck：middle rewrite 检测/重扫/追加；parent anchor 依赖 |
| parent/child session（replay/子代理） | `verified_existing` | fixture：isolated/parallel/nested child、replay 单/双 metadata |
| SQLite staging 原子性 | `verified_existing` | CodexIncrementalStore staging transaction（代码核验 + corrupt 自愈场景） |
| 缓存损坏重建 | `verified_existing` | 2KB 物理破坏 → 18ms 自愈、等价通过 |
| collection checkpoint（未变跳过） | `verified_existing` | warm 17ms、逻辑写 0；真机 checkpoint 文件在位 |
| summary record 粒度（summary_records 列） | **`verified_gap`** | 见下文 G1 |
| Helper 120 秒超时 | `verified_existing` | `DataService.helperTimeoutSeconds = 120`（DataService.swift:6,230）；真机冷采集实测 ~12s（16:25:03→16:25:15），余量充足 |
| incremental ≡ full rebuild（token 口径） | `verified_existing` | compare 模式 mismatch=0、record_count_delta=0；database-compare 双库一致 |

## G1：summary 与 detailed 读出路径的估算金额分歧

**现象**（确定性复现，固定语料 150 会话/7613 记录）：

- token、记录数、exact/dup/inherited 诊断、每模型 token —— **完全一致**；
- 估算金额：summary **$65.71** vs detailed **$71.88**（+9.4%）；
- 复现：`TOKENSTEP_BENCHMARK_HOME=<corpus>/home TOKENSTEP_BENCHMARK_DATABASE=<db> ./script/benchmark_energy_efficiency.sh cache-compare` → `mismatch_sections=totals,daily`。

**已排除的原因**：

- 存储层不一致——两列 plist 分量和逐会话完全一致（解码核验）；
- requestID 跨会话重复——7613 条全唯一；detailed 读出去重零命中；
- `openAICostByParts` 逐条 clamp 非线性——线性化实验后分歧数字**一字不变**（65.71/71.88），已回滚该实验改动；
- 逐条/聚合理论定价（新旧公式均）= $65.70，与 summary 一致，**与 detailed 的 $71.88 不符**——说明 detailed 路径在 readout 之后、aggregate 之前的某处变换了记录分量语义（疑点：`canonicalUsageCounts` 的 input-cached 包含关系在两条路径的调用点不同）。

**生产影响**：`requiresDetailedRecords = !ccSwitch.records.isEmpty`（UsageCollector.swift:64）——
**CC Switch 有代理行时 Codex 估算金额会切换到 detailed 口径（本语料 +9.4%）**。token 与圆环不受影响；金额本身是"API 列表价估算"（V1 已在 UI 常驻标注）。

**修复方向**（需专项 Goal，不在本轮）：定位 detailed 读出路径的分量语义差异；或统一为"dedup 用 detailed、记账恒用 summary"（需扩展 CollectorResult 携带双数组，并验证 CC Switch enrich 不丢）。修复后 cache-compare 作为回归门。

## 条件任务激活裁决

| 任务 | 触发条件 | 实测 | 裁决 |
|---|---|---|---|
| V2-T02 Claude 尾部增量 | Claude warm/append p95 > 2s，或占完整采集 p95 > 50%；且 7 天 Beta ≥3 次可感知延迟 | 固定语料 Claude warm p95 = **990ms**（<2s）；Claude 占比远低于 Codex（用户真机 Claude 当日 1 条记录）；无 7 天 Beta 证据 | **not_activated** |
| V2-T03 Helper 跨轮恢复 | 真实 Helper 超时/终止且现有机制无法安全解决 | 真机冷采集 ~12s（120s 超时余量 10×）；故障注入测试（E0-T02）回滚路径全覆盖；无超时案例 | **not_activated** |
| V2-T04 最小拆分 | T02 或 T03 激活 | 均未激活 | **not_activated** |

G1（估算金额口径）不映射到 T02/T03 的激活面（它不是性能/中断缺口，而是记账一致性问题）——按 PRD"不以排期替代证据"，G1 记录在案并转交 v0.2 PRD Backlog（与 P0-4 成本计价改造同项处理最合适）。

## 结论

G-V2 无被量化证据激活的工程任务；本轮唯一 verified_gap（G1）已完整定性并转 Backlog。
按 PRD §6.1"如果所有 Conditional Task 均未触发，G-V2 不启动；这视为正确停止，不是失败"——
G-V2 以**正确停止**收口。
