# Install TokenStep

## Recommended Path

1. Download `TokenStep-<version>.dmg` from GitHub Releases.
2. Open the DMG.
3. Drag `TokenStep.app` into Applications.
4. Launch TokenStep.

TokenStep lives in the macOS menu bar. Click the menu bar item to open the popover, or choose "Open Dashboard" from the popover.

## First Launch

TokenStep creates local app data here:

```text
~/Library/Application Support/TokenStep
```

It stores:

- `data/usage.json`: generated token usage summary
- `config/settings.json`: daily goal and refresh settings
- `logs/`: login item logs

## Login Item

TokenStep enables login launch by default on first run so usage tracking is less likely to miss a day. You can turn this off in Settings.

## Supported Clients

TokenStep currently supports:

- Codex
- Claude Code

If neither client has local usage metadata, TokenStep will open normally and show an empty state until data appears.

## Uninstall

1. Quit TokenStep from the menu bar popover.
2. Delete `TokenStep.app` from Applications.
3. Optional: delete local data:

```bash
rm -rf "$HOME/Library/Application Support/TokenStep"
rm -f "$HOME/Library/LaunchAgents/com.huangshu.TokenStep.login.plist"
```
