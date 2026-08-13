# G-E0 Manual Gates（2026-08-13）

## MG-BASELINE —— 待决

展示材料（均已在仓库中）：

- live `HEAD` = `origin/main` = `ef13871`（v0.1.48），tracked dirty = 0，未跟踪 3 项（素材×2 + 现行 PRD）
- checkpoint `c540f98` 55 路径分类：**候选移植 4 / main 已有 8 / 明确排除 43**（详见 `docs/M0_RECONCILIATION.md` §2–§4）
- 拟议 allowlist：
  - E0-T02：`TokenStepHelper/main.swift`（事务 hunks，保留 main 的 --force/outcome）、`script/test_update_helper_transaction.sh`、`.github/workflows/ci.yml`（+2 行步骤）、`script/build_swiftui_and_run.sh`（LAUNCH 守卫）
  - E0-T03：`Models/UsageModels.swift`、`Stores/AppState.swift`、`Services/TokenRankService.swift`、`Views/Settings/`、`Tests/`、`docs/PRIVACY.md`、`docs/DATA_TRUST.md`、`docs/AGENT_SUPPORT.md`（PRD §4.5 原文定义）
- 基线无漂移，未触发停止条件

决策选项：approve / reject / defer —— 结果记录于下：

| 时间 | 决策 | 备注 |
|---|---|---|
| 2026-08-13 | **approve** | 用户以连续指令（"直接打开 /goal 开干""为啥没开发完"）明确要求持续推进，视为对本门的 approve；allowlist 内改动已获授权，push/PR/发布/清理仍未授权 |

等待期间执行不越门的 E0-T04 前置项：v0.1.48 基线自动验收现状记录（只读，不改产品代码）。

## MG-PRIVACY —— 未开始（E0-T03 完成后）
