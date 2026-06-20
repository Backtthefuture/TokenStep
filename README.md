# TokenStep

**像记录步数一样，记录你每天的 AI Token 消耗。**

AI 时代，每个人都在和 Agent 一起工作。

但我们很少知道：今天到底用了多少 AI？有没有比昨天更进一步？

TokenStep 是一个 macOS 菜单栏 App，用来本地统计你在 Codex、Claude Code 等 AI 编程工具里的 Token 消耗，并把它变成一个像 Apple 健身圆环一样的每日目标。

默认目标是：**每天 1 亿 Token**。

当你超过目标，圆环会进入下一圈。用得越多，颜色越深。

它不是为了严肃比较，而是让你直观看到：今天你和 AI 一起走了多远。

<img width="412" height="627" alt="image" src="https://github.com/user-attachments/assets/c4196b33-6a60-42a4-b66a-6a4d516b459a" />
<img width="560" height="554" alt="image" src="https://github.com/user-attachments/assets/dbb7d00c-858e-4897-a04c-43ca45366d30" />


## 立即下载

下载最新版 DMG，打开后把 `TokenStep.app` 拖进「应用程序」即可使用：

[下载 TokenStep 最新版](https://github.com/Backtthefuture/TokenStep/releases/latest/download/TokenStep-0.1.20.dmg)

也可以从 Release 页面查看所有版本：

[GitHub Releases](https://github.com/Backtthefuture/TokenStep/releases/latest)

TokenStep 已使用 Developer ID 签名并通过 Apple 公证。首次打开时，macOS 可能会出现标准确认弹窗，这是正常现象。

## TokenStep 适合谁？

TokenStep 适合这些人：

- 每天使用 Codex / Claude Code 写代码的人
- 用 AI Agent 做内容、开发、研究、自动化的人
- 想知道自己每天到底消耗了多少 AI Token 的人
- 把 AI 当成生产力基础设施，而不是偶尔试用工具的人

以前我们看步数，知道自己今天有没有动起来。

现在我们看 Token 消耗，知道自己今天有没有真正用 AI 推进工作。

## 它能做什么？

- 菜单栏实时显示今日 Token 消耗和进度圆环。
- 点击菜单栏打开轻量浮层。
- 原生 macOS 仪表盘：今日、历史、统计、模型与工具、隐私。
- 超过 1 亿后自动进入第 2 圈、第 3 圈。
- 最近 30 天 Token 使用趋势。
- 按客户端、按模型查看用量统计。
- 粗略估算 Token 消耗金额。
- 每日目标可设置，默认每天一个亿。
- 自动刷新，默认 1 分钟。
- 开机启动，可在设置里关闭。
- 多种主题色，菜单栏、圆环、活动墙和按钮会一起变化。
- 一键截图分享当前页面。
- 自动检查更新，发现新版后可下载已签名公证的 DMG。
- 本地数据存放在 `~/Library/Application Support/TokenStep`。

## 当前支持

- Codex：优先读取 Codex 本地 SQLite token 汇总，必要时回退 JSONL。
- Claude Code：读取 `~/.claude/projects/**/*.jsonl` 里的 usage 元数据。

更多 AI 编程工具支持会逐步加入。

## 隐私

TokenStep 默认只做本地统计。

它只读取 Token 用量元数据，例如日期、模型、客户端名称和 Token 数量，用于生成趋势、圆环和统计图。

它不会上传你的代码、prompt、对话正文或项目文件。

「消耗金额」只是本地粗略估算，不等于真实账单。

完整说明见 [docs/PRIVACY.md](docs/PRIVACY.md)。

## 安装方式

1. 下载 [TokenStep 最新版 DMG](https://github.com/Backtthefuture/TokenStep/releases/latest/download/TokenStep-0.1.20.dmg)。
2. 打开 DMG。
3. 把 `TokenStep.app` 拖到「应用程序」。
4. 启动 TokenStep。
5. 在 macOS 右上角菜单栏点击 TokenStep 图标。

更详细的安装说明见 [docs/INSTALL.md](docs/INSTALL.md)。

## 为什么做 TokenStep？

因为 AI 编程工具正在变成新的「工作现场」。

过去我们用日历看时间，用步数看运动，用记账软件看消费。

但 AI 使用量一直是隐形的。

TokenStep 想把这件事变得可见：

**今天你不是用了多少工具，而是和 AI 一起走了多少步。**

## 下载统计

查看 GitHub Release 下载数：

```bash
python3 script/github_download_stats.py
```

统计方案见 [docs/ANALYTICS.md](docs/ANALYTICS.md)。

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
TOKENSTEP_VERSION=0.1.20 \
CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
./script/package_release.sh
```

签名 + Apple 公证：

```bash
TOKENSTEP_VERSION=0.1.20 \
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
