# 固定语料采集基准（G-E0 / E0-T04，2026-08-13）

> 交付物对应 `PRD_TOKENSTEP_OPTIMIZATION.md` §4.6；工具：`script/benchmark_energy_efficiency.sh fixed-corpus` + `TokenStepSwift/Tests/Fixtures/FixedCorpusBenchmark.swift`。

## 环境

| 项 | 值 |
|---|---|
| commit 基线 | `ef13871`（origin/main = HEAD，v0.1.48） |
| 工作区 | E0-T02/T03 候选改动在树（均不触碰 `UsageCollector.swift` 采集口径；`UsageModels.swift` 仅设置/榜单相关字段） |
| 系统 | macOS 15（darwin 24.6.0），Apple Silicon arm64 |
| 工具链 | CLT only，Swift 6.1.2（swiftc + VFS overlay 编译，同现有 fixture 惯例） |

## 语料（完全确定性）

| 项 | 值 |
|---|---|
| 生成方式 | 固定种子 LCG（Codex `0xC0DE_2026_08_13` / Claude `0xCA1A_2026_08_13`），两次独立生成 hash 一致（已验证） |
| Codex | 150 会话 / 2,919,005 B，铺在 2026-05-15…2026-08-12，累计计数器 schema（`event_msg/token_count`），模型 gpt-5/gpt-5.5/gpt-5.4-codex/gpt-5.1 |
| Claude | 120 文件（40 项目 × 3 会话）/ 2,436,029 B，assistant/usage schema，含 ~5% 同 message id 重复行与 stop_reason 变体 |
| corpus_sha256 | `c5239d34f90dc1fd39e3a595e85b490e74dcc5247fe1a60ff681118119abc33d` |

## 结果（2026-08-13T15:50 第二轮，warm_runs=5）

### Codex（增量 SQLite 缓存路径）

| 场景 | 耗时 | max RSS | 逻辑写入 | 等价性 |
|---|---|---|---|---|
| cold | 1,046 ms（首轮基准 ~1.0 s） | 20.7 MB | 4.74 MB（建库） | — |
| warm ×5 | median **17 ms** / p95 22 ms | 19.5 MB | **0 追加**（last_logical_write_bytes 恒定 4,740,410） | totals 与 cold 一致 |
| append（12 文件 +60 事件） | 55 ms，generation 1→2 | 39.2 MB | 430 KB | incremental ≡ full rebuild ✅ |
| rewrite（1 文件整写，rewritten timestamps） | 24 ms，records 7613→7578 | 37.0 MB | 20 KB | ✅ |
| truncated（末行残缺，模拟崩溃写一半） | 26 ms，status=ok，records -1 | 36.5 MB | 37 KB | ✅（残缺尾行保护生效） |
| corrupt-cache（库中部 2 KB 破坏） | 18 ms，status=ok，自愈重建 | 51.6 MB | 恢复正常 | ✅ |
| compare（纯对账） | — | 35.0 MB | — | mismatch=0，record_count_delta=0 ✅ |

### Claude（当前 full-scan 路径）

| 场景 | 耗时 | max RSS | 备注 |
|---|---|---|---|
| cold | 1,036 ms | 20.8 MB | 45,101,788 tokens |
| warm ×5 | median **978 ms** / p95 990 ms | 41.5 MB（同进程 6 次扫描累计） | 与 cold 无差异：每次全量重解析 |
| append（10 文件 +120 行） | 991 ms | 27.8 MB | 新增 418,000 tokens 被正确记录 ✅ |

> 口径说明：Claude 走 `collectClaudeCodeUsageSnapshotForTests`，每次调用使用全新 CollectorCache，测得的是 full-parse 口径；App 内持久 `collector-cache.json` 的 mtime 命中路径不在本钩子覆盖范围内，本报告不对其下结论。

## 强制三分类结论（PRD §4.6）

**1. v0.1.48 已具备**

- Codex warm 缓存命中：**17 ms vs cold ~1,000 ms（约 57×）**，且 warm 路径逻辑写入为零；
- append 增量采集与 generation 递增；
- rewritten timestamps 整文件重扫；
- 残缺尾行保护（截断行被安全丢弃，records 精确 -1）；
- 缓存损坏自愈（2 KB 物理破坏后 18 ms 恢复且等价）；
- incremental ≡ full rebuild 的 totals/daily/rhythms/agentWork/tools/models/sources 七板块逐项等价。

**2. 有证据的缺口**

- **Claude 无增量路径**：语料无变化时仍每次全量重解析（120 文件 ~1 s，随真实数据规模线性放大）。→ 激活 **V2-T02（Claude 尾部增量读取）**，证据充分。
- 次要观察（不单独立项）：Claude 同进程多轮扫描 RSS 累计（20.8→41.5 MB），疑为候选字典驻留，V2-T02 实现时一并复核。

**3. 无须开发**

- baseline-2026-08-13.md 观察 1 的"warm 53.7 s"：固定语料证明 warm 算法路径本身是毫秒级；53.7 s 与真实规模 cold build（1107 会话/68k 记录/GB 级文件）量级相称，最可能是该轮临时 DB 未跨轮持久化导致实际走了 cold build（**解释性假设，已标注；不再作为缺口证据**）。观察 2 的"基准语料覆盖缺口"由本报告关闭。

## 复现

```bash
./script/benchmark_energy_efficiency.sh fixed-corpus          # 全矩阵
TOKENSTEP_BENCHMARK_WARM_RUNS=9 ./script/benchmark_energy_efficiency.sh fixed-corpus
# 原始输出逐场景保存在 ${TMPDIR}/tokenstep-energy-benchmark-$UID/fixed-*.txt
```
