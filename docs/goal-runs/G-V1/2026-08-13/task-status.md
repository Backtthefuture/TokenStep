# G-V1 Task Status（2026-08-13）

> Goal 启动：2026-08-13 用户经 AskUserQuestion 明确"确认并启动 G-V1"。
> 前置：G-E0 = complete（本地证据链闭合，MG-PRIVACY approved）。

| 任务 | 状态 | 备注 |
|---|---|---|
| V1-T01 统一新鲜度与失败状态模型 | **verified（待 CI swift test）** | 见下 |
| V1-T02 可信标签与界面整合 | ready | manual_gate: MG-UX |
| V1-T03 Trust 与 Privacy 文档同步 | ready | 依赖 T02 |
| V1-T04 十人理解度测试 | blocked（需用户招募 Beta） | manual_gate: MG-BETA |

## V1-T01 交付物

- `Support/FreshnessPolicy.swift`：`UsageFreshnessKind`（六态）、`UsageErrorKind`（安全错误分类，六类）、`RefreshAttemptRecord`（区分 lastAttemptedAt / lastSucceededAt / lastFailedAt）、`FreshnessState`（持久化三通道记录）、集中分类策略（阈值全部在 policy：collection TTL = 用户刷新间隔受 EnergyRefreshPolicy 下限约束；quota TTL = 15min；stale = 2×TTL）。
- `UsageSnapshot.sourceAttempt`（`decodeIfPresent` 兼容旧快照；round-trip 测试覆盖）。
- `AppState`：三通道 freshness 发布（collectionFreshness / codexQuotaFreshness / claudeQuotaFreshness）；采集尝试/成功/失败全记录；**Codex 与 Claude 额度独立记录互不掩盖**；`lastError` 改为安全分类文案（不透出原始错误正文）；状态持久化至 `cache/freshness-state.json`（仅时间+分类，无路径无正文）。
- partial 判定基于快照 source diagnostics（disabled 源不算失败；ok/ok_sqlite 算成功）。

## 本地验收（2026-08-13）

- `test_freshness_model.sh` ✅（六态/独立通道/partial/legacy 解码/错误分类/记录迁移）
- 回归：fixture×3 + helper 事务 + 本地化×2 + `build_swiftui_and_run --no-launch` 全绿
- `swift test`（含 FreshnessModelTests 12 用例）→ CI 代验（PR 上）
- 构建脚本注意项：新增 Support 文件后，Helper 与三个 fixture 脚本的显式编译清单已同步（此为显式清单维护成本，G-V2 Collection Core 拆分时一并考虑收敛）

Goal 状态：active；下一步 = V1-T02（UI 整合，MG-UX 前置 fixtures）
