#!/usr/bin/env python3
from __future__ import annotations

import datetime as dt
import json
import os
import plistlib
import subprocess
import sys
import threading
from pathlib import Path

from AppKit import (
    NSApp,
    NSApplication,
    NSApplicationActivationPolicyAccessory,
    NSBackingStoreBuffered,
    NSBezierPath,
    NSBezelStyleRounded,
    NSButton,
    NSColor,
    NSFont,
    NSFontWeightBold,
    NSFontWeightHeavy,
    NSFontWeightMedium,
    NSFontWeightRegular,
    NSFontWeightSemibold,
    NSGradient,
    NSImage,
    NSImageLeft,
    NSMakePoint,
    NSMakeRect,
    NSMakeSize,
    NSMinYEdge,
    NSMutableParagraphStyle,
    NSObject,
    NSPopover,
    NSPopoverBehaviorTransient,
    NSRoundLineCapStyle,
    NSStatusBar,
    NSVariableStatusItemLength,
    NSView,
    NSViewController,
    NSWindow,
    NSWindowStyleMaskClosable,
    NSWindowStyleMaskMiniaturizable,
    NSWindowStyleMaskResizable,
    NSWindowStyleMaskTitled,
    NSString,
)
from Foundation import NSTimer
from objc import python_method
from objc import super as objc_super


ROOT = Path(__file__).resolve().parents[1]
USAGE_JSON = ROOT / "data" / "usage.json"
SETTINGS_JSON = ROOT / "config" / "settings.json"
COLLECTOR = ROOT / "token_usage_monitor.py"
PYTHON = Path(sys.executable)
APP_BUNDLE = ROOT / "TokenUsageMenuApp" / "dist" / "TokenStep.app"
LAUNCH_AGENT_LABEL = "com.huangshu.TokenStep.prototype.login"
LAUNCH_AGENT = Path.home() / "Library" / "LaunchAgents" / f"{LAUNCH_AGENT_LABEL}.plist"

DEFAULT_SETTINGS = {
    "daily_goal_tokens": 100_000_000,
    "refresh_interval_seconds": 60,
    "history_days": 180,
}

APP_TITLE = "TokenStep"
APP_SUBTITLE = "今日 AI 步数"
PRIMARY = "#2da44e"
PRIMARY_DARK = "#216e39"
BLUE = PRIMARY
MINT = "#40c463"
GOLD = "#9be9a8"
GH_EMPTY = "#ebedf0"
GH_1 = "#9be9a8"
GH_2 = "#40c463"
GH_3 = "#30a14e"
GH_4 = "#216e39"
INK = "#121826"
MUTED = "#6b7280"
SOFT = "#f4f6fb"
LINE = "#e5e7eb"
SIDEBAR = "#f7f8fb"


def color(hex_value: str, alpha: float = 1.0) -> NSColor:
    value = hex_value.lstrip("#")
    red = int(value[0:2], 16) / 255
    green = int(value[2:4], 16) / 255
    blue = int(value[4:6], 16) / 255
    return NSColor.colorWithCalibratedRed_green_blue_alpha_(red, green, blue, alpha)


def load_settings() -> dict:
    settings = DEFAULT_SETTINGS.copy()
    try:
        with SETTINGS_JSON.open("r", encoding="utf-8") as f:
            loaded = json.load(f)
        if isinstance(loaded, dict):
            settings.update({k: loaded[k] for k in DEFAULT_SETTINGS if k in loaded})
    except Exception:
        pass
    return normalize_settings(settings)


def normalize_settings(settings: dict) -> dict:
    try:
        settings["daily_goal_tokens"] = max(1_000_000, int(settings.get("daily_goal_tokens", 100_000_000)))
    except Exception:
        settings["daily_goal_tokens"] = 100_000_000
    try:
        seconds = int(settings.get("refresh_interval_seconds", 60))
        settings["refresh_interval_seconds"] = seconds if seconds in [0, 60, 300, 900] else 60
    except Exception:
        settings["refresh_interval_seconds"] = 60
    try:
        settings["history_days"] = max(7, min(365, int(settings.get("history_days", 30))))
    except Exception:
        settings["history_days"] = 30
    return settings


def save_settings(settings: dict) -> None:
    SETTINGS_JSON.parent.mkdir(parents=True, exist_ok=True)
    with SETTINGS_JSON.open("w", encoding="utf-8") as f:
        json.dump(normalize_settings(settings), f, ensure_ascii=False, indent=2)
        f.write("\n")


def load_snapshot() -> dict:
    try:
        with USAGE_JSON.open("r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {
            "generated_at": "",
            "timezone": "Asia/Shanghai",
            "totals": {"tokens": 0, "cost": 0, "active_days": 0},
            "daily": [],
            "tools": [],
            "models": [],
            "sources": {},
        }


def autostart_enabled() -> bool:
    return LAUNCH_AGENT.exists()


def set_autostart(enabled: bool) -> None:
    LAUNCH_AGENT.parent.mkdir(parents=True, exist_ok=True)
    domain = f"gui/{os.getuid()}"
    if enabled:
        payload = {
            "Label": LAUNCH_AGENT_LABEL,
            "ProgramArguments": ["/usr/bin/open", str(APP_BUNDLE)],
            "RunAtLoad": True,
            "KeepAlive": False,
            "StandardOutPath": str(ROOT / "logs" / "login.out.log"),
            "StandardErrorPath": str(ROOT / "logs" / "login.err.log"),
        }
        (ROOT / "logs").mkdir(parents=True, exist_ok=True)
        with LAUNCH_AGENT.open("wb") as f:
            plistlib.dump(payload, f)
        subprocess.run(["launchctl", "bootout", domain, str(LAUNCH_AGENT)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(["launchctl", "bootstrap", domain, str(LAUNCH_AGENT)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return

    subprocess.run(["launchctl", "bootout", domain, str(LAUNCH_AGENT)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        LAUNCH_AGENT.unlink()
    except FileNotFoundError:
        pass


def trim_float(value: float, digits: int = 2) -> str:
    if digits <= 0:
        return f"{value:.0f}"
    text = f"{value:.{digits}f}"
    return text.rstrip("0").rstrip(".")


def format_tokens(value: int | float, compact: bool = False) -> str:
    value = int(value or 0)
    if value >= 100_000_000:
        return f"{trim_float(value / 100_000_000, 2)}亿"
    if value >= 10_000:
        digits = 0 if compact or value >= 10_000_000 else 1
        return f"{trim_float(value / 10_000, digits)}万"
    return str(value)


def format_money(value: int | float) -> str:
    return f"${float(value or 0):,.2f}"


def format_percent(value: float) -> str:
    if value >= 100:
        return f"{value:.0f}%"
    if value >= 10:
        return f"{value:.1f}%"
    return f"{value:.0f}%"


def short_date(value: str | None) -> str:
    if not value or len(value) < 10:
        return value or ""
    return value[5:10]


def generated_time(value: str | None) -> str:
    if not value:
        return "等待同步"
    return value.replace("T", " ")[:16]


def today_key() -> str:
    return dt.datetime.now().date().isoformat()


def parse_day(value: str | None) -> dt.date | None:
    if not value:
        return None
    try:
        return dt.date.fromisoformat(value[:10])
    except Exception:
        return None


def daily_rows(snapshot: dict) -> list[dict]:
    rows = snapshot.get("daily", [])
    return rows if isinstance(rows, list) else []


def today_row(snapshot: dict) -> dict:
    rows = daily_rows(snapshot)
    today = today_key()
    for row in reversed(rows):
        if row.get("date") == today:
            return row
    if rows:
        return rows[-1]
    return {"date": today, "tools": {}, "total_tokens": 0, "cost": 0}


def month_average(snapshot: dict) -> int:
    rows = daily_rows(snapshot)[-30:]
    if not rows:
        return 0
    return int(sum(int(row.get("total_tokens", 0) or 0) for row in rows) / len(rows))


def goal_progress(tokens: int, goal: int) -> float:
    return 0 if goal <= 0 else tokens / goal


def dominant_tool(row: dict) -> str:
    tools = row.get("tools", {}) if isinstance(row.get("tools"), dict) else {}
    if not tools:
        return "无"
    name, value = max(tools.items(), key=lambda item: item[1] or 0)
    return name if value else "无"


def active_goal_days(snapshot: dict, goal: int) -> int:
    return len([row for row in daily_rows(snapshot) if int(row.get("total_tokens", 0) or 0) >= goal])


def history_window_rows(snapshot: dict, days: int = 238) -> list[dict]:
    cutoff = dt.date.today() - dt.timedelta(days=days - 1)
    result = []
    for row in daily_rows(snapshot):
        day = parse_day(row.get("date"))
        if day and day >= cutoff:
            result.append(row)
    return result


def best_day(rows: list[dict]) -> dict:
    if not rows:
        return {"date": "", "total_tokens": 0, "cost": 0}
    return max(rows, key=lambda row: int(row.get("total_tokens", 0) or 0))


def tool_color(tool: str, alpha: float = 1.0) -> NSColor:
    if tool == "Codex":
        return color(GH_2, alpha)
    if tool == "Claude Code":
        return color(GH_3, alpha)
    if tool == "Gemini":
        return color(GH_4, alpha)
    return color("#7c8594", alpha)


def interval_label(seconds: int) -> str:
    if seconds == 0:
        return "手动"
    if seconds == 60:
        return "1 分钟"
    return f"{seconds // 60} 分钟"


def make_status_image(progress: float, refreshing: bool = False) -> NSImage:
    image = NSImage.alloc().initWithSize_(NSMakeSize(22, 22))
    image.lockFocus()
    center = NSMakePoint(11, 11)
    track = NSBezierPath.bezierPath()
    track.appendBezierPathWithArcWithCenter_radius_startAngle_endAngle_clockwise_(center, 7.8, 0, 360, False)
    track.setLineWidth_(2.7)
    color(GH_EMPTY, 0.95).setStroke()
    track.stroke()

    value = min(max(progress, 0), 1)
    if value > 0:
        arc = NSBezierPath.bezierPath()
        arc.appendBezierPathWithArcWithCenter_radius_startAngle_endAngle_clockwise_(
            center, 7.8, 90, 90 - 360 * value, True
        )
        arc.setLineWidth_(2.7)
        arc.setLineCapStyle_(NSRoundLineCapStyle)
        color(PRIMARY).setStroke()
        arc.stroke()

    dot_color = color(PRIMARY)
    dot_color.setFill()
    NSBezierPath.bezierPathWithOvalInRect_(NSMakeRect(8.4, 8.4, 5.2, 5.2)).fill()
    image.unlockFocus()
    image.setTemplate_(False)
    return image


class CanvasBase(NSView):
    def isFlipped(self):
        return True

    @python_method
    def rounded(self, rect, radius: float):
        return NSBezierPath.bezierPathWithRoundedRect_xRadius_yRadius_(rect, radius, radius)

    @python_method
    def text(self, value, x, y, w, h, size, weight=NSFontWeightRegular, text_color=None, align="left"):
        paragraph = NSMutableParagraphStyle.alloc().init()
        if align == "center":
            paragraph.setAlignment_(1)
        elif align == "right":
            paragraph.setAlignment_(2)
        attrs = {
            "NSFont": NSFont.systemFontOfSize_weight_(size, weight),
            "NSColor": text_color or color(INK),
            "NSParagraphStyle": paragraph,
        }
        NSString.stringWithString_(str(value)).drawInRect_withAttributes_(NSMakeRect(x, y, w, h), attrs)

    @python_method
    def fit_text(self, value, x, y, w, h, max_size, min_size, weight=NSFontWeightRegular, text_color=None, align="left"):
        rendered = str(value)
        size = max_size
        while size > min_size:
            font = NSFont.systemFontOfSize_weight_(size, weight)
            measured = NSString.stringWithString_(rendered).sizeWithAttributes_({"NSFont": font})
            if measured.width <= w:
                break
            size -= 1
        self.text(rendered, x, y, w, h, size, weight, text_color, align)

    @python_method
    def card(self, rect, radius=22, fill=None, stroke=None):
        path = self.rounded(rect, radius)
        (fill or NSColor.whiteColor().colorWithAlphaComponent_(0.86)).setFill()
        path.fill()
        (stroke or color(LINE, 0.9)).setStroke()
        path.setLineWidth_(1)
        path.stroke()

    @python_method
    def pill(self, rect, fill, stroke=None, radius=14):
        path = self.rounded(rect, radius)
        fill.setFill()
        path.fill()
        if stroke:
            stroke.setStroke()
            path.setLineWidth_(1)
            path.stroke()

    @python_method
    def ring(self, rect, progress, line_width, track_color, progress_color):
        size = rect.size.width
        center = NSMakePoint(rect.origin.x + size / 2, rect.origin.y + size / 2)
        radius = size / 2 - line_width / 2
        track = NSBezierPath.bezierPath()
        track.appendBezierPathWithArcWithCenter_radius_startAngle_endAngle_clockwise_(center, radius, 0, 360, False)
        track.setLineWidth_(line_width)
        track_color.setStroke()
        track.stroke()

        value = min(max(progress, 0), 1.0)
        if value <= 0:
            return
        arc = NSBezierPath.bezierPath()
        arc.appendBezierPathWithArcWithCenter_radius_startAngle_endAngle_clockwise_(
            center, radius, -90, -90 + 360 * value, False
        )
        arc.setLineWidth_(line_width)
        arc.setLineCapStyle_(NSRoundLineCapStyle)
        progress_color.setStroke()
        arc.stroke()

    @python_method
    def mini_bars(self, rows, x, y, w, h, goal, max_count=30):
        days = rows[-max_count:]
        if not days:
            self.text("暂无历史数据", x, y + 18, w, 18, 12, NSFontWeightMedium, color(MUTED))
            return
        gap = 4
        bar_w = max(4, (w - gap * max(len(days) - 1, 0)) / max(len(days), 1))
        max_tokens = max([int(day.get("total_tokens", 0) or 0) for day in days] + [goal, 1])
        goal_y = y + h - h * min(goal / max_tokens, 1)
        color(LINE, 0.9).setStroke()
        line = NSBezierPath.bezierPath()
        line.moveToPoint_(NSMakePoint(x, goal_y))
        line.lineToPoint_(NSMakePoint(x + w, goal_y))
        line.setLineWidth_(1)
        line.stroke()
        for index, day in enumerate(days):
            tokens = int(day.get("total_tokens", 0) or 0)
            bar_h = max(3, h * tokens / max_tokens) if tokens else 3
            bx = x + index * (bar_w + gap)
            by = y + h - bar_h
            fill = self.contribution_color(tokens, goal)
            fill.setFill()
            self.rounded(NSMakeRect(bx, by, bar_w, bar_h), min(4, bar_w / 2)).fill()
        self.text(short_date(days[0].get("date")), x, y + h + 8, 72, 15, 10, NSFontWeightMedium, color("#9aa3b2"))
        self.text(short_date(days[-1].get("date")), x + w - 72, y + h + 8, 72, 15, 10, NSFontWeightMedium, color("#9aa3b2"), align="right")

    @python_method
    def progress_row(self, x, y, w, name, value_text, percent, fill_color):
        name_w = min(120, max(82, w * 0.32))
        value_w = 140 if w >= 500 else (108 if w >= 360 else 82)
        self.text(name, x, y - 2, name_w, 18, 12, NSFontWeightSemibold, color("#475569"))
        self.text(value_text, x + w - value_w, y - 2, value_w, 18, 12, NSFontWeightSemibold, color("#475569"), align="right")
        tx = x + name_w + 14
        tw = max(28, w - name_w - value_w - 28)
        self.pill(NSMakeRect(tx, y + 6, tw, 7), color("#edf0f5"), radius=4)
        if percent > 0:
            self.pill(NSMakeRect(tx, y + 6, max(5, tw * min(percent, 100) / 100), 7), fill_color, radius=4)

    @python_method
    def scroll_indicator(self, x, y, h, total, visible, offset):
        if total <= visible:
            return
        track = NSMakeRect(x, y, 4, h)
        self.pill(track, color("#eef1f5"), radius=2)
        knob_h = max(26, h * visible / total)
        max_offset = max(1, total - visible)
        knob_y = y + (h - knob_h) * min(max(offset, 0), max_offset) / max_offset
        self.pill(NSMakeRect(x, knob_y, 4, knob_h), color("#b8c2cf"), radius=2)

    @python_method
    def contribution_color(self, tokens, goal):
        if tokens <= 0:
            return color(GH_EMPTY)
        progress = min(goal_progress(int(tokens), int(goal)), 1)
        if progress >= 1:
            return color(GH_4)
        if progress >= 0.65:
            return color(GH_3)
        if progress >= 0.35:
            return color(GH_2)
        if progress >= 0.12:
            return color(GH_1)
        return color("#d8f3dc")

    @python_method
    def contribution_wall(self, rows, x, y, weeks, cell, gap, goal):
        row_by_day = {}
        for item in rows:
            day = parse_day(item.get("date"))
            if day:
                row_by_day[day] = item

        end_day = dt.date.today()
        start_day = end_day - dt.timedelta(weeks=weeks - 1)
        start_day = start_day - dt.timedelta(days=start_day.weekday())
        month_seen = set()

        weekdays = [(0, "一"), (2, "三"), (4, "五")]
        for day_index, label in weekdays:
            self.text(label, x - 22, y + day_index * (cell + gap) - 1, 14, 12, 9, NSFontWeightMedium, color("#9aa3b2"))

        for col in range(weeks):
            week_start = start_day + dt.timedelta(days=col * 7)
            if week_start.day <= 7 and week_start.month not in month_seen:
                month_seen.add(week_start.month)
                self.text(f"{week_start.month}月", x + col * (cell + gap), y - 21, 36, 12, 9, NSFontWeightSemibold, color("#9aa3b2"))
            for row in range(7):
                day = week_start + dt.timedelta(days=row)
                if day > end_day:
                    continue
                item = row_by_day.get(day, {})
                tokens = int(item.get("total_tokens", 0) or 0)
                rect = NSMakeRect(x + col * (cell + gap), y + row * (cell + gap), cell, cell)
                self.pill(rect, self.contribution_color(tokens, goal), None, 3)
                if day == end_day:
                    color(PRIMARY_DARK, 0.82).setStroke()
                    path = self.rounded(rect, 3)
                    path.setLineWidth_(1.4)
                    path.stroke()


class PopoverCanvas(CanvasBase):
    def initWithFrame_(self, frame):
        self = objc_super(PopoverCanvas, self).initWithFrame_(frame)
        if self is None:
            return None
        self.snapshot = load_snapshot()
        self.settings = load_settings()
        self.refreshing = False
        return self

    def setState_settings_refreshing_(self, snapshot, settings, refreshing):
        self.snapshot = snapshot
        self.settings = settings
        self.refreshing = refreshing
        self.setNeedsDisplay_(True)

    def drawRect_(self, dirty_rect):
        bounds = self.bounds()
        gradient = NSGradient.alloc().initWithColors_(
            [color("#f7fff8"), color("#fbfefa"), color("#ffffff")]
        )
        gradient.drawInRect_angle_(bounds, -90)
        self.draw_header()
        self.draw_today()
        self.draw_trend()
        self.draw_footer()

    @python_method
    def draw_header(self):
        self.text(APP_TITLE, 24, 22, 155, 26, 20, NSFontWeightHeavy, color(INK))
        self.text("像步数一样记录每天的 AI 使用量", 24, 51, 220, 18, 11, NSFontWeightMedium, color(MUTED))
        status = "同步中" if self.refreshing else "已同步"
        self.pill(NSMakeRect(300, 28, 66, 24), color("#eff4ff" if self.refreshing else "#f2f4f7"), radius=12)
        self.text(status, 300, 33, 66, 14, 10, NSFontWeightSemibold, color(BLUE if self.refreshing else MUTED), align="center")

    @python_method
    def draw_today(self):
        row = today_row(self.snapshot)
        goal = int(self.settings["daily_goal_tokens"])
        tokens = int(row.get("total_tokens", 0) or 0)
        progress = goal_progress(tokens, goal)

        self.card(NSMakeRect(18, 86, 354, 238), 28, NSColor.whiteColor().colorWithAlphaComponent_(0.92))
        self.text(APP_SUBTITLE, 38, 108, 128, 20, 14, NSFontWeightBold, color(INK))
        self.text(today_key(), 268, 109, 76, 16, 10, NSFontWeightSemibold, color("#9aa3b2"), align="right")

        self.ring(NSMakeRect(46, 142, 132, 132), progress, 15, color(GH_EMPTY), color(PRIMARY))
        self.fit_text(format_tokens(tokens), 58, 183, 108, 30, 25, 18, NSFontWeightHeavy, color(INK), align="center")
        self.text(f"/ {format_tokens(goal, compact=True)}", 72, 216, 82, 16, 11, NSFontWeightMedium, color(MUTED), align="center")

        pct = min(progress * 100, 999)
        self.text("今日已完成", 218, 152, 112, 18, 12, NSFontWeightBold, color("#9aa3b2"), align="right")
        self.text(format_percent(pct), 222, 176, 108, 30, 25, NSFontWeightHeavy, color(INK), align="right")
        self.text("目标 1 亿", 236, 212, 94, 16, 11, NSFontWeightSemibold, color(MUTED), align="right")

        metrics = [
            ("消耗金额", format_money(row.get("cost", 0))),
            ("活跃天数", f"{self.snapshot.get('totals', {}).get('active_days', 0)} 天"),
            ("本月均值", format_tokens(month_average(self.snapshot), compact=True)),
        ]
        for index, (label, value) in enumerate(metrics):
            x = 38 + index * 104
            self.pill(NSMakeRect(x, 286, 92, 24), color("#f6faf7"), radius=12)
            self.text(label, x + 8, 291, 40, 13, 9, NSFontWeightSemibold, color("#9aa3b2"))
            self.text(value, x + 36, 291, 48, 13, 9, NSFontWeightBold, color(INK), align="right")

    @python_method
    def draw_trend(self):
        self.card(NSMakeRect(18, 340, 354, 118), 22, NSColor.whiteColor().colorWithAlphaComponent_(0.86))
        self.text("最近 30 天", 36, 357, 120, 18, 13, NSFontWeightBold, color(INK))
        self.text("细线是每日目标", 238, 359, 100, 14, 10, NSFontWeightMedium, color("#9aa3b2"), align="right")
        self.mini_bars(daily_rows(self.snapshot), 36, 386, 318, 44, int(self.settings["daily_goal_tokens"]), 30)

    @python_method
    def draw_footer(self):
        self.text("本地统计 · 不上传代码或对话", 22, 468, 170, 16, 10, NSFontWeightMedium, color("#9aa3b2"))
        self.text("刷新 " + interval_label(int(self.settings["refresh_interval_seconds"])), 260, 468, 108, 16, 10, NSFontWeightMedium, color("#9aa3b2"), align="right")


class PopoverController(NSViewController):
    def initWithAppDelegate_(self, delegate):
        self = objc_super(PopoverController, self).init()
        if self is None:
            return None
        self.delegate = delegate
        return self

    def loadView(self):
        root = FlippedRootView.alloc().initWithFrame_(NSMakeRect(0, 0, 390, 520))
        self.canvas = PopoverCanvas.alloc().initWithFrame_(NSMakeRect(0, 0, 390, 520))
        root.addSubview_(self.canvas)
        self.add_button(root, "打开", 194, 486, 58, "openApp:")
        self.add_button(root, "刷新", 258, 486, 52, "refresh:")
        self.add_button(root, "退出", 316, 486, 52, "quit:")
        self.setView_(root)

    @python_method
    def add_button(self, root, title, x, y, w, action):
        button = NSButton.buttonWithTitle_target_action_(title, self, action)
        button.setFrame_(NSMakeRect(x, y, w, 24))
        button.setBezelStyle_(NSBezelStyleRounded)
        button.setFont_(NSFont.systemFontOfSize_weight_(11, NSFontWeightSemibold))
        root.addSubview_(button)

    def updateWithState_settings_refreshing_(self, snapshot, settings, refreshing):
        if hasattr(self, "canvas"):
            self.canvas.setState_settings_refreshing_(snapshot, settings, refreshing)

    def openApp_(self, sender):
        if hasattr(self.delegate, "popover") and self.delegate.popover.isShown():
            self.delegate.popover.performClose_(sender)
        self.delegate.openMainWindow()

    def refresh_(self, sender):
        self.delegate.refreshData()

    def quit_(self, sender):
        NSApp.terminate_(None)


class MainWindowCanvas(CanvasBase):
    def initWithFrame_(self, frame):
        self = objc_super(MainWindowCanvas, self).initWithFrame_(frame)
        if self is None:
            return None
        self.snapshot = load_snapshot()
        self.settings = load_settings()
        self.page = "today"
        self.refreshing = False
        self.history_offset = 0
        return self

    def setState_settings_page_refreshing_(self, snapshot, settings, page, refreshing):
        self.snapshot = snapshot
        self.settings = settings
        self.page = page
        self.refreshing = refreshing
        if page != "history":
            self.history_offset = 0
        else:
            rows = daily_rows(snapshot)
            visible = 8
            max_offset = max(0, min(len(rows), int(settings.get("history_days", 180))) - visible)
            self.history_offset = min(max(self.history_offset, 0), max_offset)
        self.setNeedsDisplay_(True)

    def acceptsFirstResponder(self):
        return True

    def scrollWheel_(self, event):
        if self.page != "history":
            objc_super(MainWindowCanvas, self).scrollWheel_(event)
            return
        total = min(len(daily_rows(self.snapshot)), int(self.settings.get("history_days", 180)))
        visible = 8
        max_offset = max(0, total - visible)
        if max_offset <= 0:
            return
        delta = float(event.scrollingDeltaY())
        if delta == 0:
            delta = float(event.deltaY())
        if delta == 0:
            return
        step = max(1, min(6, int(abs(delta) / 8) + 1))
        if delta < 0:
            self.history_offset = min(max_offset, self.history_offset + step)
        else:
            self.history_offset = max(0, self.history_offset - step)
        self.setNeedsDisplay_(True)

    def drawRect_(self, dirty_rect):
        bounds = self.bounds()
        NSColor.whiteColor().setFill()
        NSBezierPath.fillRect_(bounds)
        color(SIDEBAR).setFill()
        NSBezierPath.fillRect_(NSMakeRect(0, 0, 188, bounds.size.height))
        color(LINE, 0.9).setStroke()
        line = NSBezierPath.bezierPath()
        line.moveToPoint_(NSMakePoint(188, 0))
        line.lineToPoint_(NSMakePoint(188, bounds.size.height))
        line.stroke()
        self.draw_sidebar()
        if self.page == "history":
            self.draw_history()
        elif self.page == "stats":
            self.draw_stats()
        elif self.page == "settings":
            self.draw_settings()
        elif self.page == "privacy":
            self.draw_privacy()
        else:
            self.draw_today()

    @python_method
    def draw_sidebar(self):
        self.text(APP_TITLE, 28, 32, 120, 30, 23, NSFontWeightHeavy, color(INK))
        self.text("每天一个亿", 30, 64, 110, 18, 12, NSFontWeightSemibold, color(PRIMARY))
        navs = [("today", "今日"), ("history", "历史"), ("stats", "统计"), ("settings", "设置"), ("privacy", "隐私")]
        for index, (page, title) in enumerate(navs):
            y = 128 + index * 48
            active = self.page == page
            if active:
                self.pill(NSMakeRect(20, y, 140, 36), color("#ffffff"), color(LINE, 0.85), 12)
                self.pill(NSMakeRect(28, y + 9, 4, 18), color(PRIMARY), radius=2)
            self.text(title, 44, y + 9, 80, 18, 13, NSFontWeightBold if active else NSFontWeightSemibold, color(INK if active else MUTED))
        self.text("本地统计", 30, 600, 90, 16, 11, NSFontWeightBold, color("#9aa3b2"))
        self.text("不上传代码或对话", 30, 620, 118, 16, 11, NSFontWeightMedium, color("#9aa3b2"))

    @python_method
    def draw_page_header(self, title, subtitle):
        self.text(title, 224, 34, 260, 34, 28, NSFontWeightHeavy, color(INK))
        self.text(subtitle, 226, 70, 420, 18, 12, NSFontWeightMedium, color(MUTED))
        sync = "同步中" if self.refreshing else "更新 " + generated_time(self.snapshot.get("generated_at"))
        self.text(sync, 586, 43, 208, 18, 12, NSFontWeightMedium, color(BLUE if self.refreshing else MUTED), align="right")

    @python_method
    def draw_today(self):
        self.draw_page_header(APP_SUBTITLE, "像步数一样，记录每天和 AI 一起走过的路。")
        row = today_row(self.snapshot)
        goal = int(self.settings["daily_goal_tokens"])
        tokens = int(row.get("total_tokens", 0) or 0)
        progress = goal_progress(tokens, goal)

        hero = NSMakeRect(224, 112, 670, 224)
        self.card(hero, 28, color("#fcfffd"))
        self.ring(NSMakeRect(260, 146, 154, 154), progress, 17, color(GH_EMPTY), color(PRIMARY))
        self.fit_text(format_tokens(tokens), 276, 196, 122, 34, 30, 20, NSFontWeightHeavy, color(INK), align="center")
        self.text(f"目标 {format_tokens(goal, compact=True)}", 292, 234, 90, 18, 12, NSFontWeightSemibold, color(MUTED), align="center")

        self.text("今日已完成", 470, 150, 140, 18, 12, NSFontWeightBold, color("#9aa3b2"))
        self.text(format_percent(min(progress * 100, 999)), 468, 174, 142, 42, 34, NSFontWeightHeavy, color(INK))
        self.text("像步数一样自然累积", 472, 222, 190, 18, 13, NSFontWeightSemibold, color(MUTED))

        metrics = [
            ("消耗金额", format_money(row.get("cost", 0))),
            ("本月均值", format_tokens(month_average(self.snapshot))),
            ("达标天数", f"{active_goal_days(self.snapshot, goal)} 天"),
        ]
        for index, (label, value) in enumerate(metrics):
            x = 470 + index * 128
            self.pill(NSMakeRect(x, 268, 112, 42), color("#f6faf7"), color(LINE, 0.8), 14)
            self.text(label, x + 12, 277, 88, 13, 10, NSFontWeightBold, color("#9aa3b2"))
            self.text(value, x + 12, 292, 88, 16, 13, NSFontWeightHeavy, color(INK))

        self.card(NSMakeRect(224, 360, 670, 154), 24, color("#ffffff"))
        self.text("最近 30 天", 248, 380, 120, 20, 15, NSFontWeightBold, color(INK))
        self.text("细线是每日目标", 744, 383, 116, 16, 11, NSFontWeightMedium, color("#9aa3b2"), align="right")
        self.mini_bars(daily_rows(self.snapshot), 248, 416, 606, 58, goal, 30)

        self.card(NSMakeRect(224, 538, 320, 126), 22, color("#ffffff"))
        self.text("按工具", 248, 558, 120, 18, 15, NSFontWeightBold, color(INK))
        for index, item in enumerate(self.snapshot.get("tools", [])[:3]):
            percent = float(item.get("percent", 0) or 0)
            self.progress_row(
                248,
                590 + index * 24,
                262,
                item.get("tool", ""),
                format_tokens(item.get("tokens", 0), compact=True),
                percent,
                tool_color(item.get("tool", "")),
            )

        self.card(NSMakeRect(574, 538, 320, 126), 22, color("#ffffff"))
        self.text("主力模型", 598, 558, 120, 18, 15, NSFontWeightBold, color(INK))
        for index, item in enumerate(self.snapshot.get("models", [])[:3]):
            percent = float(item.get("percent", 0) or 0)
            name = item.get("model", "")
            if len(name) > 18:
                name = name[:17] + "…"
            self.progress_row(
                598,
                590 + index * 24,
                262,
                name,
                format_tokens(item.get("tokens", 0), compact=True),
                percent,
                tool_color(item.get("tool", "")),
            )

    @python_method
    def draw_stats(self):
        self.draw_page_header("统计", "按客户端和模型，看见累计 AI 步数都走到了哪里。")
        totals = self.snapshot.get("totals", {}) if isinstance(self.snapshot.get("totals"), dict) else {}
        total_tokens = int(totals.get("tokens", 0) or 0)
        total_cost = float(totals.get("cost", 0) or 0)
        active_days = int(totals.get("active_days", 0) or 0)

        self.card(NSMakeRect(224, 112, 670, 100), 24, color("#fcfffd"))
        summaries = [
            ("累计 AI 步数", format_tokens(total_tokens)),
            ("消耗金额", format_money(total_cost)),
            ("活跃天数", f"{active_days} 天"),
        ]
        for index, (label, value) in enumerate(summaries):
            x = 248 + index * 214
            self.text(label, x, 136, 140, 15, 11, NSFontWeightBold, color("#9aa3b2"))
            self.fit_text(value, x, 158, 158, 30, 24, 14, NSFontWeightHeavy, color(INK))

        tools = self.snapshot.get("tools", [])
        tools = tools if isinstance(tools, list) else []
        self.card(NSMakeRect(224, 238, 670, 146), 24, color("#ffffff"))
        self.text("按客户端", 248, 260, 140, 20, 15, NSFontWeightBold, color(INK))
        self.text("累计总量分布", 746, 263, 112, 14, 10, NSFontWeightMedium, color("#9aa3b2"), align="right")
        if not tools:
            self.text("暂无客户端统计", 248, 304, 180, 18, 12, NSFontWeightMedium, color(MUTED))
        for index, item in enumerate(tools[:3]):
            self.progress_row(
                248,
                302 + index * 28,
                610,
                item.get("tool", ""),
                f"{format_tokens(item.get('tokens', 0), compact=True)} · {format_percent(float(item.get('percent', 0) or 0))}",
                float(item.get("percent", 0) or 0),
                tool_color(item.get("tool", "")),
            )

        models = self.snapshot.get("models", [])
        models = models if isinstance(models, list) else []
        self.card(NSMakeRect(224, 410, 670, 258), 24, color("#ffffff"))
        self.text("按模型", 248, 432, 140, 20, 15, NSFontWeightBold, color(INK))
        model_note = f"Top {min(len(models), 10)} / {len(models)}" if models else "暂无"
        self.text(model_note, 782, 435, 76, 14, 10, NSFontWeightMedium, color("#9aa3b2"), align="right")
        if not models:
            self.text("暂无模型统计", 248, 474, 180, 18, 12, NSFontWeightMedium, color(MUTED))
        for index, item in enumerate(models[:10]):
            name = item.get("model", "")
            if len(name) > 28:
                name = name[:27] + "…"
            self.progress_row(
                248,
                472 + index * 21,
                610,
                name,
                f"{format_tokens(item.get('tokens', 0), compact=True)} · {format_percent(float(item.get('percent', 0) or 0))}",
                float(item.get("percent", 0) or 0),
                tool_color(item.get("tool", "")),
            )

    @python_method
    def draw_history(self):
        self.draw_page_header("历史", "像 GitHub 活动墙一样，看见自己的 AI 使用节奏。")
        all_rows = daily_rows(self.snapshot)
        window_rows = history_window_rows(self.snapshot, 238)
        rows = list(reversed(all_rows[-int(self.settings["history_days"]):]))
        goal = int(self.settings["daily_goal_tokens"])

        active_days = len([row for row in window_rows if int(row.get("total_tokens", 0) or 0) > 0])
        goal_days = len([row for row in window_rows if int(row.get("total_tokens", 0) or 0) >= goal])
        high = best_day(window_rows)
        wall_cost = sum(float(row.get("cost", 0) or 0) for row in window_rows)

        self.card(NSMakeRect(224, 112, 670, 252), 24, color("#ffffff"))
        self.text("近 8 个月活动墙", 248, 132, 160, 20, 15, NSFontWeightBold, color(INK))
        self.text("颜色越深，越接近或超过当天目标", 694, 135, 164, 14, 10, NSFontWeightMedium, color("#9aa3b2"), align="right")
        self.contribution_wall(window_rows, 280, 184, 34, 13, 4, goal)

        stats = [
            ("活跃", f"{active_days} 天"),
            ("达标", f"{goal_days} 天"),
            ("最高", format_tokens(high.get("total_tokens", 0), compact=True)),
            ("消耗", f"${wall_cost:,.0f}"),
        ]
        for index, (label, value) in enumerate(stats):
            x = 248 + index * 112
            self.pill(NSMakeRect(x, 320, 96, 26), color("#f6faf7"), color(LINE, 0.8), 13)
            self.text(label, x + 10, 327, 36, 11, 9, NSFontWeightBold, color("#9aa3b2"))
            self.text(value, x + 42, 326, 44, 12, 10, NSFontWeightHeavy, color(INK), align="right")

        legend_x = 734
        self.text("少", legend_x, 327, 16, 11, 9, NSFontWeightMedium, color("#9aa3b2"))
        for idx, sample in enumerate([0, int(goal * 0.18), int(goal * 0.45), int(goal * 0.75), goal]):
            self.pill(NSMakeRect(754 + idx * 18, 324, 13, 13), self.contribution_color(sample, goal), None, 3)
        self.text("多", 848, 327, 16, 11, 9, NSFontWeightMedium, color("#9aa3b2"), align="right")

        self.card(NSMakeRect(224, 392, 670, 286), 24, color("#ffffff"))
        self.text("近期明细", 248, 414, 120, 20, 15, NSFontWeightBold, color(INK))
        visible_count = 8
        total_rows = len(rows)
        max_offset = max(0, total_rows - visible_count)
        self.history_offset = min(max(self.history_offset, 0), max_offset)
        visible_rows = rows[self.history_offset:self.history_offset + visible_count]
        if total_rows > visible_count:
            start = self.history_offset + 1
            end = min(self.history_offset + visible_count, total_rows)
            self.text(f"{start}-{end} / {total_rows}", 790, 417, 68, 14, 10, NSFontWeightMedium, color("#9aa3b2"), align="right")
        headers = [("日期", 248, 74), ("AI 步数", 350, 104), ("完成率", 484, 86), ("消耗金额", 594, 96), ("主力工具", 732, 110)]
        for title, x, w in headers:
            self.text(title, x, 446, w, 16, 11, NSFontWeightBold, color("#9aa3b2"))
        if not visible_rows:
            self.text("暂无历史明细", 248, 494, 160, 18, 12, NSFontWeightMedium, color(MUTED))
            return
        y = 478
        for index, row in enumerate(visible_rows):
            tokens = int(row.get("total_tokens", 0) or 0)
            progress = goal_progress(tokens, goal) * 100
            if index > 0:
                color(LINE, 0.65).setStroke()
                sep = NSBezierPath.bezierPath()
                sep.moveToPoint_(NSMakePoint(248, y - 10))
                sep.lineToPoint_(NSMakePoint(858, y - 10))
                sep.stroke()
            self.text(row.get("date", ""), 248, y, 86, 20, 13, NSFontWeightSemibold, color("#536071"))
            self.text(format_tokens(tokens), 350, y, 104, 20, 13, NSFontWeightHeavy, color(INK))
            pct_color = color(PRIMARY_DARK) if progress >= 100 else color(MUTED)
            self.text(format_percent(progress), 484, y, 82, 20, 13, NSFontWeightBold, pct_color)
            self.text(format_money(row.get("cost", 0)), 594, y, 96, 20, 13, NSFontWeightSemibold, color("#536071"))
            self.text(dominant_tool(row), 732, y, 120, 20, 13, NSFontWeightSemibold, color("#536071"))
            y += 25
        self.scroll_indicator(866, 478, 182, total_rows, visible_count, self.history_offset)

    @python_method
    def draw_settings(self):
        self.draw_page_header("设置", "第一版先把目标和刷新频率做稳。")
        goal = int(self.settings["daily_goal_tokens"])
        interval = int(self.settings["refresh_interval_seconds"])

        self.card(NSMakeRect(224, 112, 670, 170), 24, color("#ffffff"))
        self.text("每日目标", 248, 136, 140, 20, 16, NSFontWeightBold, color(INK))
        self.text(format_tokens(goal), 248, 168, 180, 42, 38, NSFontWeightHeavy, color(PRIMARY))
        self.text("默认每天一个亿，可以按自己的节奏增减。", 250, 218, 280, 18, 12, NSFontWeightMedium, color(MUTED))

        self.card(NSMakeRect(224, 310, 670, 170), 24, color("#ffffff"))
        self.text("自动刷新", 248, 334, 140, 20, 16, NSFontWeightBold, color(INK))
        self.text(f"当前：{interval_label(interval)}", 248, 366, 170, 24, 18, NSFontWeightHeavy, color(INK))
        self.text("1 分钟会更及时，但会更频繁地读取本机用量记录。", 250, 400, 360, 18, 12, NSFontWeightMedium, color(MUTED))
        options = [(60, "1 分钟"), (300, "5 分钟"), (900, "15 分钟"), (0, "手动")]
        for index, (seconds, label) in enumerate(options):
            x = 248 + index * 112
            active = interval == seconds
            self.pill(NSMakeRect(x, 436, 92, 26), color(PRIMARY if active else "#f2f4f7"), color(LINE, 0.8), 13)
            self.text(label, x, 442, 92, 14, 11, NSFontWeightBold, NSColor.whiteColor() if active else color(MUTED), align="center")

        self.card(NSMakeRect(224, 508, 670, 134), 24, color("#ffffff"))
        self.text("开机自启动", 248, 532, 140, 20, 16, NSFontWeightBold, color(INK))
        self.text("开启后，TokenStep 会在登录后自动常驻菜单栏，避免漏记每日 AI 步数。", 248, 566, 500, 18, 12, NSFontWeightMedium, color(MUTED))
        enabled = autostart_enabled()
        self.pill(NSMakeRect(764, 532, 92, 30), color(PRIMARY if enabled else "#f2f4f7"), color(LINE, 0.75), 15)
        self.text("已开启" if enabled else "开启", 764, 540, 92, 14, 11, NSFontWeightBold, NSColor.whiteColor() if enabled else color(MUTED), align="center")
        self.text(str(LAUNCH_AGENT), 248, 604, 500, 14, 10, NSFontWeightMedium, color("#9aa3b2"))

    @python_method
    def draw_privacy(self):
        self.draw_page_header("隐私", "TokenStep 的第一原则：只统计数量。")
        self.card(NSMakeRect(224, 112, 670, 236), 28, color("#ffffff"))
        items = [
            ("只统计 token 数量", "用于计算今日 AI 步数、历史趋势和消耗金额。"),
            ("不上传代码或对话", "所有数据文件都保留在这台 Mac 上。"),
            ("消耗金额仅供参考", "按本地价格表粗略估算，不等于真实账单。"),
        ]
        for index, (title, desc) in enumerate(items):
            y = 146 + index * 62
            self.pill(NSMakeRect(250, y, 34, 34), color("#eef8f0"), None, 17)
            self.text(str(index + 1), 250, y + 8, 34, 16, 13, NSFontWeightHeavy, color(PRIMARY), align="center")
            self.text(title, 304, y + 2, 240, 20, 16, NSFontWeightBold, color(INK))
            self.text(desc, 304, y + 27, 430, 18, 12, NSFontWeightMedium, color(MUTED))

        self.card(NSMakeRect(224, 382, 670, 166), 24, color("#ffffff"))
        self.text("本地文件", 248, 408, 140, 20, 16, NSFontWeightBold, color(INK))
        self.text(str(USAGE_JSON), 248, 444, 580, 18, 11, NSFontWeightMedium, color("#536071"))
        self.text(str(SETTINGS_JSON), 248, 474, 580, 18, 11, NSFontWeightMedium, color("#536071"))
        self.text("后续如果要接入排行榜，会单独做授权和确认，不会默认上传。", 248, 510, 520, 18, 12, NSFontWeightMedium, color(MUTED))


class FlippedRootView(NSView):
    def isFlipped(self):
        return True


class MainWindowController(NSObject):
    def initWithDelegate_(self, delegate):
        self = objc_super(MainWindowController, self).init()
        if self is None:
            return None
        self.delegate = delegate
        self.page = "today"
        self.settings_buttons = []
        self.interval_buttons = []
        self.build_window()
        return self

    @python_method
    def build_window(self):
        style = (
            NSWindowStyleMaskTitled
            | NSWindowStyleMaskClosable
            | NSWindowStyleMaskMiniaturizable
            | NSWindowStyleMaskResizable
        )
        self.window = NSWindow.alloc().initWithContentRect_styleMask_backing_defer_(
            NSMakeRect(0, 0, 940, 700), style, NSBackingStoreBuffered, False
        )
        self.window.setTitle_(APP_TITLE)
        self.window.setMinSize_(NSMakeSize(900, 660))
        self.window.setReleasedWhenClosed_(False)
        root = FlippedRootView.alloc().initWithFrame_(NSMakeRect(0, 0, 940, 700))
        self.canvas = MainWindowCanvas.alloc().initWithFrame_(NSMakeRect(0, 0, 940, 700))
        self.canvas.setAutoresizingMask_(18)
        root.addSubview_(self.canvas)
        self.window.setContentView_(root)
        self.add_sidebar_buttons(root)
        self.refresh_button = self.add_button(root, "刷新", 814, 38, 64, "refresh:", visible=True)
        self.add_settings_controls(root)

    @python_method
    def add_sidebar_buttons(self, root):
        pages = [("today", 128), ("history", 176), ("stats", 224), ("settings", 272), ("privacy", 320)]
        for index, (page, y) in enumerate(pages):
            button = NSButton.buttonWithTitle_target_action_("", self, "switchPage:")
            button.setFrame_(NSMakeRect(20, y, 140, 36))
            button.setBordered_(False)
            button.setTag_(index)
            root.addSubview_(button)

    @python_method
    def add_settings_controls(self, root):
        controls = [
            ("- 1000 万", 584, 178, 86, "adjustGoal:", -10_000_000),
            ("+ 1000 万", 682, 178, 86, "adjustGoal:", 10_000_000),
            ("重置 1 亿", 780, 178, 86, "resetGoal:", 0),
        ]
        for title, x, y, w, action, tag in controls:
            button = self.add_button(root, title, x, y, w, action, visible=False)
            button.setTag_(tag)
            self.settings_buttons.append(button)

        for seconds, x in [(60, 248), (300, 360), (900, 472), (0, 584)]:
            button = NSButton.buttonWithTitle_target_action_("", self, "setInterval:")
            button.setFrame_(NSMakeRect(x, 436, 92, 26))
            button.setBordered_(False)
            button.setTag_(seconds)
            button.setHidden_(True)
            root.addSubview_(button)
            self.interval_buttons.append(button)

        self.autostart_button = NSButton.buttonWithTitle_target_action_("", self, "toggleAutostart:")
        self.autostart_button.setFrame_(NSMakeRect(764, 532, 92, 30))
        self.autostart_button.setBordered_(False)
        self.autostart_button.setHidden_(True)
        root.addSubview_(self.autostart_button)

    @python_method
    def add_button(self, root, title, x, y, w, action, visible=True):
        button = NSButton.buttonWithTitle_target_action_(title, self, action)
        button.setFrame_(NSMakeRect(x, y, w, 28))
        button.setBezelStyle_(NSBezelStyleRounded)
        button.setFont_(NSFont.systemFontOfSize_weight_(12, NSFontWeightSemibold))
        button.setHidden_(not visible)
        root.addSubview_(button)
        return button

    def switchPage_(self, sender):
        pages = ["today", "history", "stats", "settings", "privacy"]
        index = int(sender.tag())
        if 0 <= index < len(pages):
            self.page = pages[index]
            self.update()
            self.window.makeFirstResponder_(self.canvas)

    def refresh_(self, sender):
        self.delegate.refreshData()

    def adjustGoal_(self, sender):
        self.delegate.adjustGoal(int(sender.tag()))

    def resetGoal_(self, sender):
        self.delegate.setGoal(100_000_000)

    def setInterval_(self, sender):
        self.delegate.setRefreshInterval(int(sender.tag()))

    def toggleAutostart_(self, sender):
        self.delegate.setAutostart(not autostart_enabled())

    @python_method
    def show(self):
        self.update()
        if not self.window.isVisible():
            self.window.center()
        self.window.makeKeyAndOrderFront_(None)
        self.window.orderFrontRegardless()
        NSApp.activateIgnoringOtherApps_(True)
        self.window.makeFirstResponder_(self.canvas)

    @python_method
    def update(self):
        is_settings = self.page == "settings"
        for button in self.settings_buttons + self.interval_buttons:
            button.setHidden_(not is_settings)
        self.autostart_button.setHidden_(not is_settings)
        self.canvas.setState_settings_page_refreshing_(
            self.delegate.snapshot, self.delegate.settings, self.page, self.delegate.refreshing
        )


class AppDelegate(NSObject):
    def applicationDidFinishLaunching_(self, notification):
        self.snapshot = load_snapshot()
        self.settings = load_settings()
        self.refreshing = False
        self.refresh_timer = None
        self.main_controller = None

        self.status_item = NSStatusBar.systemStatusBar().statusItemWithLength_(NSVariableStatusItemLength)
        button = self.status_item.button()
        button.setTarget_(self)
        button.setAction_("togglePopover:")
        button.setImagePosition_(NSImageLeft)

        self.popover = NSPopover.alloc().init()
        self.popover.setBehavior_(NSPopoverBehaviorTransient)
        self.popover.setContentSize_(NSMakeSize(390, 520))
        self.panel_controller = PopoverController.alloc().initWithAppDelegate_(self)
        self.popover.setContentViewController_(self.panel_controller)

        self.updateUI()
        self.installTimer()
        self.refreshData()

    def togglePopover_(self, sender):
        button = self.status_item.button()
        if self.popover.isShown():
            self.popover.performClose_(sender)
        else:
            self.snapshot = load_snapshot()
            self.updateUI()
            self.popover.showRelativeToRect_ofView_preferredEdge_(button.bounds(), button, NSMinYEdge)

    def tick_(self, timer):
        self.snapshot = load_snapshot()
        self.updateUI()
        if int(self.settings.get("refresh_interval_seconds", 60)) > 0:
            self.refreshData()

    @python_method
    def installTimer(self):
        if self.refresh_timer:
            self.refresh_timer.invalidate()
            self.refresh_timer = None
        seconds = int(self.settings.get("refresh_interval_seconds", 60))
        if seconds <= 0:
            return
        self.refresh_timer = NSTimer.scheduledTimerWithTimeInterval_target_selector_userInfo_repeats_(
            seconds, self, "tick:", None, True
        )

    @python_method
    def openMainWindow(self):
        if self.main_controller is None:
            self.main_controller = MainWindowController.alloc().initWithDelegate_(self)
        self.main_controller.show()

    @python_method
    def refreshData(self):
        if self.refreshing:
            return
        self.refreshing = True
        self.updateUI()

        def worker():
            try:
                subprocess.run([str(PYTHON), str(COLLECTOR), "collect"], cwd=str(ROOT), timeout=240)
            except Exception:
                pass
            self.performSelectorOnMainThread_withObject_waitUntilDone_("finishRefresh:", None, False)

        threading.Thread(target=worker, daemon=True).start()

    def finishRefresh_(self, obj):
        self.refreshing = False
        self.snapshot = load_snapshot()
        self.updateUI()

    @python_method
    def setGoal(self, goal: int):
        self.settings["daily_goal_tokens"] = max(1_000_000, int(goal))
        save_settings(self.settings)
        self.settings = load_settings()
        self.updateUI()

    @python_method
    def adjustGoal(self, delta: int):
        self.setGoal(int(self.settings.get("daily_goal_tokens", 100_000_000)) + int(delta))

    @python_method
    def setRefreshInterval(self, seconds: int):
        self.settings["refresh_interval_seconds"] = int(seconds)
        save_settings(self.settings)
        self.settings = load_settings()
        self.installTimer()
        self.updateUI()

    @python_method
    def setAutostart(self, enabled: bool):
        set_autostart(bool(enabled))
        self.updateUI()

    @python_method
    def updateUI(self):
        row = today_row(self.snapshot)
        tokens = int(row.get("total_tokens", 0) or 0)
        goal = int(self.settings.get("daily_goal_tokens", 100_000_000))
        progress = goal_progress(tokens, goal)
        button = self.status_item.button()
        button.setImage_(make_status_image(progress, self.refreshing))
        button.setTitle_(" " + format_tokens(tokens, compact=True))
        if hasattr(self, "panel_controller"):
            self.panel_controller.updateWithState_settings_refreshing_(self.snapshot, self.settings, self.refreshing)
        if self.main_controller is not None:
            self.main_controller.update()


def run_check():
    snapshot = load_snapshot()
    settings = load_settings()
    row = today_row(snapshot)
    print("app:", APP_TITLE)
    print("generated_at:", snapshot.get("generated_at"))
    print("today:", format_tokens(row.get("total_tokens", 0)))
    print("goal:", format_tokens(settings.get("daily_goal_tokens", 0)))
    print("refresh:", interval_label(settings.get("refresh_interval_seconds", 60)))
    print("cost:", format_money(row.get("cost", 0)))


def main():
    if "--check" in sys.argv:
        run_check()
        return
    app = NSApplication.sharedApplication()
    app.setActivationPolicy_(NSApplicationActivationPolicyAccessory)
    delegate = AppDelegate.alloc().init()
    app.setDelegate_(delegate)
    app.run()


if __name__ == "__main__":
    main()
