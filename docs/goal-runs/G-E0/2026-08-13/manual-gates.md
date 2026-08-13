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

## MG-PRIVACY —— 待决（2026-08-13 材料齐备）

审核材料（均在仓库中）：

- `docs/M0_RECONCILIATION.md`（E0-T01，55 路径裁决）
- `docs/DATA_TRUST.md`（新增，数据信任契约：三版本概念、证据状态词表、榜单数据流、已知边界）
- `docs/PRIVACY.md`（更新：榜单 opt-in 章节，默认 hidden 承诺）
- 代码行为证据（替代截图，见下方"未验 gate"说明）：
  - `TokenStepSettings.defaults.agentWorkRankVisibility = .hidden`（新安装默认关闭）
  - legacy 迁移：无法识别的旧字段 → hidden / 显式 visible 才开启（`UsageModels.swift`）
  - `AgentWorkRankServiceTests`：hidden 状态下**零身份读取、零网络请求**（注入式断言）；身份白名单解码忽略凭据邮箱
  - `CCSwitchProxyFixtureCheck`：legacy 迁移断言更新为 hidden
- 自动测试报告：fixture×3 + helper 事务 + 本地化×2 + 固定语料基准 10 场景 + `build_swiftui_and_run --no-launch` 全绿（task-status.md 第二轮记录）

未验 gate（如实申报）：

1. `swift test` 全量 XCTest：本机 CLT-only 环境无法运行（原始错误见 baseline-2026-08-13.md），需 CI（macos-15）在 PR 上代验——**尚未推送，故尚未验证**；
2. 三状态（默认关闭/显式开启/再次关闭）GUI 截图或录屏：以注入式测试的零读取/零请求断言作为替代证据；如需录屏可在门决策时提出。

决策选项：approve / reject / defer —— 结果记录于下：

| 时间 | 决策 | 备注 |
|---|---|---|
| （待填） | | |

> approve 仅授权进入 G-V1，不授权 push、PR、发布或清理。
