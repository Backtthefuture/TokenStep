# Privacy

TokenStep is designed as a local-first usage tracker.

## What TokenStep Reads

TokenStep reads local metadata from supported agent logs:

- date or timestamp
- model name when present
- client name
- token usage counts

It does not read prompts, code, conversation text, or project files, and it never uploads usage data or content.

## Network Requests

Token totals are always computed locally. The app makes only the requests listed below. Each one says when it happens and what it sends.

| Request | Destination | On by default | When | What is sent |
| --- | --- | --- | --- | --- |
| Update check | `api.github.com/repos/Backtthefuture/TokenStep/releases/latest`, falling back to `github.com/.../releases/latest` | Yes (Settings → Check for updates automatically) | At launch, periodically, when a window comes to the front, and when you click Check Updates | A `User-Agent` header with the app version. No usage data. |
| Update download | `github.com/Backtthefuture/TokenStep/releases/download/...` | Only after you confirm an update | When you choose Install | Nothing beyond a standard download request. |
| Token Rank board | `www.zhenganhuo.com/api/token-rank/leaderboard.php` | Automatic: only if a local Token Rank account exists in `~/.token-rank/client-state.json`; can be hidden in Settings | At launch, with background refreshes, and when a window comes to the front; at most every 30 minutes | A read-only request with the board filters (`client`, `range`, `usage_mode`). TokenStep uploads nothing. Uploading to the board is done by the separate Token Rank client, not by TokenStep. |
| Codex quota | Runs the local `codex app-server`, which talks to OpenAI with your Codex login | No | When quota display is on, at most every 15 minutes | Handled by the Codex CLI. TokenStep only reads the rate-limit response. |
| Claude Code quota | `api.anthropic.com/api/oauth/usage` | No | When quota display is on, at most every 15 minutes | Your Claude Code OAuth access token, read from the macOS Keychain item Claude Code created. |
| Cursor quota and usage events | `cursor.com/api/usage-summary`, `cursor.com/api/usage`, `cursor.com/api/dashboard/get-filtered-usage-events` (fallback `api2.cursor.sh`) | No | When Cursor is turned on, at most every 15 minutes | Your Cursor session token, read from Cursor's local `state.vscdb`. It is kept in memory only. |
| GLM quota | `open.bigmodel.cn` or `api.z.ai` usage endpoints | No | When GLM is turned on | The API key you entered. It is stored in the macOS Keychain. |
| Kimi quota | `api.kimi.com` or `www.kimi.com` usage endpoints | No | When Kimi is turned on | The token from the local Kimi CLI login (`~/.kimi`), or the token you entered, which is stored in the macOS Keychain. |
| Grok quota | `cli-chat-proxy.grok.com/v1/billing` | No | When Grok is turned on | The session from the local Grok CLI login (`~/.grok/auth.json`), or the token you entered, which is stored in the macOS Keychain. |

Credentials are used only for the provider they belong to. They are never sent to a TokenStep server, because there is no TokenStep server.

## Local Files

Generated app data is stored at:

```text
~/Library/Application Support/TokenStep
```

This folder contains settings, token summaries, collector caches, and lifecycle logs. You can reveal or clear it from Settings.

## Time Zone

Usage is split into days using your Mac's current time zone. When the time zone changes, TokenStep recollects local logs so the day boundaries stay correct.

## Cost Estimates

The "spend" value is a rough local estimate based on bundled pricing assumptions. It is meant for trend tracking and is not a bill.

## Future Sync or Ranking Features

If TokenStep later adds cloud sync or uploads to a public ranking, it will be opt-in and will require a separate confirmation before any data is uploaded.
