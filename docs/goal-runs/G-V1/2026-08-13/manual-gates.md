# G-V1 Manual Gates（2026-08-13）

## MG-UX —— approved

审核材料：

- 9 状态渲染件：`screenshots/freshness-states.png`（`TOKENSTEP_FRESHNESS_RENDER_PATH=… script/render_freshness_states.sh` 可重新生成；2× 分辨率）
  1. 首次启动（从未成功）→ 暂无数据（灰，虚线圆）
  2. 刚成功 → 已同步（绿）
  3. 数据老化 → 数据待更新（橙，时钟）
  4. 额度请求失败有旧值 → 同步失败 · 最后成功 N 分钟前（红，三角）
  5. 采集失败有旧快照 → 同步失败（红）+ tooltip 显示安全错误分类
  6. Codex 成功 / Claude 失败 → 两枚独立徽章（绿/红），互不掩盖
  7. 部分本地源失败 → 部分来源失败（橙）+ tooltip 列失败来源
  8. 额度功能关闭 → 已关闭（灰）
  9. 旧快照读取 → 兼容解码，正常徽章
- 落地位置：
  - Popover 头部胶囊（原"已同步/同步中"位置，非新卡片）
  - Popover 今日圆环卡（从未成功不显示 0；金额标注"消耗金额（估算）"+ tooltip）
  - Popover 额度卡（双供应商独立徽章，部分失败不隐藏）
  - 主窗口今日页顶部紧凑徽章行 + hero 金额估算标注
  - 隐私页"数据状态说明"卡（五状态图例 + 估算声明）
- 三语：新增 17 键 en/zhHant，check_localization ✅ check_language_refresh ✅
- 自动验收：构建 ✅ fixture×4 ✅ helper 事务 ✅；`swift test`（含 FreshnessModelTests 12 用例）待 CI 代验
- 未验 gate 申报：swift test 全量需 CI（未推送）；真机 GUI 录屏未做（以渲染件 + 可运行候选替代，如需可补）

决策选项：approve / reject / defer —— 结果记录于下：

| 时间 | 决策 | 备注 |
|---|---|---|
| 2026-08-13 | **approve** | 用户真机验证后指令"按你推荐的来"；三处反馈问题已修复（79842cb：升级播种/成功判定/0token 行）|

> approve 仅表示 V1-T02/T03 通过，进入 V1-T04（十人理解度测试）；不授权 push、PR、发布。

## MG-BETA —— 未开始（V1-T04，需用户招募 10 名 Beta 用户）
