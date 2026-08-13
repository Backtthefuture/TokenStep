# Privacy

TokenStep is designed as a local-first usage tracker.

## What TokenStep Reads

TokenStep reads local metadata from supported agent logs:

- date or timestamp
- model name when present
- client name
- token usage counts

## What TokenStep Does Not Do

TokenStep does not upload anything by default.

TokenStep does not need to send your code, prompts, or conversation text to any server.

## Optional Quota Display

The Agent quota display is off by default.

When enabled, TokenStep may read local account metadata needed by supported tools:

- Codex quota is read from the local Codex account/rate limit interface.
- Claude Code quota is read by using the local macOS Keychain item for Claude Code and requesting Anthropic's OAuth usage endpoint.

TokenStep uses this only to show remaining quota. The account token is not stored by TokenStep and is not uploaded to a TokenStep server.

## Local Files

Generated app data is stored at:

```text
~/Library/Application Support/TokenStep
```

This folder contains settings, token summaries, and login item logs.

## Cost Estimates

The "spend" value is a rough local estimate based on bundled pricing assumptions. It is meant for trend tracking and is not a bill.

## Agent Work Rank (Opt-In)

The optional Agent Work rank card is strictly opt-in:

- New installs default to **hidden**. While hidden, TokenStep performs **zero local identity reads and zero leaderboard requests**, and no rank card is shown.
- Enabling it (自动 / 显示 in Settings) is an explicit user action. Only then does TokenStep read the local rank identity file (`~/.token-rank/client-state.json`, user id / display name / avatar URL only) and request the public leaderboard endpoint (`www.zhenganhuo.com/api/token-rank/leaderboard.php`).
- Switching back to 隐藏 immediately clears the in-memory identity, leaderboard, and error state, and stops all reads and requests.
- Legacy settings never silently enable the rank card: unrecognized legacy fields and explicit legacy "off" both migrate to hidden; only an explicit legacy "on" preserves visibility.
- TokenStep never uploads your local usage statistics to the leaderboard. Rank data shown comes from the public leaderboard API only.

## Future Sync Features

If TokenStep later adds cloud sync, it should be opt-in and should require a separate confirmation before uploading any data.
