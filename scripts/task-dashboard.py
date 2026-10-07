#!/usr/bin/env python3
"""Single human-facing task dashboard across the whole ecosystem:
taskwarrior + timewarrior + bugwarrior (GitHub issues) + the
l-agent-task-db agent flow.

Read-only: never modifies any db. Always targets the HUMAN taskwarrior db
(~/.taskrc), unsetting any agent TASKDATA/TIMEWARRIORDB so it still works
inside a project whose direnv/devenv exported an agent TASKRC.

On a tty it runs as a live curses TUI with tabs: dashboard (active timers
and tasks, next up, projects, time today / this week), needs review, needs
clarification, due (overdue / due today / aging), GitHub issues, agent flow
and burndown. Keys: 1-7 / Tab / h l switch tabs, j k scroll, r refresh,
q / Esc quit. Fast sources (active timer, active tasks) refresh every
FAST_REFRESH_S, slow ones (task export, timew week, bugwarrior issues,
agent dbs, burndown) every SLOW_REFRESH_S or on r.

Off a tty, or with --print / --page, it prints one page: active, overdue,
due today, upcoming, aging, GitHub issues, projects, burndown, time this
week and a per-project summary of the agent task dbs under ~/projects.

Each system is optional: a missing timew/bugwarrior/agent-db degrades to
"(none)" rather than erroring.

Usage: task-dashboard [--print] [--page|-p]
"""
import curses
import glob
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import time
from collections import Counter
from dataclasses import dataclass, field
from datetime import datetime, timezone

# -----------------------------------------------------------------------------
# CONSTANTS
# -----------------------------------------------------------------------------

HUMAN_TASKRC = os.path.expanduser("~/.taskrc")
AGENT_DB_GLOB = os.path.expanduser("~/projects/*/tasks/.taskrc")
AGENT_MODULE_REL = "skills/l-agent-task-db/scripts/task-dashboard.py"
READY_LIMIT = 10
AGING_LIMIT = 10
GITHUB_LIMIT = 15
BUGWARRIOR_TAG = "github"
BUGWARRIOR_UDA = "githuburl"            # definitive marker of a bugwarrior-sourced task
HUMAN_INPUT_TAGS = ("human-clarification-needed", "human-review-ready")
REVIEW_TAG_WORDS = ("review", "approval")
CLARIFY_TAG_WORDS = ("needs-human", "clarification")
TIMESTAMP_FMT = "%Y%m%dT%H%M%SZ"

REDRAW_INTERVAL_MS = 1000
FAST_REFRESH_S = 5
SLOW_REFRESH_S = 30
COLUMN_RATIO = 0.50
COLUMN_PAD = 3
MIN_HEIGHT = 10
MIN_WIDTH = 50
DIM_COLOR = 245
ESC_DELAY_MS = 25
KEY_ESC = 27
KEY_TAB = 9
PROJECT_TOP_TASKS = 2
ACTIVE_TAG_LIMIT = 3
BAR_PROJECT_W = 6
BAR_TIME_W = 8

STYLE_NORMAL, STYLE_DIM, STYLE_BOLD, STYLE_REVERSE = range(4)
TABS = ("Dashboard", "Review", "Clarify", "Due", "GitHub", "Agents", "Burndown")
TAB_DASHBOARD, TAB_REVIEW, TAB_CLARIFY, TAB_DUE, TAB_GITHUB, TAB_AGENTS, TAB_BURNDOWN = range(len(TABS))
FOOTER_KEYS = f" 1-{len(TABS)} Tab h l: tabs  j k: scroll  r: refresh  q: quit"
TASK_ROW_FMT = " {:>3}  {:>3}  {:>4}  {:<15} {}"

# -----------------------------------------------------------------------------
# INTERNAL: environment + process helpers
# -----------------------------------------------------------------------------


def human_env():
    """Env that forces the human db regardless of an agent shell's exports."""
    env = dict(os.environ, TASKRC=HUMAN_TASKRC)
    env.pop("TASKDATA", None)
    env.pop("TIMEWARRIORDB", None)
    return env


def have(cmd):
    return shutil.which(cmd) is not None


def run(argv, env=None):
    """Run a command, returning its stdout (stderr dropped). Empty string on
    any failure, so a missing/erroring subsystem never takes the page down."""
    try:
        res = subprocess.run(
            argv, env=env, capture_output=True, text=True, check=False,
        )
        return res.stdout.rstrip("\n")
    except (OSError, ValueError):
        return ""


def run_json(argv, env):
    out = run(argv, env)
    try:
        data = json.loads(out) if out.strip() else []
    except ValueError:
        return []
    return data if isinstance(data, list) else []


def load_agent_module():
    """Import the l-agent-task-db dashboard as a module to reuse its data
    model (load_all_tasks, stage_of, question_file, pr_link) instead of
    reimplementing it. The filename has a hyphen, so load it by path."""
    script = os.path.realpath(__file__)
    repo_root = os.path.dirname(os.path.dirname(script))
    path = os.path.join(repo_root, AGENT_MODULE_REL)
    if not os.path.isfile(path):
        return None
    spec = importlib.util.spec_from_file_location("agent_task_dashboard", path)
    mod = importlib.util.module_from_spec(spec)
    try:
        spec.loader.exec_module(mod)
    except Exception:
        return None
    return mod


# -----------------------------------------------------------------------------
# INTERNAL: data fetching (shared by the print page and the TUI)
# -----------------------------------------------------------------------------


@dataclass
class AgentProject:
    name: str
    note: str = ""
    open_count: int = 0
    stages: str = ""
    clarify: list = field(default_factory=list)
    review: list = field(default_factory=list)
    answered: int = 0


def fetch_tasks(env, *filters):
    if not have("task"):
        return []
    return run_json(["task", "rc.verbose=nothing", *filters, "export"], env)


def fetch_report(env, *args, color=True):
    """A taskwarrior report, colour forced through the capture pipe unless
    the caller draws it itself."""
    force = "on" if color else "off"
    return run(["task", "rc.verbose=nothing", f"rc._forcecolor={force}", *args], env=env)


def fetch_timer(env):
    if not have("timew"):
        return None
    latest = run_json(["timew", "export", "@1"], env)
    return latest[0] if latest and "end" not in latest[0] else None


def fetch_time_week(env):
    return run_json(["timew", "export", ":week"], env) if have("timew") else []


def classify_gated(agent_tasks):
    """Split gated tickets the way the agent dashboard does: clarification
    vs review, with human-answered ones pulled out as awaiting the agent."""
    gated = [t for t in agent_tasks
             if set(HUMAN_INPUT_TAGS) & set(t.get("tags", []))]
    answered = [t for t in gated if "human-answered" in t.get("tags", [])]
    clarify = [t for t in gated if t not in answered
               and "human-clarification-needed" in t.get("tags", [])]
    review = [t for t in gated if t not in answered
              and "human-review-ready" in t.get("tags", [])]
    return clarify, review, answered


def fetch_agent_flow(agent_mod):
    """Per-project agent db summary; None when the agent module is missing."""
    if agent_mod is None:
        return None
    projects = []
    for taskrc in sorted(glob.glob(AGENT_DB_GLOB)):
        root = os.path.dirname(os.path.dirname(taskrc))
        project = AgentProject(os.path.basename(root))
        projects.append(project)
        try:
            all_tasks = agent_mod.load_all_tasks(taskrc)
        except Exception:
            project.note = "(unreadable db)"
            continue

        agent_tasks = [t for t in all_tasks if t.get("status") == "pending"
                       and "agent-task" in t.get("tags", [])]
        if not agent_tasks:
            project.note = "(no open agent tickets)"
            continue

        stages = Counter(agent_mod.stage_of(t) for t in agent_tasks)
        project.open_count = len(agent_tasks)
        project.stages = " ".join(f"{s}:{n}" for s, n in sorted(stages.items()))
        clarify, review, answered = classify_gated(agent_tasks)
        project.clarify = [(t["id"], agent_mod.one_line(t["description"]),
                            agent_mod.question_file(t, root)) for t in clarify]
        project.review = [(t["id"], agent_mod.one_line(t["description"]),
                           agent_mod.pr_link(t)) for t in review]
        project.answered = len(answered)
    return projects


# -----------------------------------------------------------------------------
# INTERNAL: selection over a task export
# -----------------------------------------------------------------------------


def parse_timestamp(s):
    try:
        return datetime.strptime(s, TIMESTAMP_FMT).replace(tzinfo=timezone.utc)
    except (ValueError, TypeError):
        return None


def one_line(text):
    return " ".join(text.split())


def has_tag_word(task, words):
    return any(w in tag.lower() for tag in task.get("tags", []) for w in words)


def is_ready(task):
    wait = parse_timestamp(task.get("wait"))
    return task.get("status") == "pending" and not (wait and wait > datetime.now(timezone.utc))


def select_github_issues(tasks):
    """GitHub issues pulled into the human db by bugwarrior, identified by
    the githuburl UDA (definitive) or +github tag."""
    issues = [t for t in tasks if t.get("status") == "pending"
              and (t.get(BUGWARRIOR_UDA) or BUGWARRIOR_TAG in t.get("tags", []))]
    issues.sort(key=lambda t: (t.get("project", ""), t.get("githubnumber") or 0))
    return issues


def select_by_due_day(tasks, compare):
    today = datetime.now().date()
    result = []
    for t in tasks:
        due = parse_timestamp(t.get("due"))
        if is_ready(t) and due and compare(due.astimezone().date(), today):
            result.append(t)
    return sorted(result, key=lambda t: t["due"])


def select_aging(tasks):
    pending = [t for t in tasks if is_ready(t)]
    return sorted(pending, key=lambda t: t.get("entry", ""))[:AGING_LIMIT]


def summarize_projects(tasks):
    pending = Counter()
    completed = Counter()
    top = {}
    for t in tasks:
        name = t.get("project")
        if not name:
            continue
        if t.get("status") == "pending":
            pending[name] += 1
            top.setdefault(name, []).append(t)
        elif t.get("status") == "completed":
            completed[name] += 1
    stats = []
    for name in set(pending) | set(completed):
        best = sorted(top.get(name, []), key=lambda t: -t.get("urgency", 0))
        stats.append((name, pending[name], completed[name], best[:PROJECT_TOP_TASKS]))
    return sorted(stats, key=lambda s: (-s[1], s[0]))


def aggregate_time(entries):
    totals = Counter()
    now = datetime.now(timezone.utc)
    for e in entries:
        start = parse_timestamp(e.get("start"))
        if start:
            end = parse_timestamp(e.get("end")) or now
            totals[", ".join(e.get("tags", [])) or "(untagged)"] += (end - start).total_seconds()
    return totals.most_common()


def format_elapsed(start):
    if not start:
        return ""
    return str(datetime.now(timezone.utc) - start).split(".")[0]


def format_hours(seconds):
    h, rest = divmod(int(seconds), 3600)
    return f"{h}:{rest // 60:02d}"


def format_due_relative(task):
    due = parse_timestamp(task.get("due"))
    if not due:
        return ""
    days = (due.astimezone().date() - datetime.now().date()).days
    if days < -1:
        return f"{-days}d ago"
    return {-1: "yesterday", 0: "today", 1: "tomorrow"}.get(days, f"in {days}d")


def format_age(task):
    entry = parse_timestamp(task.get("entry"))
    return f"{(datetime.now(timezone.utc) - entry).days}d" if entry else ""


# -----------------------------------------------------------------------------
# INTERNAL: line builders (shared by the print page and the TUI)
# -----------------------------------------------------------------------------


def lines_github(issues, limit):
    lines = []
    for t in issues[:limit]:
        repo = t.get("githubrepo") or t.get("project") or "-"
        num = t.get("githubnumber")
        ref = f"{repo}#{int(num)}" if num else repo
        title = (t.get("githubtitle") or t.get("description") or "").strip()
        lines.append((f"  #{t['id']:<4} {ref:<28} {title}", STYLE_NORMAL))
    if len(issues) > limit:
        lines.append((f"  ... and {len(issues) - limit} more", STYLE_DIM))
    return lines


def lines_agent_flow(projects):
    if projects is None:
        return [("  (agent task-db module not found)", STYLE_DIM)]
    if not projects:
        return [("  (no agent task dbs under ~/projects)", STYLE_DIM)]
    lines = []
    for p in projects:
        if p.note:
            lines.append((f"  {p.name}: {p.note}", STYLE_DIM))
            continue
        lines.append((f"  {p.name}: {p.open_count} open  [{p.stages}]", STYLE_NORMAL))
        # "needs human input" is the human's cue: make it prominent.
        for task_id, desc, qf in p.clarify:
            lines.append((f"      NEEDS YOU: #{task_id} {desc}", STYLE_BOLD))
            if qf:
                lines.append((f"                 -> {qf}", STYLE_DIM))
        for task_id, desc, pr in p.review:
            lines.append((f"      REVIEW PR: #{task_id} {desc}", STYLE_BOLD))
            lines.append((f"                 -> {pr or '(no PR annotated)'}", STYLE_DIM))
        if p.answered:
            lines.append((f"      ({p.answered} answered, awaiting agent)", STYLE_DIM))
    return lines


def join_lines(lines):
    return "\n".join(text for text, _ in lines)


# -----------------------------------------------------------------------------
# INTERNAL: print page (gum when present, plain fallback)
# -----------------------------------------------------------------------------


class Page:
    """Accumulates the whole dashboard so it can be printed or paged as one
    block. gum styles headings/banner when available; plain text otherwise."""

    def __init__(self):
        self.parts = []
        self.gum = have("gum")

    def raw(self, text):
        if text:
            self.parts.append(text)

    def banner(self, text):
        if self.gum:
            self.raw(run([
                "gum", "style", "--border", "double", "--border-foreground", "5",
                "--padding", "0 2", "--bold", "--foreground", "6", text,
            ]))
        else:
            self.raw(f"=== {text} ===")

    def heading(self, text):
        if self.gum:
            self.raw(run(["gum", "style", "--bold", "--foreground", "6", f">> {text}"]))
        else:
            self.raw(f"\n>> {text}")

    def section(self, title, body):
        self.heading(title)
        self.raw(body if body.strip() else "  (none)")

    def render(self):
        return "\n".join(self.parts) + "\n"


def section_active(page, env):
    page.heading("ACTIVE (being worked now)")
    body = []
    if have("timew"):
        timers = run(["timew"], env=env)
        body.append(timers if timers else "  (no active timer)")
    active = fetch_report(env, "+ACTIVE")
    if active:
        body.append(active)
    page.raw("\n".join(body) if any(b.strip() for b in body) else "  (none)")


def build_page():
    page = Page()
    env = human_env()

    page.banner(f"TASK DASHBOARD // {datetime.now():%Y-%m-%d %H:%M}")

    if not have("task"):
        page.raw("  taskwarrior not installed")
        return page.render()

    tasks = fetch_tasks(env)

    section_active(page, env)
    page.section("OVERDUE", fetch_report(env, "+OVERDUE"))
    page.section("DUE TODAY", fetch_report(env, "due:today"))
    page.section("UPCOMING (ready)", fetch_report(env, f"limit:{READY_LIMIT}", "ready"))
    page.section("AGING (oldest pending)", fetch_report(env, f"limit:{AGING_LIMIT}", "aging"))
    page.section("GITHUB ISSUES (bugwarrior)",
                 join_lines(lines_github(select_github_issues(tasks), GITHUB_LIMIT)))
    page.section("PROJECTS", fetch_report(env, "summary"))
    page.section("BURNDOWN (daily)", fetch_report(env, "burndown.daily"))

    if have("timew"):
        page.section("TIME THIS WEEK", run(["timew", "summary", ":week"], env=env))

    page.heading("AGENT FLOW (per project)")
    page.raw(join_lines(lines_agent_flow(fetch_agent_flow(load_agent_module()))))
    return page.render()


def print_page(paged):
    text = build_page()
    if paged and have("less") and sys.stdout.isatty():
        proc = subprocess.Popen(["less", "-R"], stdin=subprocess.PIPE, text=True)
        try:
            proc.communicate(text)
        except BrokenPipeError:
            pass
    else:
        sys.stdout.write(text)


# -----------------------------------------------------------------------------
# INTERNAL: TUI state
# -----------------------------------------------------------------------------


@dataclass
class State:
    tasks: list = field(default_factory=list)
    time_week: list = field(default_factory=list)
    burndown: str = ""
    agent_projects: list | None = None
    active_tasks: list = field(default_factory=list)
    timer: dict | None = None
    slow_at: float = float("-inf")
    fast_at: float = float("-inf")
    updated: str = ""


def refresh_slow(state, env, agent_mod):
    state.tasks = fetch_tasks(env)
    state.time_week = fetch_time_week(env)
    state.burndown = fetch_report(env, "burndown.daily", color=False) if have("task") else ""
    state.agent_projects = fetch_agent_flow(agent_mod)
    state.slow_at = time.monotonic()
    state.updated = f"{datetime.now():%H:%M:%S}"


def refresh_fast(state, env):
    state.active_tasks = fetch_tasks(env, "+ACTIVE")
    state.timer = fetch_timer(env)
    state.fast_at = time.monotonic()


def select_next(state):
    active = {t.get("uuid") for t in state.active_tasks}
    ready = [t for t in state.tasks if is_ready(t)
             and not t.get("start") and t.get("uuid") not in active]
    return sorted(ready, key=lambda t: -t.get("urgency", 0))


def agent_items(state, kind):
    return [(p.name, *item) for p in state.agent_projects or [] for item in getattr(p, kind)]


def count_tab(state, tab):
    pending = [t for t in state.tasks if t.get("status") == "pending"]
    if tab == TAB_REVIEW:
        return sum(has_tag_word(t, REVIEW_TAG_WORDS) for t in pending) + len(agent_items(state, "review"))
    if tab == TAB_CLARIFY:
        return sum(has_tag_word(t, CLARIFY_TAG_WORDS) for t in pending) + len(agent_items(state, "clarify"))
    if tab == TAB_DUE:
        return len(select_by_due_day(state.tasks, lambda due, today: due <= today))
    if tab == TAB_GITHUB:
        return len(select_github_issues(state.tasks))
    if tab == TAB_AGENTS:
        return sum(p.open_count for p in state.agent_projects or [])
    return None


# -----------------------------------------------------------------------------
# INTERNAL: TUI screen
# -----------------------------------------------------------------------------


class Screen:
    def __init__(self, win):
        self.win = win
        self.height, self.width = win.getmaxyx()
        try:
            curses.curs_set(0)
        except curses.error:
            pass
        curses.set_escdelay(ESC_DELAY_MS)
        dim = curses.A_DIM
        try:
            curses.start_color()
            curses.use_default_colors()
            if curses.COLORS > DIM_COLOR:
                curses.init_pair(1, DIM_COLOR, -1)
                dim = curses.color_pair(1)
        except curses.error:
            pass
        self.styles = {STYLE_NORMAL: curses.A_NORMAL, STYLE_DIM: dim, STYLE_BOLD: curses.A_BOLD,
                       STYLE_REVERSE: curses.A_REVERSE}
        win.keypad(True)
        win.timeout(REDRAW_INTERVAL_MS)

    def erase(self):
        self.win.erase()
        self.height, self.width = self.win.getmaxyx()

    def text(self, y, x, s, style=STYLE_NORMAL):
        if y < 0 or y >= self.height - 1 or x < 0 or x >= self.width - 1:
            return
        try:
            self.win.addnstr(y, x, s, self.width - x - 1, self.styles[style])
        except curses.error:
            pass

    def footer(self, s, style=STYLE_DIM):
        try:
            self.win.move(self.height - 1, 0)
            self.win.clrtoeol()
            self.win.addnstr(self.height - 1, 0, s, self.width - 1, self.styles[style])
        except curses.error:
            pass

    def vline(self, x, y_top):
        for y in range(y_top, self.height - 1):
            self.text(y, x, "|", STYLE_DIM)


def truncate(s, w):
    if len(s) <= w:
        return s
    return s[:w - 3] + "..." if w > 3 else s[:max(w, 0)]


def make_bar(filled, total):
    return "=" * filled + "." * (total - filled)


# -----------------------------------------------------------------------------
# INTERNAL: TUI dashboard tab
# -----------------------------------------------------------------------------


def render_active(scr, y, x, w, timer, tasks):
    scr.text(y, x, "ACTIVE", STYLE_DIM)
    y += 1
    if not timer and not tasks:
        scr.text(y, x, "  -", STYLE_DIM)
        return y + 2

    if timer:
        elapsed = format_elapsed(parse_timestamp(timer.get("start")))
        label = "timew: " + (" ".join(timer.get("tags", [])) or "(untagged)")
        scr.text(y, x, truncate(label, w - len(elapsed) - 2), STYLE_BOLD)
        scr.text(y, x + w - len(elapsed), elapsed, STYLE_BOLD)
        y += 2

    for task in tasks:
        if y >= scr.height - 3:
            break
        elapsed = format_elapsed(parse_timestamp(task.get("start")))
        scr.text(y, x, truncate(one_line(task.get("description", "")), w - len(elapsed) - 2), STYLE_BOLD)
        scr.text(y, x + w - len(elapsed), elapsed, STYLE_BOLD)
        y += 1

        meta = [f"#{task.get('id', 0)}"]
        if task.get("priority"):
            meta.append(task["priority"])
        meta.append(f"{task.get('urgency', 0):.1f}")
        if due := format_due_relative(task):
            meta.append(due)
        if task.get("project"):
            meta.append(f"@{task['project']}")
        meta.extend(f"+{t}" for t in task.get("tags", [])[:ACTIVE_TAG_LIMIT])
        scr.text(y, x, truncate("  ".join(meta), w), STYLE_DIM)
        y += 2
    return y


def priority_style(task):
    return {"H": STYLE_BOLD, "L": STYLE_DIM}.get(task.get("priority"), STYLE_NORMAL)


def render_next(scr, y, x, w, tasks):
    scr.text(y, x, "NEXT", STYLE_DIM)
    y += 1
    if not tasks:
        scr.text(y, x, "  -", STYLE_DIM)
        return y + 1

    id_w, due_w = 5, 10
    desc_w = w - id_w - due_w - 1
    for task in tasks:
        if y >= scr.height - 1:
            break
        scr.text(y, x, f"{task.get('id', 0):>3}", STYLE_DIM)
        scr.text(y, x + id_w, truncate(one_line(task.get("description", "")), desc_w), priority_style(task))
        if due := format_due_relative(task):
            scr.text(y, x + w - due_w, f"{due:>{due_w}}", STYLE_DIM)
        y += 1
    return y


def render_projects(scr, y, x, w, stats, max_y):
    scr.text(y, x, "PROJECTS", STYLE_DIM)
    y += 1
    if not stats:
        scr.text(y, x, "  -", STYLE_DIM)
        return y + 2

    pct_w = 4
    name_w = max(1, w - BAR_PROJECT_W - pct_w - 2)
    for name, pending, completed, top in stats:
        if y >= max_y - 1:
            break
        percent = round(completed / (pending + completed) * 100)
        filled = round(BAR_PROJECT_W * percent / 100)
        scr.text(y, x, truncate(name, name_w - 1))
        scr.text(y, x + name_w, make_bar(filled, BAR_PROJECT_W), STYLE_DIM)
        scr.text(y, x + name_w + BAR_PROJECT_W + 1, f"{percent:>2}%", STYLE_DIM)
        y += 1
        for t in top:
            if y >= max_y - 1:
                break
            desc = truncate(one_line(t.get("description", "")), max(1, w - 7))
            scr.text(y, x, f"  {t.get('id', 0):>3} {desc}", STYLE_DIM)
            y += 1
    return y + 1


def render_time(scr, y, x, w, label, totals):
    scr.text(y, x, label, STYLE_DIM)
    y += 1
    if not totals:
        scr.text(y, x, "  -", STYLE_DIM)
        return y + 2

    max_secs = totals[0][1]
    label_w = max(1, w - BAR_TIME_W - 5 - 2)
    for name, secs in totals:
        if y >= scr.height - 1:
            break
        filled = max(1, round(BAR_TIME_W * secs / max_secs)) if max_secs else 1
        scr.text(y, x, truncate(name, label_w - 1))
        scr.text(y, x + label_w, make_bar(filled, BAR_TIME_W), STYLE_DIM)
        scr.text(y, x + label_w + BAR_TIME_W + 1, format_hours(secs), STYLE_BOLD)
        y += 1
    scr.text(y, x + w - 6, format_hours(sum(secs for _, secs in totals)))
    return y + 2


def render_dashboard(scr, state):
    col_x = int(scr.width * COLUMN_RATIO)
    left_w = col_x - COLUMN_PAD
    right_w = scr.width - col_x - COLUMN_PAD - 1
    scr.vline(col_x, 2)

    y = render_active(scr, 2, 1, left_w, state.timer, state.active_tasks)
    render_next(scr, y + 1, 1, left_w, select_next(state))

    today = datetime.now().date()
    week = state.time_week
    todays = [e for e in week if (s := parse_timestamp(e.get("start"))) and s.astimezone().date() == today]
    rx = col_x + COLUMN_PAD
    y = render_projects(scr, 2, rx, right_w, summarize_projects(state.tasks), scr.height // 2 + 1)
    y = render_time(scr, y + 1, rx, right_w, "TODAY", aggregate_time(todays))
    render_time(scr, y + 1, rx, right_w, "THIS WEEK", aggregate_time(week))


# -----------------------------------------------------------------------------
# INTERNAL: TUI line tabs
# -----------------------------------------------------------------------------


def lines_task_table(tasks):
    if not tasks:
        return [("  No tasks in this category.", STYLE_DIM)]
    lines = [(TASK_ROW_FMT.format("ID", "PRI", "URG", "PROJECT", "DESCRIPTION"), STYLE_DIM)]
    for t in tasks:
        tags = f" [{','.join(t['tags'])}]" if t.get("tags") else ""
        row = TASK_ROW_FMT.format(
            t.get("id", 0), t.get("priority") or "-", f"{t.get('urgency', 0):.1f}",
            truncate(t.get("project") or "-", 14), one_line(t.get("description", "")) + tags,
        )
        lines.append((row, priority_style(t)))
    return lines


def lines_agent_items(items):
    if not items:
        return [("  (none)", STYLE_DIM)]
    lines = []
    for project, task_id, desc, link in items:
        lines.append((f"  {project} #{task_id} {desc}", STYLE_BOLD))
        lines.append((f"      -> {link or '(none annotated)'}", STYLE_DIM))
    return lines


def lines_due(tasks, label, describe):
    lines = [(label, STYLE_BOLD)]
    for t in tasks:
        lines.append((f"  #{t.get('id', 0):<4} {describe(t):>10}  {one_line(t.get('description', ''))}", priority_style(t)))
    if not tasks:
        lines.append(("  (none)", STYLE_DIM))
    return lines + [("", STYLE_NORMAL)]


def build_tab_lines(state, tab):
    pending = [t for t in state.tasks if t.get("status") == "pending"]
    if tab == TAB_REVIEW:
        return ([("TASKS NEEDING REVIEW", STYLE_BOLD)]
                + lines_task_table([t for t in pending if has_tag_word(t, REVIEW_TAG_WORDS)])
                + [("", STYLE_NORMAL), ("AGENT PRS AWAITING REVIEW", STYLE_BOLD)]
                + lines_agent_items(agent_items(state, "review")))
    if tab == TAB_CLARIFY:
        return ([("TASKS NEEDING CLARIFICATION (needs human input)", STYLE_BOLD)]
                + lines_task_table([t for t in pending if has_tag_word(t, CLARIFY_TAG_WORDS)])
                + [("", STYLE_NORMAL), ("AGENT TICKETS NEEDING YOU", STYLE_BOLD)]
                + lines_agent_items(agent_items(state, "clarify")))
    if tab == TAB_DUE:
        return (lines_due(select_by_due_day(state.tasks, lambda due, today: due < today), "OVERDUE", format_due_relative)
                + lines_due(select_by_due_day(state.tasks, lambda due, today: due == today), "DUE TODAY", format_due_relative)
                + lines_due(select_aging(state.tasks), "AGING (oldest pending)", format_age))
    if tab == TAB_GITHUB:
        issues = select_github_issues(state.tasks)
        return [("GITHUB ISSUES (bugwarrior)", STYLE_BOLD)] + (lines_github(issues, len(issues)) or [("  (none)", STYLE_DIM)])
    if tab == TAB_AGENTS:
        return [("AGENT FLOW (per project)", STYLE_BOLD)] + lines_agent_flow(state.agent_projects)
    lines = [(line, STYLE_NORMAL) for line in state.burndown.splitlines()]
    return [("BURNDOWN (daily)", STYLE_BOLD)] + (lines or [("  (none)", STYLE_DIM)])


def render_lines(scr, lines, scroll):
    visible = scr.height - 3
    scroll = max(0, min(scroll, len(lines) - visible))
    for i, (text, style) in enumerate(lines[scroll:scroll + visible]):
        scr.text(2 + i, 1, text, style)
    return scroll


# -----------------------------------------------------------------------------
# INTERNAL: TUI layout + loop
# -----------------------------------------------------------------------------


def render_tabs(scr, state, active_tab):
    x = 1
    for i, name in enumerate(TABS):
        count = count_tab(state, i)
        label = f" {i + 1}:{name}" + (f" ({count}) " if count is not None else " ")
        scr.text(0, x, label, STYLE_REVERSE if i == active_tab else STYLE_DIM)
        x += len(label) + 1
    scr.text(1, 0, "-" * (scr.width - 1), STYLE_DIM)


def render(scr, state, tab, scroll):
    scr.erase()
    if scr.height < MIN_HEIGHT or scr.width < MIN_WIDTH:
        scr.text(0, 0, "terminal too small", STYLE_BOLD)
        return scroll

    render_tabs(scr, state, tab)
    if tab == TAB_DASHBOARD:
        render_dashboard(scr, state)
    else:
        scroll = render_lines(scr, build_tab_lines(state, tab), scroll)
    updated = f"  updated {state.updated} "
    room = scr.width - 1 - len(FOOTER_KEYS)
    scr.footer(FOOTER_KEYS + (updated.rjust(room) if room >= len(updated) else ""))
    return scroll


def run_tui(win):
    scr = Screen(win)
    env = human_env()
    agent_mod = load_agent_module()
    state = State()
    tab, scroll = TAB_DASHBOARD, 0

    while True:
        now = time.monotonic()
        if now - state.slow_at >= SLOW_REFRESH_S:
            scr.footer(" refreshing...")
            win.refresh()
            refresh_slow(state, env, agent_mod)
        if now - state.fast_at >= FAST_REFRESH_S:
            refresh_fast(state, env)
        scroll = render(scr, state, tab, scroll)
        win.refresh()

        ch = win.getch()
        if ch in (ord("q"), ord("Q"), KEY_ESC):
            break
        if ch == ord("r"):
            state.slow_at = state.fast_at = float("-inf")
        elif ch == curses.KEY_RESIZE:
            win.clear()
        elif ord("1") <= ch < ord("1") + len(TABS):
            tab, scroll = ch - ord("1"), 0
        elif ch in (KEY_TAB, curses.KEY_RIGHT, ord("l")):
            tab, scroll = (tab + 1) % len(TABS), 0
        elif ch in (curses.KEY_BTAB, curses.KEY_LEFT, ord("h")):
            tab, scroll = (tab - 1) % len(TABS), 0
        elif ch in (curses.KEY_DOWN, ord("j")):
            scroll += 1
        elif ch in (curses.KEY_UP, ord("k")):
            scroll = max(0, scroll - 1)


# -----------------------------------------------------------------------------
# FUNCTIONS
# -----------------------------------------------------------------------------


def main():
    args = sys.argv[1:]
    paged = "--page" in args or "-p" in args
    if "--print" in args or paged or not sys.stdout.isatty():
        print_page(paged)
        return
    try:
        curses.wrapper(run_tui)
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
