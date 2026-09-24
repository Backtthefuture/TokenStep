#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import glob
import html
import json
import os
import re
import sqlite3
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any

try:
    from zoneinfo import ZoneInfo
except ImportError:  # pragma: no cover
    ZoneInfo = None


ROOT = Path(__file__).resolve().parent
DATA_DIR = ROOT / "data"
DATA_JSON = DATA_DIR / "usage.json"
DASHBOARD_HTML = ROOT / "dashboard.html"
PRICING_JSON = ROOT / "config" / "pricing.json"
TZ_NAME = os.environ.get("TOKEN_USAGE_TZ", "Asia/Shanghai")
LOCAL_TZ = ZoneInfo(TZ_NAME) if ZoneInfo else dt.timezone(dt.timedelta(hours=8))

TOOL_COLORS = {
    "Codex": "#2563eb",
    "Claude Code": "#df7656",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build a local AI token usage dashboard.")
    sub = parser.add_subparsers(dest="command")
    sub.add_parser("collect", help="Collect usage data and regenerate dashboard.html")
    sub.add_parser("print-summary", help="Collect data and print a compact summary")
    return parser.parse_args()


def load_pricing() -> dict[str, Any]:
    if not PRICING_JSON.exists():
        return {}
    with PRICING_JSON.open("r", encoding="utf-8") as f:
        return json.load(f)


def parse_iso(ts: str | None) -> dt.datetime | None:
    if not ts:
        return None
    try:
        if ts.endswith("Z"):
            ts = ts[:-1] + "+00:00"
        parsed = dt.datetime.fromisoformat(ts)
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=dt.timezone.utc)
        return parsed.astimezone(LOCAL_TZ)
    except Exception:
        return None


def date_from_iso(ts: str | None) -> str | None:
    parsed = parse_iso(ts)
    return parsed.date().isoformat() if parsed else None


def date_from_epoch(seconds: int | float | None) -> str | None:
    if seconds is None:
        return None
    try:
        return dt.datetime.fromtimestamp(float(seconds), LOCAL_TZ).date().isoformat()
    except Exception:
        return None


def empty_usage() -> dict[str, int]:
    return {
        "input_tokens": 0,
        "output_tokens": 0,
        "cache_creation_input_tokens": 0,
        "cache_read_input_tokens": 0,
        "reasoning_output_tokens": 0,
        "total_tokens": 0,
    }


def normalize_usage(raw: dict[str, Any] | None) -> dict[str, int]:
    usage = empty_usage()
    if not isinstance(raw, dict):
        return usage
    aliases = {
        "input": "input_tokens",
        "output": "output_tokens",
        "cached": "cache_read_input_tokens",
        "thoughts": "reasoning_output_tokens",
        "total": "total_tokens",
        "input_tokens": "input_tokens",
        "output_tokens": "output_tokens",
        "cache_creation_input_tokens": "cache_creation_input_tokens",
        "cache_read_input_tokens": "cache_read_input_tokens",
        "cached_input_tokens": "cache_read_input_tokens",
        "reasoning_output_tokens": "reasoning_output_tokens",
        "total_tokens": "total_tokens",
    }
    for key, value in raw.items():
        mapped = aliases.get(key)
        if not mapped:
            continue
        try:
            usage[mapped] += int(value or 0)
        except Exception:
            pass
    if usage["total_tokens"] <= 0:
        usage["total_tokens"] = (
            usage["input_tokens"]
            + usage["output_tokens"]
            + usage["cache_creation_input_tokens"]
            + usage["cache_read_input_tokens"]
            + usage["reasoning_output_tokens"]
        )
    return usage


def add_usage(a: dict[str, int], b: dict[str, int]) -> dict[str, int]:
    for key, value in b.items():
        a[key] = a.get(key, 0) + int(value or 0)
    return a


def model_key(model: str | None) -> str:
    value = (model or "unknown").strip()
    return value if value else "unknown"


def match_pricing_model(pricing: dict[str, Any], model: str) -> dict[str, Any] | None:
    models = pricing.get("models", {})
    lower = model.lower()
    if model in models:
        return models[model]
    for key, value in models.items():
        if lower.startswith(key.lower()) or key.lower() in lower:
            return value
    return None


def estimate_cost(usage: dict[str, int], tool: str, model: str, pricing: dict[str, Any]) -> float:
    rates = match_pricing_model(pricing, model)
    if not rates:
        rates = pricing.get("tools", {}).get(tool)
    if not rates:
        rates = {"total_usd_per_1m": pricing.get("default_total_usd_per_1m", 0)}

    if "total_usd_per_1m" in rates:
        return usage.get("total_tokens", 0) / 1_000_000 * float(rates.get("total_usd_per_1m", 0))

    total = 0.0
    total += usage.get("input_tokens", 0) / 1_000_000 * float(rates.get("input_usd_per_1m", 0))
    total += usage.get("output_tokens", 0) / 1_000_000 * float(rates.get("output_usd_per_1m", 0))
    total += usage.get("cache_creation_input_tokens", 0) / 1_000_000 * float(
        rates.get("cache_creation_usd_per_1m", rates.get("input_usd_per_1m", 0))
    )
    total += usage.get("cache_read_input_tokens", 0) / 1_000_000 * float(
        rates.get("cache_read_usd_per_1m", 0)
    )
    total += usage.get("reasoning_output_tokens", 0) / 1_000_000 * float(
        rates.get("reasoning_usd_per_1m", rates.get("output_usd_per_1m", 0))
    )
    return total


def collect_codex() -> tuple[list[dict[str, Any]], dict[str, Any]]:
    paths = []
    home = Path.home()
    for pattern in [
        str(home / ".codex" / "sessions" / "**" / "*.jsonl"),
        str(home / ".codex" / "archived_sessions" / "*.jsonl"),
    ]:
        paths.extend(glob.glob(pattern, recursive=True))

    records: list[dict[str, Any]] = []
    seen: set[tuple[Any, ...]] = set()
    files_read = 0

    for path in sorted(set(paths)):
        session_id = Path(path).stem
        current_model = "unknown"
        event_index = 0
        try:
            with open(path, "r", encoding="utf-8") as f:
                files_read += 1
                for line in f:
                    try:
                        obj = json.loads(line)
                    except Exception:
                        continue
                    payload = obj.get("payload") if isinstance(obj, dict) else None
                    if obj.get("type") == "session_meta" and isinstance(payload, dict):
                        session_id = payload.get("id") or session_id
                    if obj.get("type") == "turn_context" and isinstance(payload, dict):
                        current_model = model_key(payload.get("model") or current_model)
                    if obj.get("type") != "event_msg" or not isinstance(payload, dict):
                        continue
                    if payload.get("type") != "token_count":
                        continue
                    info = payload.get("info") or {}
                    usage = normalize_usage(info.get("last_token_usage"))
                    if usage["total_tokens"] <= 0:
                        continue
                    event_index += 1
                    timestamp = obj.get("timestamp")
                    day = date_from_iso(timestamp)
                    if not day:
                        continue
                    dedupe_key = (session_id, timestamp, event_index, usage["total_tokens"])
                    if dedupe_key in seen:
                        continue
                    seen.add(dedupe_key)
                    records.append(
                        {
                            "date": day,
                            "timestamp": timestamp,
                            "tool": "Codex",
                            "model": current_model,
                            "usage": usage,
                            "source": "codex-rollout",
                        }
                    )
        except Exception:
            continue

    if records:
        return records, {"status": "ok", "files": files_read, "records": len(records)}

    fallback_records = collect_codex_from_threads()
    return fallback_records, {
        "status": "fallback_threads" if fallback_records else "missing",
        "files": files_read,
        "records": len(fallback_records),
    }


def collect_codex_from_threads() -> list[dict[str, Any]]:
    home = Path.home()
    db_candidates = [home / ".codex" / "state_5.sqlite", home / ".codex" / "sqlite" / "state_5.sqlite"]
    db_path = next((p for p in db_candidates if p.exists()), None)
    if not db_path:
        return []

    records: list[dict[str, Any]] = []
    try:
        con = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
        cur = con.cursor()
        for created_at, model, tokens_used in cur.execute(
            "select created_at, model, tokens_used from threads where tokens_used > 0"
        ):
            day = date_from_epoch(created_at)
            if not day:
                continue
            usage = empty_usage()
            usage["total_tokens"] = int(tokens_used or 0)
            records.append(
                {
                    "date": day,
                    "timestamp": None,
                    "tool": "Codex",
                    "model": model_key(model),
                    "usage": usage,
                    "source": "codex-threads",
                }
            )
    except Exception:
        return []
    return records


def collect_claude_code() -> tuple[list[dict[str, Any]], dict[str, Any]]:
    paths = glob.glob(str(Path.home() / ".claude" / "projects" / "**" / "*.jsonl"), recursive=True)
    responses: dict[str, tuple[int, str, dict[str, Any]]] = {}
    files_read = 0

    for path in sorted(paths):
        try:
            with open(path, "r", encoding="utf-8") as f:
                files_read += 1
                for line_no, line in enumerate(f, 1):
                    try:
                        obj = json.loads(line)
                    except Exception:
                        continue
                    if obj.get("type") != "assistant":
                        continue
                    message = obj.get("message")
                    if not isinstance(message, dict):
                        continue
                    usage = normalize_usage(message.get("usage"))
                    if usage["total_tokens"] <= 0:
                        continue
                    day = date_from_iso(obj.get("timestamp"))
                    if not day:
                        continue
                    message_id = message.get("id")
                    if isinstance(message_id, str) and message_id.strip():
                        unique = f"message:{message_id}"
                    else:
                        unique = obj.get("uuid") or f"{path}:{line_no}"
                        unique = f"uuid:{unique}"
                    has_stop_reason = bool(str(message.get("stop_reason") or "").strip())
                    priority = 1 if has_stop_reason else 0
                    existing = responses.get(unique)
                    if existing and existing[0] > priority:
                        continue
                    record = {
                        "date": day,
                        "timestamp": obj.get("timestamp"),
                        "tool": "Claude Code",
                        "model": model_key(message.get("model")),
                        "usage": usage,
                        "source": "claude-jsonl",
                    }
                    responses[unique] = (priority, str(obj.get("timestamp") or ""), record)
        except Exception:
            continue

    records = [item[2] for item in responses.values()]
    return records, {"status": "ok" if records else "missing", "files": files_read, "records": len(records)}


def aggregate(records: list[dict[str, Any]], pricing: dict[str, Any]) -> dict[str, Any]:
    daily_map: dict[str, dict[str, Any]] = defaultdict(lambda: {"date": "", "tools": {}, "total_tokens": 0, "cost": 0.0})
    tool_map: dict[str, dict[str, Any]] = defaultdict(lambda: {"usage": empty_usage(), "cost": 0.0})
    model_map: dict[tuple[str, str], dict[str, Any]] = defaultdict(lambda: {"usage": empty_usage(), "cost": 0.0})

    for record in records:
        tool = record["tool"]
        model = record["model"]
        usage = record["usage"]
        cost = estimate_cost(usage, tool, model, pricing)
        day = record["date"]

        daily = daily_map[day]
        daily["date"] = day
        daily["tools"][tool] = daily["tools"].get(tool, 0) + usage["total_tokens"]
        daily["total_tokens"] += usage["total_tokens"]
        daily["cost"] += cost

        add_usage(tool_map[tool]["usage"], usage)
        tool_map[tool]["cost"] += cost

        add_usage(model_map[(tool, model)]["usage"], usage)
        model_map[(tool, model)]["cost"] += cost

    total_tokens = sum(v["usage"]["total_tokens"] for v in tool_map.values())
    total_cost = sum(v["cost"] for v in tool_map.values())
    active_days = len([d for d in daily_map.values() if d["total_tokens"] > 0])

    daily_rows = []
    for day in sorted(daily_map):
        row = daily_map[day]
        tools = {tool: int(row["tools"].get(tool, 0)) for tool in TOOL_COLORS}
        daily_rows.append(
            {
                "date": day,
                "tools": tools,
                "total_tokens": int(row["total_tokens"]),
                "cost": round(float(row["cost"]), 4),
            }
        )

    tool_rows = []
    for tool, item in sorted(tool_map.items(), key=lambda kv: kv[1]["usage"]["total_tokens"], reverse=True):
        tokens = item["usage"]["total_tokens"]
        tool_rows.append(
            {
                "tool": tool,
                "tokens": int(tokens),
                "percent": round(tokens / total_tokens * 100, 2) if total_tokens else 0,
                "cost": round(float(item["cost"]), 4),
                "color": TOOL_COLORS.get(tool, "#64748b"),
            }
        )

    model_rows = []
    for (tool, model), item in sorted(model_map.items(), key=lambda kv: kv[1]["usage"]["total_tokens"], reverse=True):
        tokens = item["usage"]["total_tokens"]
        model_rows.append(
            {
                "tool": tool,
                "model": model,
                "tokens": int(tokens),
                "percent": round(tokens / total_tokens * 100, 2) if total_tokens else 0,
                "cost": round(float(item["cost"]), 4),
                "color": TOOL_COLORS.get(tool, "#64748b"),
            }
        )

    return {
        "generated_at": dt.datetime.now(LOCAL_TZ).isoformat(timespec="seconds"),
        "timezone": TZ_NAME,
        "totals": {
            "tokens": int(total_tokens),
            "cost": round(float(total_cost), 2),
            "active_days": active_days,
        },
        "daily": daily_rows,
        "tools": tool_rows,
        "models": model_rows,
    }


def collect_all() -> dict[str, Any]:
    pricing = load_pricing()
    codex_records, codex_meta = collect_codex()
    claude_records, claude_meta = collect_claude_code()
    records = codex_records + claude_records
    result = aggregate(records, pricing)
    result["sources"] = {
        "Codex": codex_meta,
        "Claude Code": claude_meta,
    }
    return result


def human_tokens(tokens: int | float) -> str:
    value = float(tokens or 0)
    if value >= 100_000_000:
        return f"{value / 100_000_000:.2f}亿"
    if value >= 10_000:
        return f"{value / 10_000:.1f}万"
    return f"{value:.0f}"


def json_for_html(data: dict[str, Any]) -> str:
    payload = json.dumps(data, ensure_ascii=False)
    return payload.replace("</", "<\\/")


def render_dashboard(data: dict[str, Any]) -> str:
    inline_data = json_for_html(data)
    generated_at = html.escape(data.get("generated_at", ""))
    return f"""<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>AI Token 用量监控</title>
  <style>
    :root {{
      --ink: #111827;
      --muted: #6b7280;
      --soft: #f3f4f6;
      --line: #e5e7eb;
      --panel: rgba(255, 255, 255, 0.96);
      --codex: #2563eb;
      --claude: #df7656;
    }}
    * {{ box-sizing: border-box; }}
    html, body {{ max-width: 100%; overflow-x: hidden; }}
    body {{
      margin: 0;
      min-height: 100vh;
      font-family: ui-sans-serif, -apple-system, BlinkMacSystemFont, "SF Pro Text", "PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", sans-serif;
      color: var(--ink);
      background:
        radial-gradient(circle at 15% 10%, rgba(255, 255, 255, 0.45), transparent 28%),
        linear-gradient(135deg, #ff7a6e 0%, #f0649f 48%, #f2a43a 100%);
      padding: 28px;
    }}
    .shell {{
      width: auto;
      max-width: 1180px;
      margin: 0 auto;
      background: var(--panel);
      border: 1px solid rgba(255,255,255,.75);
      border-radius: 28px;
      box-shadow: 0 32px 80px rgba(17, 24, 39, .18);
      padding: 34px clamp(20px, 4vw, 52px) 48px;
      overflow: hidden;
      min-width: 0;
    }}
    header {{
      display: flex;
      justify-content: space-between;
      align-items: flex-start;
      gap: 18px;
      margin-bottom: 28px;
    }}
    h1 {{
      margin: 0;
      font-size: clamp(30px, 4vw, 48px);
      line-height: 1.08;
      letter-spacing: 0;
    }}
    .updated {{
      margin-top: 8px;
      color: var(--muted);
      font-size: 14px;
    }}
    .actions {{
      display: flex;
      gap: 10px;
      align-items: center;
      color: var(--muted);
      white-space: nowrap;
      font-size: 16px;
    }}
    .cards {{
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      gap: 18px;
      margin-bottom: 22px;
    }}
    .metric, .panel {{
      border: 1px solid var(--line);
      background: #fff;
      border-radius: 16px;
    }}
    .metric {{
      padding: 26px 28px;
      min-height: 122px;
    }}
    .metric .value {{
      font-size: clamp(32px, 4vw, 46px);
      font-weight: 800;
      line-height: 1;
      letter-spacing: 0;
    }}
    .metric .label {{
      color: #9ca3af;
      margin-top: 10px;
      font-size: 18px;
      font-weight: 700;
    }}
    .panel {{
      padding: 28px;
      margin-top: 22px;
      overflow: hidden;
      min-width: 0;
    }}
    .panel h2 {{
      margin: 0 0 20px;
      font-size: 26px;
      letter-spacing: 0;
    }}
    .legend {{
      display: flex;
      gap: 22px;
      flex-wrap: wrap;
      color: var(--muted);
      font-size: 18px;
      margin-bottom: 18px;
    }}
    .legend span {{
      display: inline-flex;
      align-items: center;
      gap: 8px;
      font-weight: 700;
    }}
    .dot {{
      width: 12px;
      height: 12px;
      border-radius: 999px;
      display: inline-block;
    }}
    .chart-wrap {{
      height: 330px;
      display: grid;
      grid-template-rows: 1fr auto;
      gap: 10px;
    }}
    .chart {{
      height: 100%;
      display: flex;
      gap: 4px;
      align-items: flex-end;
      padding-top: 14px;
      border-bottom: 1px solid var(--line);
      overflow: hidden;
    }}
    .bar {{
      flex: 1 1 7px;
      min-width: 3px;
      max-width: 14px;
      height: 100%;
      display: flex;
      flex-direction: column-reverse;
      justify-content: flex-start;
      border-radius: 4px 4px 0 0;
      overflow: hidden;
      background: transparent;
    }}
    .seg {{ width: 100%; min-height: 1px; }}
    .axis {{
      display: flex;
      justify-content: space-between;
      color: #9ca3af;
      font-size: 16px;
      font-weight: 700;
    }}
    .rows {{
      display: grid;
      gap: 16px;
    }}
    .usage-row {{
      display: grid;
      grid-template-columns: minmax(110px, 170px) minmax(120px, 1fr) minmax(110px, auto);
      gap: 18px;
      align-items: center;
      min-height: 32px;
      min-width: 0;
    }}
    .name {{
      color: #4b5563;
      font-size: 19px;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }}
    .track {{
      height: 12px;
      background: #f1f3f6;
      border-radius: 999px;
      overflow: hidden;
    }}
    .fill {{
      height: 100%;
      border-radius: 999px;
      min-width: 4px;
    }}
    .amount {{
      color: #6b7280;
      font-size: 18px;
      font-weight: 700;
      text-align: right;
      white-space: nowrap;
    }}
    table {{
      width: 100%;
      border-collapse: collapse;
      font-size: 17px;
    }}
    th, td {{
      padding: 13px 6px;
      border-bottom: 1px solid #f0f1f3;
      text-align: right;
      white-space: nowrap;
    }}
    th:first-child, td:first-child {{ text-align: left; }}
    th {{
      color: #9ca3af;
      font-size: 15px;
      font-weight: 800;
    }}
    td {{
      color: #4b5563;
      font-weight: 650;
    }}
    td.total {{
      color: #111827;
      font-weight: 850;
    }}
    .source-grid {{
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      gap: 12px;
      color: var(--muted);
      font-size: 14px;
    }}
    .source {{
      background: #f9fafb;
      border: 1px solid #eef0f3;
      border-radius: 12px;
      padding: 12px;
    }}
    .source b {{
      color: var(--ink);
      display: block;
      margin-bottom: 6px;
    }}
    @media (max-width: 820px) {{
      body {{ padding: 12px; }}
      .shell {{ width: calc(100vw - 24px); border-radius: 22px; padding: 24px 16px 34px; }}
      .shell {{ width: auto; max-width: 100%; }}
      header {{ flex-direction: column; }}
      .cards, .source-grid {{ grid-template-columns: 1fr; }}
      .panel {{ padding: 20px 14px; }}
      .chart-wrap {{ height: 260px; }}
      .legend {{ gap: 12px; font-size: 15px; }}
      .chart {{ gap: 2px; }}
      .usage-row {{
        grid-template-columns: minmax(0, 1fr) auto;
        grid-template-areas:
          "name amount"
          "track track";
        column-gap: 10px;
        row-gap: 8px;
      }}
      .name {{ grid-area: name; font-size: 15px; }}
      .track {{ grid-area: track; }}
      .amount {{ grid-area: amount; font-size: 13px; line-height: 1.15; white-space: nowrap; }}
      .axis {{ font-size: 14px; gap: 12px; }}
      .axis span {{ min-width: 0; overflow: hidden; text-overflow: ellipsis; }}
      table {{ font-size: 14px; }}
      th, td {{ padding: 11px 4px; }}
    }}
  </style>
</head>
<body>
  <main class="shell">
    <header>
      <div>
        <h1>我的 AI 用量</h1>
        <div class="updated">更新于 {generated_at}</div>
      </div>
      <div class="actions">本地统计 · 不上传内容</div>
    </header>

    <section class="cards">
      <div class="metric"><div class="value" id="totalTokens">-</div><div class="label">总用量</div></div>
      <div class="metric"><div class="value" id="totalCost">-</div><div class="label">预估 Token 成本</div></div>
      <div class="metric"><div class="value" id="activeDays">-</div><div class="label">活跃天数</div></div>
    </section>

    <section class="panel">
      <h2>每天用量</h2>
      <div class="legend">
        <span><i class="dot" style="background:var(--codex)"></i>Codex</span>
        <span><i class="dot" style="background:var(--claude)"></i>Claude Code</span>
      </div>
      <div class="chart-wrap">
        <div class="chart" id="chart"></div>
        <div class="axis"><span id="firstDate">-</span><span id="lastDate">-</span></div>
      </div>
    </section>

    <section class="panel">
      <h2>按工具</h2>
      <div class="rows" id="tools"></div>
    </section>

    <section class="panel">
      <h2>按模型</h2>
      <div class="rows" id="models"></div>
    </section>

    <section class="panel">
      <h2>按天明细</h2>
      <div style="overflow:auto">
        <table>
          <thead>
            <tr>
              <th>日期</th><th>Codex</th><th>Claude Code</th><th>合计</th><th>预估成本</th>
            </tr>
          </thead>
          <tbody id="dailyRows"></tbody>
        </table>
      </div>
    </section>

    <section class="panel">
      <h2>数据源</h2>
      <div class="source-grid" id="sources"></div>
    </section>
  </main>

  <script>
    window.USAGE_DATA = {inline_data};
    const data = window.USAGE_DATA;
    const colors = {{ "Codex": "#2563eb", "Claude Code": "#df7656" }};
    const tools = ["Codex", "Claude Code"];

    function fmtTokens(n) {{
      n = Number(n || 0);
      if (n >= 100000000) return (n / 100000000).toFixed(2) + "亿";
      if (n >= 10000) return (n / 10000).toFixed(1) + "万";
      return Math.round(n).toString();
    }}
    function fmtMoney(n) {{
      return "$" + Number(n || 0).toLocaleString(undefined, {{ minimumFractionDigits: 2, maximumFractionDigits: 2 }});
    }}
    function shortDate(s) {{
      return String(s || "").slice(0, 10);
    }}
    function axisDate(s) {{
      const value = shortDate(s);
      return window.innerWidth < 520 ? value.slice(5) : value;
    }}

    document.getElementById("totalTokens").textContent = fmtTokens(data.totals.tokens);
    document.getElementById("totalCost").textContent = fmtMoney(data.totals.cost);
    document.getElementById("activeDays").textContent = data.totals.active_days;

    const chartData = data.daily.slice(-90);
    const max = Math.max(1, ...chartData.map(d => d.total_tokens));
    const chart = document.getElementById("chart");
    chart.innerHTML = chartData.map(day => {{
      const height = Math.max(1, day.total_tokens / max * 100);
      const segments = tools.map(tool => {{
        const value = day.tools[tool] || 0;
        if (!value) return "";
        const pct = Math.max(1, value / day.total_tokens * 100);
        return `<div class="seg" style="height:${{pct}}%;background:${{colors[tool]}}" title="${{tool}} ${{fmtTokens(value)}}"></div>`;
      }}).join("");
      return `<div class="bar" style="height:${{height}}%" title="${{day.date}} ${{fmtTokens(day.total_tokens)}}">${{segments}}</div>`;
    }}).join("");
    document.getElementById("firstDate").textContent = axisDate(chartData[0]?.date || "-");
    document.getElementById("lastDate").textContent = axisDate(chartData[chartData.length - 1]?.date || "-");

    function renderRows(id, rows, nameFn) {{
      const host = document.getElementById(id);
      const maxTokens = Math.max(1, ...rows.map(r => r.tokens));
      host.innerHTML = rows.slice(0, 12).map(row => {{
        const width = Math.max(1, row.tokens / maxTokens * 100);
        return `<div class="usage-row">
          <div class="name" title="${{nameFn(row)}}">${{nameFn(row)}}</div>
          <div class="track"><div class="fill" style="width:${{width}}%;background:${{row.color}}"></div></div>
          <div class="amount">${{fmtTokens(row.tokens)}} · ${{row.percent.toFixed(1)}}%</div>
        </div>`;
      }}).join("");
    }}
    renderRows("tools", data.tools, row => row.tool);
    renderRows("models", data.models, row => row.model);

    const dailyRows = document.getElementById("dailyRows");
    dailyRows.innerHTML = data.daily.slice().reverse().slice(0, 45).map(day => `
      <tr>
        <td>${{shortDate(day.date)}}</td>
        <td>${{day.tools.Codex ? fmtTokens(day.tools.Codex) : "—"}}</td>
        <td>${{day.tools["Claude Code"] ? fmtTokens(day.tools["Claude Code"]) : "—"}}</td>
        <td class="total">${{fmtTokens(day.total_tokens)}}</td>
        <td>${{fmtMoney(day.cost)}}</td>
      </tr>
    `).join("");

    const sources = document.getElementById("sources");
    sources.innerHTML = Object.entries(data.sources || {{}}).map(([name, meta]) => `
      <div class="source">
        <b>${{name}}</b>
        状态：${{meta.status || "unknown"}}<br>
        文件：${{meta.files || 0}} · 记录：${{meta.records || 0}}
      </div>
    `).join("");
  </script>
</body>
</html>
"""


def write_outputs(data: dict[str, Any]) -> None:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    tmp_json = DATA_JSON.with_suffix(".json.tmp")
    tmp_html = DASHBOARD_HTML.with_suffix(".html.tmp")
    tmp_json.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    tmp_json.replace(DATA_JSON)
    tmp_html.write_text(render_dashboard(data), encoding="utf-8")
    tmp_html.replace(DASHBOARD_HTML)


def print_summary(data: dict[str, Any]) -> None:
    print(f"generated_at: {data['generated_at']}")
    print(f"total_tokens: {human_tokens(data['totals']['tokens'])}")
    print(f"estimated_cost: ${data['totals']['cost']:.2f}")
    print(f"active_days: {data['totals']['active_days']}")
    print("tools:")
    for row in data["tools"]:
        print(f"  - {row['tool']}: {human_tokens(row['tokens'])} ({row['percent']:.1f}%)")


def main() -> int:
    args = parse_args()
    command = args.command or "collect"
    data = collect_all()
    write_outputs(data)
    if command == "print-summary":
        print_summary(data)
    elif command != "collect":
        print(f"Unknown command: {command}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
