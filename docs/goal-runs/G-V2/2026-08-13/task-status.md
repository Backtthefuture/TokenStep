# G-V2 Task Status（2026-08-13）

| 任务 | 状态 | 备注 |
|---|---|---|
| V2-T01 能力矩阵审计 | **verified** | `docs/COLLECTION_GAP_AUDIT.md`：11 项 verified_existing + 1 项 verified_gap（G1 估算金额口径，转 Backlog） |
| V2-T02 Claude 尾部增量 | **not_activated** | 固定语料 Claude warm p95=990ms < 2s 阈值；无 7 天 Beta 证据 |
| V2-T03 Helper 跨轮恢复 | **not_activated** | 真机冷采集 ~12s（120s 超时 10× 余量）；无超时/中断案例 |
| V2-T04 最小 Collection Core 拆分 | **not_activated** | 前置 T02/T03 均未激活 |

## G1（verified_gap）摘要

summary/detailed 两条读出路径估算金额确定性分歧（65.71 vs 71.88，+9.4%，token/记录/诊断全一致）；
生产触发条件 = CC Switch 有代理行（requiresDetailedRecords 切换）。已排除存储不一致、requestID 重复、
计价 clamp 非线性（线性化实验分歧不变，实验已回滚）。疑点收敛到 detailed 路径 readout 后的分量语义
（canonicalUsageCounts input-cached 包含关系的调用点差异）。转 v0.2 Backlog，与 P0-4 成本计价改造合并处理，
修复后以 cache-compare 为回归门。

Goal 状态：**complete（正确停止）**——所有条件任务按证据 not_activated（PRD §6.1）。
用户 2026-08-13 指令"按你推荐的来，完成剩下全部开发"授权主线继续：B1-lite → G-A1 → G-S1 → G-A2。
