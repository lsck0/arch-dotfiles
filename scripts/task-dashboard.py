#!/usr/bin/env python3
"""taskwarrior + timewarrior dashboard"""

import curses
import json
import subprocess
import time
from dataclasses import dataclass, field
from datetime import datetime

# ============================================================================
# config
# ============================================================================

REFRESH_INTERVAL = 1
DATA_TTL = 10
COLUMN_RATIO = 0.50
TIMESTAMP_FMT = "%Y%m%dT%H%M%SZ"


# ============================================================================
# data model
# ============================================================================


def parse_timestamp(s: str) -> datetime | None:
    try:
        return datetime.strptime(s, TIMESTAMP_FMT)
    except (ValueError, TypeError):
        return None


@dataclass
class Task:
    id: int
    description: str
    project: str
    tags: list[str]
    priority: str
    due: str
    urgency: float
    start: datetime | None = None

    @property
    def active(self) -> bool:
        return self.start is not None

    @property
    def elapsed(self) -> str:
        if not self.start:
            return ""
        delta = datetime.utcnow() - self.start
        return str(delta).split(".")[0]

    @property
    def due_relative(self) -> str:
        due_dt = parse_timestamp(self.due)
        if not due_dt:
            return ""
        days = (due_dt.date() - datetime.utcnow().date()).days
        if days < -1:
            return f"{-days}d ago"
        if days == -1:
            return "yesterday"
        if days == 0:
            return "today"
        if days == 1:
            return "tomorrow"
        return f"in {days}d"


@dataclass
class TimeEntry:
    label: str
    seconds: float

    @property
    def formatted(self) -> str:
        h, m = divmod(int(self.seconds), 3600)
        return f"{h}:{m // 60:02d}"


@dataclass
class Project:
    name: str
    pending: int
    completed: int
    tasks: list[Task] = field(default_factory=list)

    @property
    def percent_done(self) -> int:
        total = self.pending + self.completed
        return round(self.completed / total * 100) if total else 0


@dataclass
class State:
    tasks: list[Task] = field(default_factory=list)
    time_entries: list[dict] = field(default_factory=list)
    completed_tasks: list[dict] = field(default_factory=list)
    fetched_at: float = 0

    @property
    def is_stale(self) -> bool:
        return time.time() - self.fetched_at > DATA_TTL

    @property
    def active_tasks(self) -> list[Task]:
        return [t for t in self.tasks if t.active]

    @property
    def upcoming_tasks(self) -> list[Task]:
        return sorted(
            [t for t in self.tasks if not t.active],
            key=lambda t: t.urgency,
            reverse=True,
        )

    @property
    def projects(self) -> list[Project]:
        pending: dict[str, int] = {}
        completed: dict[str, int] = {}
        by_project: dict[str, list[Task]] = {}

        for t in self.tasks:
            if t.project:
                pending[t.project] = pending.get(t.project, 0) + 1
                by_project.setdefault(t.project, []).append(t)

        for t in self.completed_tasks:
            if p := t.get("project"):
                completed[p] = completed.get(p, 0) + 1

        result = []
        for name in set(pending) | set(completed):
            tasks = sorted(by_project.get(name, []), key=lambda t: -t.urgency)
            result.append(
                Project(name, pending.get(name, 0), completed.get(name, 0), tasks)
            )
        return sorted(result, key=lambda p: (-p.pending, p.name))

    def _aggregate_time(self, entries: list[dict]) -> list[TimeEntry]:
        totals: dict[str, float] = {}
        now = datetime.utcnow()
        for e in entries:
            label = ", ".join(e.get("tags", [])) or "(untagged)"
            start = parse_timestamp(e.get("start", ""))
            end = parse_timestamp(e.get("end", "")) or now
            if start:
                totals[label] = totals.get(label, 0) + (end - start).total_seconds()
        return sorted(
            [TimeEntry(k, v) for k, v in totals.items()], key=lambda e: -e.seconds
        )

    @property
    def time_today(self) -> list[TimeEntry]:
        today = datetime.utcnow().strftime("%Y%m%d")
        return self._aggregate_time(
            [e for e in self.time_entries if e.get("start", "").startswith(today)]
        )

    @property
    def time_week(self) -> list[TimeEntry]:
        return self._aggregate_time(self.time_entries)


# ============================================================================
# data fetching
# ============================================================================


def run_json(cmd: str) -> list | None:
    try:
        result = subprocess.run(
            cmd, shell=True, capture_output=True, text=True, timeout=10
        )
        return json.loads(result.stdout) if result.stdout.strip() else None
    except (subprocess.TimeoutExpired, json.JSONDecodeError, OSError):
        return None


def parse_task(t: dict) -> Task | None:
    if not isinstance(t, dict):
        return None
    return Task(
        id=t.get("id", 0),
        description=t.get("description", ""),
        project=t.get("project", ""),
        tags=t.get("tags", []),
        priority=t.get("priority", ""),
        due=t.get("due", ""),
        urgency=t.get("urgency", 0.0),
        start=parse_timestamp(t.get("start")),
    )


def fetch_state(prev: State) -> State:
    if not prev.is_stale:
        return prev

    pending = run_json("task status:pending export 2>/dev/null") or []
    completed = run_json("task status:completed export 2>/dev/null") or []
    time_entries = run_json("timew export :week 2>/dev/null") or []

    tasks = [t for raw in pending if (t := parse_task(raw))]

    return State(
        tasks=tasks,
        time_entries=time_entries if isinstance(time_entries, list) else [],
        completed_tasks=completed if isinstance(completed, list) else [],
        fetched_at=time.time(),
    )


# ============================================================================
# screen
# ============================================================================


class Screen:
    def __init__(self, win):
        self.win = win
        self.height, self.width = win.getmaxyx()
        curses.curs_set(0)
        curses.start_color()
        curses.use_default_colors()
        curses.init_pair(1, 245, -1)
        self.BOLD = curses.A_BOLD
        self.DIM = curses.color_pair(1)
        self.NORMAL = curses.A_NORMAL
        win.timeout(REFRESH_INTERVAL * 1000)

    def refresh(self):
        self.win.refresh()

    def erase(self):
        self.win.erase()
        self.height, self.width = self.win.getmaxyx()

    def getch(self) -> int:
        return self.win.getch()

    def text(self, y: int, x: int, s: str, attr=None) -> bool:
        if y < 0 or y >= self.height - 1 or x < 0 or x >= self.width:
            return False
        try:
            self.win.addnstr(y, x, s, self.width - x - 1, attr or self.NORMAL)
            return True
        except curses.error:
            return False

    def vline(self, x: int, y1: int, y2: int):
        for y in range(y1, min(y2, self.height - 1)):
            try:
                self.win.addch(y, x, "|", self.DIM)
            except curses.error:
                pass


def truncate(s: str, w: int) -> str:
    return s if len(s) <= w else s[: w - 1] + "…" if w > 1 else ""


def make_bar(filled: int, total: int) -> str:
    return "=" * filled + "·" * (total - filled)


# ============================================================================
# rendering
# ============================================================================


def render_active(scr: Screen, y: int, x: int, w: int, tasks: list[Task]) -> int:
    scr.text(y, x, "ACTIVE", scr.DIM)
    y += 1

    if not tasks:
        scr.text(y, x, "  -", scr.DIM)
        return y + 2

    for task in tasks:
        if y >= scr.height - 3:
            break

        elapsed = task.elapsed
        if elapsed:
            scr.text(y, x, truncate(task.description, w - len(elapsed) - 2), scr.BOLD)
            scr.text(y, x + w - len(elapsed), elapsed, scr.BOLD)
        else:
            scr.text(y, x, truncate(task.description, w), scr.BOLD)
        y += 1

        meta = [f"#{task.id}"]
        if task.priority:
            meta.append(task.priority)
        meta.append(f"{task.urgency:.1f}")
        if task.due_relative:
            meta.append(task.due_relative)
        if task.project:
            meta.append(f"@{task.project}")
        meta.extend(f"+{t}" for t in task.tags[:3])
        scr.text(y, x, truncate("  ".join(meta), w), scr.DIM)
        y += 2

    return y


def render_tasks(
    scr: Screen, y: int, x: int, w: int, label: str, tasks: list[Task], limit: int
) -> int:
    scr.text(y, x, label, scr.DIM)
    y += 1

    if not tasks:
        scr.text(y, x, "  -", scr.DIM)
        return y + 1

    id_w, due_w = 5, 10
    desc_w = w - id_w - due_w - 1

    for task in tasks[:limit]:
        if y >= scr.height - 1:
            break
        style = (
            scr.BOLD
            if task.priority == "H"
            else scr.DIM if task.priority == "L" else scr.NORMAL
        )
        scr.text(y, x, f"{task.id:>3}", scr.DIM)
        scr.text(y, x + id_w, truncate(task.description, desc_w), style)
        if task.due_relative:
            scr.text(y, x + w - due_w, f"{task.due_relative:>{due_w}}", scr.DIM)
        y += 1

    return y


def render_projects(
    scr: Screen, y: int, x: int, w: int, projects: list[Project], max_y: int
) -> int:
    scr.text(y, x, "PROJECTS", scr.DIM)
    y += 1

    if not projects:
        scr.text(y, x, "  -", scr.DIM)
        return y + 2

    bar_w, pct_w = 6, 4
    name_w = w - bar_w - pct_w - 2

    for p in projects:
        if y >= max_y - 1:
            break
        filled = round(bar_w * p.percent_done / 100)
        scr.text(y, x, truncate(p.name, name_w), scr.NORMAL)
        scr.text(y, x + name_w, make_bar(filled, bar_w), scr.DIM)
        scr.text(y, x + name_w + bar_w + 1, f"{p.percent_done:>2}%", scr.DIM)
        y += 1

        for t in p.tasks[:2]:
            if y >= max_y - 1:
                break
            scr.text(y, x, f"  {t.id:>3} {truncate(t.description, w - 7)}", scr.DIM)
            y += 1

    return y + 1


def render_time(
    scr: Screen, y: int, x: int, w: int, label: str, entries: list[TimeEntry]
) -> int:
    scr.text(y, x, label, scr.DIM)
    y += 1

    if not entries:
        scr.text(y, x, "  -", scr.DIM)
        return y + 2

    max_secs = max(e.seconds for e in entries)
    bar_w, time_w = 8, 5
    label_w = w - bar_w - time_w - 2

    for e in entries:
        if y >= scr.height - 1:
            break
        filled = max(1, round(bar_w * e.seconds / max_secs)) if max_secs else 1
        scr.text(y, x, truncate(e.label, label_w), scr.NORMAL)
        scr.text(y, x + label_w, make_bar(filled, bar_w), scr.DIM)
        scr.text(y, x + label_w + bar_w + 1, e.formatted, scr.BOLD)
        y += 1

    total = sum(e.seconds for e in entries)
    h, m = divmod(int(total), 3600)
    scr.text(y, x + w - 6, f"{h}:{m // 60:02d}", scr.NORMAL)
    return y + 2


# ============================================================================
# layout
# ============================================================================


def render(scr: Screen, state: State):
    scr.erase()

    if scr.height < 10 or scr.width < 50:
        scr.text(0, 0, "terminal too small", scr.BOLD)
        return

    col_x = int(scr.width * COLUMN_RATIO)
    pad = 3
    left_w = col_x - pad
    right_w = scr.width - col_x - pad - 1

    scr.vline(col_x, 0, scr.height)

    # left: active + next
    y = render_active(scr, 0, 1, left_w, state.active_tasks)
    render_tasks(
        scr, y + 1, 1, left_w, "NEXT", state.upcoming_tasks, scr.height - y - 3
    )

    # right: projects + time
    rx = col_x + pad
    y = render_projects(scr, 0, rx, right_w, state.projects, scr.height // 2)
    y = render_time(scr, y + 1, rx, right_w, "TODAY", state.time_today)
    render_time(scr, y + 1, rx, right_w, "THIS WEEK", state.time_week)


# ============================================================================
# main
# ============================================================================


def main(win):
    scr = Screen(win)
    state = State()

    while True:
        state = fetch_state(state)
        render(scr, state)
        scr.refresh()

        ch = scr.getch()
        if ch in (ord("q"), ord("Q"), 27):
            break
        if ch == ord("r"):
            state.fetched_at = 0


if __name__ == "__main__":
    try:
        curses.wrapper(main)
    except KeyboardInterrupt:
        pass
