# Data Trust Contract

TokenStep solves *visibility*, not *settlement*. Usage numbers are self-reported local
telemetry: they are parsed from local agent logs on a machine the user fully controls,
and are good for trends, quotas and rhythm — not for billing, reimbursement, or rewards.

## Version Contract (E0 freeze)

Three independent version concepts. They must never be conflated or used to backfill
each other's changes:

| Version | Scope | When it changes |
|---|---|---|
| `codexAccountingRevision` | Token computation semantics for **one source** (currently Codex) | Only when that source's token results may change. Bumping it invalidates the collector cache and drives the in-app recalibration notice. It must NOT be bumped for other sources, storage changes, or pricing changes. |
| Storage schema version | Physical layout of `data/usage.json`, `cache/*.json`, `cache/codex-incremental.sqlite3` | When tables, fields, or encoding structures migrate. Old files must stay readable (`decodeIfPresent` with defaults). |
| Pricing snapshot revision | The bundled/estimated pricing dataset and its date | When estimated prices change. Reserved for future use — remote pricing is **not** implemented (see B01 backlog gate). |

Current values at v0.1.48 + E0: `codexAccountingRevision = 8`; storage schema is
implicit per Codable defaults; no pricing revision exists yet.

## Evidence Status Vocabulary (normative for UI and docs)

| Status | Meaning |
|---|---|
| 官方数据 / official | Returned by a vendor interface (quota services) |
| 本地记录 / local record | Parsed by TokenStep from local logs or databases |
| 估算 / estimate | Computed from rules or bundled list prices — never a bill |
| 已过期 / stale | Last attempt failed; the shown value is the last success |

Cost values are estimates from bundled API list prices. They do not represent
subscription entitlements or actual invoices.

## Freshness States (V1-T01, normative)

One state model for three channels (local collection, Codex quota, Claude quota),
computed by `FreshnessPolicy` — thresholds live only in the policy, never in views:

| State | 用户可见标签 | Meaning |
|---|---|---|
| `neverSucceeded` | 暂无数据 | Never captured; UI must never show 0 for it |
| `fresh` | 已同步 | Last success within the normal TTL |
| `aging` | 数据待更新 | Past the normal TTL, latest attempt not failed |
| `stale` | 同步失败 · 显示最后成功数据 | Latest attempt failed while an old value is shown, or age > 2× TTL |
| `partial` | 部分来源失败 | Same refresh cycle: ≥1 enabled source OK and ≥1 failed |
| `disabled` | 已关闭 | Feature off (quota toggle) |

TTLs: collection = user refresh interval bounded by `EnergyRefreshPolicy` retry floor;
quota = 15 min (`EnergyRefreshPolicy.quotaTTL`); stale = 2× normal TTL.
Per-channel records distinguish `lastAttemptedAt` / `lastSucceededAt` / `lastFailedAt`
plus a safe error kind — Codex and Claude quota failures never mask each other.

## Agent Work Rank Data Flows (post E0-T03)

- Default: `agentWorkRankVisibility = .hidden` → 0 local identity reads, 0 leaderboard
  requests, no rank UI.
- Enabled by explicit user choice only; reads whitelisted identity fields
  (id / name / avatar URL) from `~/.token-rank/client-state.json` and calls the public
  leaderboard API (30 min cache TTL, 15 min retry policy via EnergyRefreshPolicy).
- Disabling clears identity, leaderboard, and error state in memory.
- Legacy migration: unrecognized legacy fields → hidden; legacy explicit on → visible;
  legacy explicit off → hidden.

## Source Diagnostics

`sources` in `data/usage.json` exposes per-source status, record counts, and accounting
counters (`counter_resets`, `inherited_tokens`, …). Statuses considered successful by
the freshness policy: `ok`, `ok_sqlite`. Absent statuses (`disabled`, `missing`,
`missing_db`, `missing_valid_rows`) mean "no data from this source today" and never
trigger partial-failure. Everything else (e.g. `incremental_cache_error`) counts as an
enabled-but-failed source. Diagnostics are the primary evidence for "is today's number
complete?" and feed the trust labels.

## Local Data, Network Requests and Retention

| Item | Location | Network | Retention |
|---|---|---|---|
| Usage warehouse | `data/usage.json` | none | local only, follows user data |
| Collector caches | `cache/collector-cache.json`, `cache/codex-incremental.sqlite3`, `cache/collection-checkpoint.json` | none | rebuilt on demand |
| Quota caches | `cache/claude-quota-cache.json` (+ in-memory Codex) | Anthropic usage API when quota feature is on; Codex via local CLI/app-server | TTL 15 min |
| Freshness records (V1) | `cache/freshness-state.json` | none | timestamps + safe error kinds only; no paths, no error text |
| Settings | `config/settings.json` | none | local only |
| Agent rank (opt-in) | in-memory + public leaderboard API | zhenganhuo.com only when explicitly enabled | 30 min cache |

## Known Boundaries

| Source | Tier | Data location | 口径 |
|---|---|---|---|
| Codex | official | `~/.codex/sessions` + `archived_sessions` JSONL; SQLite fallback `state_5.sqlite` | cumulative counters → deltas; incremental SQLite cache |
| Claude Code | official | `~/.claude/projects/**/*.jsonl` | per-message usage, dedup by message id |
| CC Switch Proxy | experimental | `~/.cc-switch/cc-switch.db` `proxy_request_logs` | 2xx + tokens>0; cross-source dedup |
| ZCode / Hermes / WorkBuddy | experimental (off by default) | local DBs / JSONL | see AGENT_SUPPORT.md |

- Codex native logs are cumulative counters; TokenStep derives deltas and handles
  resets/forks, but replayed or rewritten logs can still shift attribution.
- CC Switch proxy rows are deduplicated against native records by request identity;
  unmatched proxy rows are kept under their own client name.
- Cost estimates use hardcoded list prices until pricing revision B01 is activated.
  UI labels say 消耗金额（估算）; the disclaimer reads 按 API 列表价估算，不代表订阅或实际账单。
