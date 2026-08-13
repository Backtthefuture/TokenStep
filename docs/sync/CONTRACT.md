# TokenStep 多设备同步契约（G-S1 / S1-T01）

> 状态：**draft-frozen v1**（客户端按此实现；服务端排期确认后走 MG-SYNC 门冻结）。
> 账号体系：与 token-rank 共用正安火身份（`~/.token-rank/client-state.json`，严格 opt-in），
> 同步开关与榜单开关权限独立。

## 隐私红线（实现必须逐条成立，测试覆盖）

1. 默认关闭；关闭时**零身份读取、零网络请求**（Transport 调用计数 = 0，与榜单同规格测试）。
2. 上行仅限：设备名（用户可改）+ 按 `天×小时×Agent×模型×项目目录名` 的 token 计数 + schema 版本 + 水位。
3. **不上行**：金额、完整路径、会话正文、凭据、本机其他数据。
4. 解绑：清除本机同步状态 + best-effort 服务端删除请求，UI 明示。
5. 本机 `usage.json` 永远是权威源；远端桶只读展示用，合并只发生在展示层。

## 端点（zhenganhuo.com，HTTPS）

| 端点 | 方法 | 请求 | 响应 |
|---|---|---|---|
| `/api/tokenstep-sync/v1/register` | POST | `{device_name, schema_version}` + Bearer | `{device_id, account_id}` |
| `/api/tokenstep-sync/v1/buckets` | POST | `{buckets: SyncBucket[], watermark}` | `{accepted, server_watermark}` |
| `/api/tokenstep-sync/v1/fetch?since=` | GET | Bearer | `{devices: [{device_id, device_name, buckets}]}` |
| `/api/tokenstep-sync/v1/devices/{id}` | DELETE | Bearer | `{deleted: true}` |

错误：401 → unauthorized（停止并提示重绑）；429 → Retry-After；5xx → 退避重试（60s 起，上限 1h）。

## 数据结构

```json
// SyncBucket（上行/下行的最小单元；gzip 后传输）
{
  "day": "2026-08-13",        // Asia/Shanghai
  "hour": 14,                  // 0-23, -1 = 未知
  "agent": "Codex",            // 客户端显示名
  "model": "gpt-5.5",
  "project": "token-usage-monitor",  // 目录名（脱敏），可为 ""
  "tokens": 123456
}

// 本机状态 cache/sync-state.json（不下发）
{ "watermark": "2026-08-13T15:04:05Z", "device_id": "...", "device_name": "...",
  "schema_version": 1, "last_succeeded_at": 808302557 }
// 远端桶（只读）cache/remote-buckets.json
{ "fetched_at": 808302557, "devices": {"<device_id>": {"name": "Mac mini", "buckets": [SyncBucket...]}} }
```

## 合并语义（展示层）

- 默认只看本机；`mergeTodayAllDevices` / `mergeHistoryAllDevices` 两个独立开关；
- 今日圆环 = Σ(本机今日 + 各可见远端设备今日桶)；历史/统计同口径；
- 设备级隐藏：hidden_device_ids[]，隐藏后不参与任何合并；
- 服务端不可达：本地一切照旧，Popover ☁ 变灰 + 最后成功时间。
- 同名项目目录跨设备合并为同一桶（用户已确认 D1 语义）。

## 服务端 TODO（外部）

桶存储（按 account+device 分键）、注册/鉴权、删除、_since 增量拉取、gzip。
客户端在 `docs/sync/CONTRACT.md` 冻结前不发布启用入口。
