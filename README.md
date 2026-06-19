# TokenStep

TokenStep turns AI token usage into a daily step ring for macOS.

It is a native menu bar app that tracks local usage from supported AI coding agents, shows today's progress toward a token goal, and keeps history like an activity dashboard.

## Current Support

- Codex: reads token metadata from `~/.codex/sessions` and `~/.codex/archived_sessions`.
- Claude Code: reads usage metadata from `~/.claude/projects/**/*.jsonl`.

TokenStep only reads usage metadata such as date, model, client name, and token counts. It does not upload code, prompts, or conversation content.

## Install

Download the latest `TokenStep.dmg` from GitHub Releases, open it, and drag `TokenStep.app` into Applications.

On first launch, TokenStep starts from the macOS menu bar. It defaults to:

- daily goal: 100 million tokens
- refresh interval: 1 minute
- local-only stats
- login item enabled, configurable in Settings

For more detail, see [docs/INSTALL.md](docs/INSTALL.md).

## Features

- Menu bar progress ring and today's token count.
- Popover with today's AI steps, goal progress, spend estimate, and recent activity.
- Native dashboard for Today, History, Stats, and Privacy.
- Settings for daily goal, refresh interval, login launch, and privacy status.
- Local data storage under `~/Library/Application Support/TokenStep`.

## Privacy

TokenStep is local-first.

- It reads token usage metadata from supported local agent logs.
- It stores generated summaries on your Mac.
- It does not upload data by default.
- Estimated spend is approximate and not a bill.

See [docs/PRIVACY.md](docs/PRIVACY.md).

## Build Locally

Requirements:

- macOS 14+
- Xcode Command Line Tools

Build and run:

```bash
./script/build_and_run.sh --verify
```

Build without launching:

```bash
./script/build_swiftui_and_run.sh --no-launch
```

The app bundle is created at:

```text
TokenStepSwift/dist/TokenStep.app
```

## Package a Release

Developer ID signing:

```bash
TOKENSTEP_VERSION=0.1.0 \
CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
./script/package_release.sh
```

Signing plus notarization:

```bash
TOKENSTEP_VERSION=0.1.0 \
CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
TOKENSTEP_NOTARY_PROFILE="tokenstep-notary" \
./script/package_release.sh --notarize
```

Release outputs are written to:

```text
release/TokenStep-<version>.zip
release/TokenStep-<version>.dmg
```

See [docs/RELEASE.md](docs/RELEASE.md).

## Legacy Developer Tools

The Python collector and old PyObjC prototype are kept for development and historical comparison. The native SwiftUI app no longer depends on Python for normal installed use.

## License

MIT. See [LICENSE](LICENSE).
