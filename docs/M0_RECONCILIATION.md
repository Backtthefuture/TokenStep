# M0_RECONCILIATION —— checkpoint c540f98 全量路径裁决（E0-T01 交付物）

> Goal: G-E0 ｜ Task: E0-T01 ｜ 执行时间: 2026-08-13
> 裁决对象: `c540f98`（codex/token-accounting-agent-activity 顶端，"chore: checkpoint before switching to main"）
> 基线: `origin/main = ef13871 = v0.1.48`（执行时核验 `HEAD == origin/main == ef13871`，tracked dirty = 0）

## 1. 基线核验结果（合同命令输出摘要）

| 检查 | 结果 |
|---|---|
| `git rev-parse HEAD origin/main c540f98` | 三 ref 均存在：`ef13871` / `ef13871` / `c540f98` ✅ |
| 工作区 | tracked dirty = 0；未跟踪 3 项：`.agents/`、`brand/logo-concepts/qiaomu-tokenstep-icon-options/`、`docs/PRD_TOKENSTEP_OPTIMIZATION.md`（现行 v2.0 Goal 目录）✅ |
| `git show --name-only c540f98` | 55 路径（43 A + 12 M）✅ |
| `git diff --stat origin/main...c540f98` | 55 files, +2626/−59 |

**PRD §1.2 能力声明实证**（防止重复建设，逐项验证于 HEAD）：

| 声明能力 | 证据 |
|---|---|
| Codex SQLite 增量缓存 | `CodexIncrementalStore` 在 UsageCollector.swift 出现 26 处；`codex-incremental` 缓存路径定义于 AppPaths.swift ✅ |
| byte-offset 尾读 | `seek(toOffset` 3 处 ✅ |
| EnergyRefreshPolicy | Support/EnergyRefreshPolicy.swift 存在 ✅ |
| 实验源开关 | `showExperimentalAgentSources` 引用 5 个文件（Models/AppState/Settings 卡）✅ |
| **隐私契约冲突（PRD §1.3-1）** | `TokenStepSettings.defaults.agentWorkRankVisibility = .automatic`；且 legacy 迁移 `legacyVisible ? .visible : .automatic` —— 新装与老用户默认都不是 opt-in ✅（E0-T03 靶点确认） |

## 2. 裁决总表（15 个逐一裁决路径）

| # | 路径 | checkpoint 改动 | 裁决 | 依据 |
|---|---|---|---|---|
| 1 | `TokenStepSwift/Sources/TokenStepHelper/main.swift` | +88/−25 | **候选移植**（E0-T02 核心） | 事务化安装器：`--test-mode`/`--test-failure-point` 故障注入、`--skip-relaunch`/`--skip-stop`、回滚增强。main 侧另有 `--force` 参数与 `CollectionRunOutcome` stdout 协议（6 行），**必须保留** |
| 2 | `script/test_update_helper_transaction.sh` | 新增 212 行 | **候选移植**（E0-T02） | main 无此脚本；依赖 build 脚本与 `-D TOKENSTEP_HELPER_TESTING` 编译标志 |
| 3 | `.github/workflows/ci.yml` | +2 行 | **候选移植**（E0-T02，随 #2 落地） | 新增 "Run update rollback checks" CI 步骤；main 未动过 ci.yml |
| 4 | `script/build_swiftui_and_run.sh` | +6/−4 | **候选移植**（E0-T02） | pkill 加 `LAUNCH` 守卫：`--no-launch` 不再误杀运行中的 App；main 版无守卫 |
| 5 | `TokenStepSwift/Sources/TokenStepSwift/Services/UsageCollector.swift` | +112/−12 | **main 已有** | checkpoint 的 WorkBuddy 采集在 main 有更进化版本（`timestampEpoch` epoch 小时桶、`fullContentFingerprint` SHA256、CodexIncrementalStore）；**禁止移植重复实现**（PRD §2.5） |
| 6 | `TokenStepSwift/Sources/TokenStepSwift/Stores/AppState.swift` | +21 | **main 已有** | `updateTimer`（6h 定期检查）：main 有等价 `checkForUpdatesIfNeeded` 机制（AppState.swift:463,646）；`openTokenRankMePage()`：main 用 `AgentWorkRankService.myPageURL`（AppState.swift:456）等价实现 |
| 7 | `TokenStepSwift/Sources/TokenStepSwift/Services/TokenRankService.swift` | +1 | **main 已有** | `myPageURL` 已在 main，且域名为更新的 `www.zhenganhuo.com`（checkpoint 版反而是旧的裸域名） |
| 8 | `TokenStepSwift/Sources/TokenStepSwift/Support/Localization.swift` | +46 | **main 已有** | checkpoint 新增 27 个 key 在 main UI 引用 = 0 处（main 0.1.47 重写文案体系，如 "今日排名" 有自己的版本） |
| 9 | `TokenStepSwift/Sources/TokenStepSwift/Views/Components.swift` | +3/−1 | **main 已有** | checkpoint 版与 main 版**零差异**（完全被 main 吸收） |
| 10 | `TokenStepSwift/Sources/TokenStepSwift/Views/Settings/SettingsDisplayRefreshCards.swift` | +23/−1 | **main 已有** | main 演进版含实验源开关卡（showExperimentalAgentSources 5 处引用覆盖此卡） |
| 11 | `TokenStepSwift/Tests/Fixtures/CCSwitchProxyFixtureCheck.swift` | +18/−9 | **main 已有** | checkpoint 版内容是 main 版子集（c540f98→main 方向 diff −0 删除；main 另 +114 行为 0.1.48 fixture 扩展） |
| 12 | `TokenStepSwift/Tests/TokenStepSwiftTests/UsageCollectorExperimentalAgentTests.swift` | +50 | **main 已有** | 与 main 版仅 1 行差异；checkpoint 的 +50 测试已在 main |
| 13 | `TokenStepSwift/Sources/TokenStepSwift/Views/Settings/SettingsUpdateAutostartPrivacyCards.swift` | −7 | **明确排除** | checkpoint 删除"下载前询问"开关 = 产品决策，超出 E0-T02/T03 的 allowed_paths；如需要，另立任务走新裁决 |
| 14 | `docs/PRD_TOKENSTEP_OPTIMIZATION.md` | 新增（v1 PRD） | **明确排除** | 旧 PRD 已被现行 v2.0 Goal 目录取代（现行文件未跟踪在工作区） |
| 15 | `skills-lock.json` | 新增 | **明确排除** | 工具链锁文件，与产品代码无关 |

## 3. 明确排除的资产路径（40 个，逐一路径枚举）

`.agents/`（28 个，agent 技能素材）：

```
.agents/skills/qiaomu-icon-generator/.github/ISSUE_TEMPLATE/bug_report.md
.agents/skills/qiaomu-icon-generator/.github/ISSUE_TEMPLATE/feature_request.md
.agents/skills/qiaomu-icon-generator/.github/PULL_REQUEST_TEMPLATE.md
.agents/skills/qiaomu-icon-generator/.gitignore
.agents/skills/qiaomu-icon-generator/CODE_OF_CONDUCT.md
.agents/skills/qiaomu-icon-generator/CONTRIBUTING.md
.agents/skills/qiaomu-icon-generator/LICENSE
.agents/skills/qiaomu-icon-generator/README.md
.agents/skills/qiaomu-icon-generator/SECURITY.md
.agents/skills/qiaomu-icon-generator/SKILL.md
.agents/skills/qiaomu-icon-generator/docs/assets/examples/qiaomu-music/README.md
.agents/skills/qiaomu-icon-generator/docs/assets/examples/qiaomu-music/codex-bitmap/choices.md
.agents/skills/qiaomu-icon-generator/docs/assets/examples/qiaomu-music/codex-bitmap/prompts.md
.agents/skills/qiaomu-icon-generator/docs/assets/examples/qiaomu-music/svg-cli/choices.md
.agents/skills/qiaomu-icon-generator/docs/assets/examples/qiaomu-music/svg-cli/contact-sheet.svg
.agents/skills/qiaomu-icon-generator/docs/assets/examples/qiaomu-music/svg-cli/option-01.svg
.agents/skills/qiaomu-icon-generator/docs/assets/examples/qiaomu-music/svg-cli/option-02.svg
.agents/skills/qiaomu-icon-generator/docs/assets/examples/qiaomu-music/svg-cli/option-03.svg
.agents/skills/qiaomu-icon-generator/docs/assets/examples/qiaomu-music/svg-cli/option-04.svg
.agents/skills/qiaomu-icon-generator/docs/assets/examples/qiaomu-music/svg-cli/option-05.svg
.agents/skills/qiaomu-icon-generator/docs/assets/examples/qiaomu-music/svg-cli/option-06.svg
.agents/skills/qiaomu-icon-generator/docs/assets/examples/qiaomu-music/svg-cli/option-07.svg
.agents/skills/qiaomu-icon-generator/docs/assets/examples/qiaomu-music/svg-cli/option-08.svg
.agents/skills/qiaomu-icon-generator/docs/assets/examples/qiaomu-music/svg-cli/option-09.svg
.agents/skills/qiaomu-icon-generator/references/codex-bitmap-reference-method.md
.agents/skills/qiaomu-icon-generator/references/qm-icon-studio-cli-method.md
.agents/skills/qiaomu-icon-generator/scripts/qm-icon-studio.sh
.agents/skills/qiaomu-icon-generator/assets/icon-template.svg
```

`brand/`（12 个，品牌图标素材）：

```
brand/logo-concepts/qiaomu-tokenstep-icon-options/choices.md
brand/logo-concepts/qiaomu-tokenstep-icon-options/qm-icon-options.json
brand/logo-concepts/qiaomu-tokenstep-icon-options/prompts.md
brand/logo-concepts/qiaomu-tokenstep-icon-options/rendered/option-01.png … option-09.png（9 个）
```

（枚举行数以 `git show --format= --name-only c540f98` 为准；本节两组共 40 路径，加 §2 的 15 个 = 55 ✅）

## 4. 候选移植 hunk 级方案（供 MG-BASELINE 批准）

**移植方法：逐 hunk 重新应用到 main 版本，禁止整文件覆盖，禁止 merge/cherry-pick 整个 c540f98（PRD §2.5）。**

| 候选 | 具体内容 | 价值 | 风险 | 验收 |
|---|---|---|---|---|
| Helper main.swift | #if TOKENSTEP_HELPER_TESTING 块（testMode/testFailurePoint/--test-mode/--test-failure-point）、--skip-relaunch/--skip-stop 参数、injectFailureIfRequested、notifyFailure 测试守卫、回滚分支增强 | 安装器故障注入可测，事务路径有自动化验收 | 与 main 的 --force/outcome 改动交叠（不同函数，冲突低）；编译标志漏传会导致测试模式静默失效 | `test_update_helper_transaction.sh` 全通过；`collect` stdout 协议不变（E0-T02 stop condition） |
| test_update_helper_transaction.sh | 整文件移植（212 行） | Helper 事务能力的唯一自动化验收 | 无（新文件） | 脚本通过 + CI 绿 |
| ci.yml | "Run update rollback checks" 步骤 2 行 | 回归防护 | 仅在脚本落地后加入，否则 CI 红 | CI 全绿 |
| build_swiftui_and_run.sh | pkill 块包进 `if [[ "$LAUNCH" == true ]]` | `--no-launch` 构建不再误杀正在运行的 App（也保护 CI/本地并行） | 极低（纯行为守卫） | 构建期间运行中的 TokenStep 进程存活 |

## 5. 未跟踪文件归属（防误入候选 diff）

| 未跟踪项 | 归属 | 处理 |
|---|---|---|
| `.agents/` | 素材（同 checkpoint 的 .agents 内容） | 不入 E0 diff；是否入库由用户另定 |
| `brand/logo-concepts/qiaomu-tokenstep-icon-options/` | 品牌素材 | 同上 |
| `docs/PRD_TOKENSTEP_OPTIMIZATION.md` | 现行 v2.0 Goal 目录 | 建议在 E0 收尾时随文档任务单独提交（属 E0-T03 docs 范畴，需用户确认） |

## 6. 结论

- **候选移植：4 路径**（Helper 事务能力包，全部落在 E0-T02 allowed_paths 内）
- **main 已有：8 路径**（含两处"checkpoint 想做但 main 已用不同方式实现"的等价能力）
- **明确排除：43 路径**（40 资产 + 旧 PRD + skills-lock + 1 个超范围 UI 决策）
- 基线 `ef13871` 与 PRD 快照一致，**无 MG-BASELINE 的"基线漂移"停止条件触发**，可进入人工门裁决。
