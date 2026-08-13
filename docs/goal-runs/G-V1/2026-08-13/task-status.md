# G-V1 Task Status（2026-08-13）

> Goal 启动：2026-08-13 用户经 AskUserQuestion 明确"确认并启动 G-V1"。
> 前置：G-E0 = complete（本地证据链闭合，MG-PRIVACY approved）。

| 任务 | 状态 | 备注 |
|---|---|---|
| V1-T01 统一新鲜度与失败状态模型 | **verified（待 CI swift test）** | 提交 `b4eed7d`；交付物见下 |
| V1-T02 可信标签与界面整合 | **verified** | 提交 `d936198`+修复 `79842cb`；MG-UX approved（真机验证后）；9 状态渲染件 `screenshots/freshness-states.png`（`script/render_freshness_states.sh` 生成） |
| V1-T03 Trust 与 Privacy 文档同步 | **verified** | DATA_TRUST 增补六态词表/诊断状态语义/本地数据与网络表/来源口径表；PRIVACY 增补新鲜度说明与估算措辞；AGENT_SUPPORT 核对无不一致（正式仅 Codex+Claude，实验区表述与实现相符） |
| V1-T04 十人理解度测试 | blocked（需用户招募 Beta） | manual_gate: MG-BETA |

## V1-T02 交付物

- `Views/FreshnessBadge.swift`：统一徽章（状态图标 + 标签 + 最后成功时间 + tooltip 汇总含失败来源与安全错误分类）。
- Popover 头部胶囊改为新鲜度驱动（同步中 / 六态徽章，需注意状态附带最后成功时间）。
- PopoverTodayRingCard / TodayView hero：从未成功显示"暂无数据"不显示 0；金额 Pill 标注"消耗金额（估算）"+ tooltip"按 API 列表价估算，不代表订阅或实际账单。"
- PopoverQuotaCard：Codex/Claude 双供应商常驻各自徽章，部分失败不被隐藏；无数据供应商行显示"暂无数据"或"显示最后成功数据"。
- PrivacyView 新增"数据状态说明"卡（五状态图例 + 估算声明），与 DATA_TRUST 词表一致。
- 三语本地化新增 17 键（en/zhHant），check_localization + check_language_refresh 通过。
- TodayView 顶部新增紧凑徽章行（非新卡片）。

## 本地验收（V1-T02/T03，2026-08-13）

- `build_swiftui_and_run --no-launch` ✅；fixture×4 + helper 事务 ✅；本地化×2 ✅
- `render_freshness_states.sh` ✅ → `screenshots/freshness-states.png`（10 行：9 fixtures + 金额示例行）

MG-UX 人工门 | **approved** | 2026-08-13 真机验证+修复后用户确认

Goal 状态：**engineering complete**；V1-T04（十人测试）waiting_external——用户需招募 10 名 Beta；测试工具包见 beta-kit.md。按用户 2026-08-13 指令"按你推荐的来，完成剩下全部开发"，工程主线继续推进 G-V2→B1-lite→A1→S1→A2，T04 结果回填后做最终 G-V1 收口。

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
