# TokenStep App

原生 macOS 菜单栏 App。它只读取本地 `data/usage.json`，不上传任何内容。

TokenStep 把 AI token 用量做成“今日 AI 步数”：默认每天 1 亿 token，显示进度环、消耗金额、历史记录和刷新设置。

## 构建

```bash
./build_app.sh
open "dist/TokenStep.app"
```

也可以在上级目录运行：

```bash
./script/build_and_run.sh
```

菜单栏会出现一个进度环和今日 token 数。点击后展开浮层，点“打开客户端”进入原生窗口。
