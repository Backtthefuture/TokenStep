# G-S1 Task Status（2026-08-13）

| 任务 | 状态 | 备注 |
|---|---|---|
| S1-T01 同步契约 | **draft-frozen** | `docs/sync/CONTRACT.md` v1：端点/SyncBucket/水位/错误语义/隐私红线；**MG-SYNC 待服务端确认**（外部依赖） |
| S1-T02 DeviceSyncService | **verified（mock 层）** | Transport 协议注入；上行桶派生（天×Agent×项目 token 计数，无金额无路径）+ 水位 + 禁忌守卫；失败保留旧远端数据 |
| S1-T03 下行与合并层 | **verified** | remote-buckets.json 只读落盘；`SyncMergeView` 纯函数合并（默认只看本机/隐藏设备/开关合并）——测试覆盖三态 |
| S1-T04 设置卡与绑定 UI | **deferred（有意）** | 契约明示"服务端就绪前不提供启用入口"；settings 字段已就位（4 项，默认全关，legacy 解码兼容） |
| S1-T05 隐私压力测试 | **verified** | fixture：默认关闭 + Transport 零调用断言；上行序列化无 cost/路径断言；解绑清状态+文件+服务端删除 |

## 本地验收
`test_device_sync.sh` ✅（6 组）；CI 已接线；build ✅。
生产启用链路（URLSessionTransport + 绑定 UI + Popover ☁ 状态）在 MG-SYNC 门后一个 Goal 内完成——客户端核心逻辑已全部就绪并有测试。

Goal 状态：**client-ready, waiting_external（MG-SYNC/服务端）**
