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

`sources` in `data/usage.json` exposes per-source status (`ok`, `missing`, `disabled`,
…), record counts, and accounting counters (`counter_resets`, `inherited_tokens`, …).
They are the primary evidence for "is today's number complete?" and feed the trust
labels required by G-V1.

## Known Boundaries

- Codex native logs are cumulative counters; TokenStep derives deltas and handles
  resets/forks, but replayed or rewritten logs can still shift attribution.
- CC Switch proxy rows are deduplicated against native records by request identity;
  unmatched proxy rows are kept under their own client name.
- Cost estimates use hardcoded list prices until pricing revision B01 is activated.
