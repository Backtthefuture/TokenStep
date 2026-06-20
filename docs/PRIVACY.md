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

## Future Sync or Ranking Features

If TokenStep later adds cloud sync or public ranking, it should be opt-in and should require a separate confirmation before uploading any data.
