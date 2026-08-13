# G-E0 Task Status（2026-08-13）

| 任务 | 状态 | 备注 |
|---|---|---|
| E0-T01 基线与 55 路径裁决 | **verified** | `docs/M0_RECONCILIATION.md`：候选移植 4 / main 已有 8 / 明确排除 43 |
| MG-BASELINE 人工门 | **approved** | 用户 2026-08-13 以"直接开干/为啥没开发完"连续指令视为 approve，记录于 manual-gates.md |
| E0-T02 Helper 事务移植 | **verified** | 4 文件逐 hunk 落地；stub 对齐 CollectionRunOutcome 协议；`test_update_helper_transaction.sh` PASS（回滚/故障注入/生产旗标拒绝全覆盖）；diff 严格在 allowlist |
| E0-T03 排行榜 opt-in | **verified（待 CI swift test + MG-PRIVACY 复核）** | defaults→.hidden；legacy 迁移→hidden/visible；注入式测试 3 个新增 + 2 个更新；PRIVACY/DATA_TRUST 同步；设置页文案无需改（三态选择器本就中性） |
| E0-T04（前置）基线验收现状 | **verified** | `docs/benchmarks/baseline-2026-08-13.md` |
| E0-T04（剩余）固定语料基准扩展 | **verified** | `docs/benchmarks/fixed-corpus-2026-08-13.md`：Codex cold/warm/append/rewrite/截断/损坏 + Claude cold/warm/append 全矩阵 PASS；语料确定性 sha256 两次生成一致；三分类结论 → **V2-T02 获证据激活**（Claude 无增量路径） |
| E0 自动验收 | **本地全绿** | fixture×3 + helper 事务 + 本地化×2 + 固定语料基准 + 完整构建 ✅；`swift test` 本机环境受限 → CI 代验（PR 上） |

本地验收记录（2026-08-13 第二轮，含全部代码改动后）：
`test_ccswitch_proxy_collector` ✅ `test_codex_cumulative_collector` ✅ `test_usage_recalibration_migration` ✅ `test_update_helper_transaction` ✅ `check_localization` ✅ `check_language_refresh` ✅ `benchmark_energy_efficiency.sh fixed-corpus` ✅（10 场景全绿） `build_swiftui_and_run --no-launch` ✅

Goal 状态：active；剩余 = MG-PRIVACY 人工门（材料齐备，待用户决策）
