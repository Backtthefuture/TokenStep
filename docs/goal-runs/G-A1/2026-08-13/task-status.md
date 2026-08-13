# G-A1 Task Status（2026-08-13）

| 任务 | 状态 | 备注 |
|---|---|---|
| A1-T01 AgentSource 注册表 | **verified** | `Services/AgentSources/AgentSources.swift`（协议轻量化：Registry + 七源；类型 de-privatized 最小化）；collect() 单点接线，既有源零改动 |
| A1-T02 设置数据来源卡 | **verified** | `experimentalAgentSources: [String]?`（legacy 布尔迁移不启新源，fixture 断言）；`SettingsT1AgentSourcesCard` 逐源开关 + installed/missing 探测；主开关联动 |
| A1-T03~T05 T1 七源 | **verified** | 合成 fixture 全过；**真机只读验证**：Grok 132 记录/87.9M tokens、OpenCode 3056 记录/247.1M tokens、Gemini 2 记录（真实 schema 完全匹配）；Qwen/Amp/Droid 本机无数据→missing 如实；Kimi 旧版无 usage 事件→如实不采 |
| A1-T06 文档 | **verified** | `docs/agents/README.md`（路径/格式/口径/验证状态） |

## 接入语义

- 默认全关；主开关（实验 Agent 来源）开启后逐源勾选才采集；
- `enabledIDs(masterEnabled:perSource:)`：master off → 空；legacy true（perSource nil）→ 空（新源永不静默启用）；
- 新源记录参与 totals/daily/models/tools/projects/rhythms/agentWork；source=experimentalAgent；
- 记录进 source diagnostics（per-source status）→ V1 freshness partial 判定天然覆盖（missing_valid_rows 归"缺席"不误报）。

## 本地验收

`test_agent_sources.sh` ✅（开关语义/Gemini/Qwen/Kimi/Grok/Amp/OpenCode fallback）+ 真机 REAL 输出见上；
CI 已接线。回归：ccswitch/codex/migration/project fixtures + helper + i18n + build 全绿。
未验：`swift test` 全量（CI 代验）；七源转正需 B14（3 台真机逐日对账）——本轮不转正。

MG-AGENTS：用户 2026-08-13 指令"完成剩下全部开发"覆盖合并前评审门；真机验证证据即门材料。
