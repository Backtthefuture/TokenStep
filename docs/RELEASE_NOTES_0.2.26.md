# TokenStep 0.2.26

Trae / Trae CN 改用 IDE 同款 Cloud-IDE-JWT 鉴权，修复 0.2.25 浏览器登录后仍报 401、额度不显示的问题；令牌过期与类型错误的提示也已区分。

- **401 的根因**：Trae 的 IDE 接口不接受 `Authorization: Bearer <jwt>`，会回 HTTP 401 / code 1001；IDE 自己用的是 `Authorization: Cloud-IDE-JWT <jwt>`。用真实账号令牌实测：Bearer 401，换成 Cloud-IDE-JWT 后 200，`user_entitlement_pack_list` 与 `usage_summary` 正常返回。
- **浏览器登录后额度可直接显示**：0.2.25 拿到的令牌本身没问题，只是请求头不对；升级后无需重新登录，已保存的令牌会立刻生效。
- **自动续期沿用已验证的链路**：refresh token 仍走 `/cloudide/.../ExchangeToken`，实测可换发新 JWT；刷新后新令牌继续通过额度接口。
- **错误提示细化**：令牌不是 IDE 版 JWT 时明确提示「令牌类型不对」，HTTP 401 / code 1001 提示「登录已过期」；刷新失败会带出服务端原因，网络或 5xx 错误不会被误当成登录过期而触发刷新。
- **手动粘贴仍是兜底**：输入框与「保存并检测」保留，引导文案已改为复制 `Cloud-IDE-JWT` 之后的令牌。

Token、金额与额度的统计口径不变。
