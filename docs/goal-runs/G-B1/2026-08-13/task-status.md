# G-B1 Task Status（2026-08-13，lite 范围）

> 用户 2026-08-13 决策：B1-lite 提前（仅现有 Codex/Claude 两源），G-A1 新源接入后零成本扩展。
> 已确认决策 D1（只显示目录名）/ D3（分享卡带项目）/ D4（v0.2 只做 project）。

| 任务 | 状态 | 备注 |
|---|---|---|
| B1-T01 项目提取与脱敏层 | **verified** | `projectDisplayName`：末级目录名≤64 字符、必须含字母/数字、纯符号→nil→未命名项目；Claude 行内 cwd（无损，中文可用）；Codex session_meta.payload.cwd |
| B1-T02 数据模型与迁移 | **verified** | `ProjectUsage`；`DailyUsage.projects?`/`UsageSnapshot.projects` decodeIfPresent 兼容旧快照；Codex 记录级 projectName + summary key 扩展 + tail 继承 |
| B1-T03 UI 三处落地 | **verified** | 今日页"今日项目"全宽卡（Top4+折叠+Agent 徽标+脱敏脚注）；统计页"按项目（近 30 天）"；Popover"今日路线"（Top3 紧凑行） |
| B1-T04 分享卡项目条目 | **verified** | 战报卡新增"今日/昨日路线"面板（Top3，目录名） |
| B1-T05 隐私文档同步 | **verified** | PRIVACY"Project Dimension"章节；DATA_TRUST"Project Dimension"规范 |

## 本地验收

`test_project_extraction.sh` ✅（提取脱敏/Claude 端到端/Codex 提取+tail 继承/旧快照兼容）；全量回归 ✅（fixture×5 + helper + i18n×2 + build）。已入 CI。
未验：真机 GUI 视觉效果（待用户下次打开 App 查看"今日项目"卡）。

范围说明：未做手动归组/重命名（C05 backlog）；未含新 Agent 源项目提取（G-A1 各源自带）。
