# G-E0 Baseline（2026-08-13）

- `HEAD` = `origin/main` = `ef13871`（v0.1.48）✅ 与 PRD §1.1 快照一致，无基线漂移
- `c540f98` 存在，55 路径（43 A + 12 M）
- tracked dirty = 0
- 未跟踪：`.agents/`、`brand/logo-concepts/qiaomu-tokenstep-icon-options/`、`docs/PRD_TOKENSTEP_OPTIMIZATION.md`（v2.0 Goal 目录）
- PRD §1.2 能力声明逐项实证通过（CodexIncrementalStore 26 处 / codex-incremental 路径 / seek(toOffset 3 处 / EnergyRefreshPolicy / 实验源开关 5 文件）
- PRD §1.3-1 隐私冲突实证：`agentWorkRankVisibility` 默认 `.automatic`，legacy 迁移同样落 `.automatic`（E0-T03 靶点确认）

详见 `docs/M0_RECONCILIATION.md`。
