# TokenStep

把 AI token 用量变成「每日 AI 步数」的 macOS 菜单栏 App。

## 立即下载

下载最新版 DMG，打开后把 `TokenStep.app` 拖进「应用程序」即可使用：

[下载 TokenStep 最新版](https://github.com/Backtthefuture/TokenStep/releases/latest/download/TokenStep-0.1.6.dmg)

也可以从 Release 页面查看所有版本：

[GitHub Releases](https://github.com/Backtthefuture/TokenStep/releases/latest)

TokenStep 已使用 Developer ID 签名并通过 Apple 公证。首次打开时，macOS 可能会出现标准确认弹窗，这是正常现象。

## 它是做什么的？

TokenStep 会在本机统计 Codex / Claude Code 的 token 使用量，并像运动圆环一样显示今天的 AI 使用进度。

你可以把它理解成：

> 给 AI Agent 时代准备的「步数 App」。

默认每日目标是 `1 亿 token`。它会显示今天用了多少、完成了多少、最近 30 天趋势、历史记录、按客户端和模型的统计，以及一个粗略的「消耗金额」估算。

## 当前支持

- Codex：优先读取 Codex 本地 SQLite token 汇总，必要时回退 JSONL。
- Claude Code：读取 `~/.claude/projects/**/*.jsonl` 里的 usage 元数据。

TokenStep 只读取 token 用量元数据，例如日期、模型、客户端名称和 token 数量。

它不会上传你的代码、prompt 或对话正文。

## 功能

- 菜单栏显示今日 token 数和进度圆环。
- 点击菜单栏可打开轻量弹层。
- 原生 macOS 仪表盘：今日、历史、统计、隐私。
- 每日目标可设置，默认每天一个亿。
- 自动刷新，默认 1 分钟。
- 开机启动，可在设置里关闭。
- 自动检查更新，发现新版后可下载已签名公证的 DMG。
- 本地数据存放在 `~/Library/Application Support/TokenStep`。

## 安装方式

1. 下载 [TokenStep 最新版 DMG](https://github.com/Backtthefuture/TokenStep/releases/latest/download/TokenStep-0.1.6.dmg)。
2. 打开 DMG。
3. 把 `TokenStep.app` 拖到「应用程序」。
4. 启动 TokenStep。
5. 在 macOS 右上角菜单栏点击 TokenStep 图标。

更详细的安装说明见 [docs/INSTALL.md](docs/INSTALL.md)。

## 隐私说明

TokenStep 是 local-first 的本地工具。

- 只读取本机 usage 元数据。
- 默认不上传任何数据。
- 不读取和上传代码、prompt、对话正文。
- 「消耗金额」只是本地粗略估算，不等于真实账单。

完整说明见 [docs/PRIVACY.md](docs/PRIVACY.md)。

## 本地构建

要求：

- macOS 14+
- Xcode Command Line Tools

构建并运行：

```bash
./script/build_and_run.sh --verify
```

只构建不启动：

```bash
./script/build_swiftui_and_run.sh --no-launch
```

生成的 App 位于：

```text
TokenStepSwift/dist/TokenStep.app
```

## 发布打包

Developer ID 签名：

```bash
TOKENSTEP_VERSION=0.1.6 \
CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
./script/package_release.sh
```

签名 + Apple 公证：

```bash
TOKENSTEP_VERSION=0.1.6 \
CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
TOKENSTEP_NOTARY_PROFILE="tokenstep-notary" \
./script/package_release.sh --notarize
```

产物会生成到：

```text
release/TokenStep-<version>.zip
release/TokenStep-<version>.dmg
```

维护者说明见 [docs/RELEASE.md](docs/RELEASE.md)。

## 开源协议

MIT。见 [LICENSE](LICENSE)。
