#!/usr/bin/env python3
"""Single human-facing task dashboard across the whole ecosystem:
taskwarrior + timewarrior + bugwarrior (GitHub issues) + the
l-agent-task-db agent flow.

Read-only: never modifies any db. Always targets the HUMAN taskwarrior db
(~/.taskrc), unsetting any agent TASKDATA/TIMEWARRIORDB so it still works
inside a project whose direnv/devenv exported an agent TASKRC.

Sections: what's being worked right now (active timers + active tasks),
overdue / due today / upcoming / aging, GitHub issues pulled in by
bugwarrior, project summary, burndown, time this week, and a per-project
summary of the agent task dbs under ~/projects (stages, and anything
waiting on you).

Each system is optional: a missing timew/bugwarrior/agent-db degrades to
"(none)" rather than erroring.

Usage: task-dashboard [--page|-p]
"""
import glob
import importlib.util
import os
import shutil
import subprocess
import sys
from collections import Counter

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
# INTERNAL: output styling (gum when present, plain fallback)
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


# -----------------------------------------------------------------------------
# INTERNAL: taskwarrior / timewarrior human reports
# -----------------------------------------------------------------------------


def task_report(env, *args):
    """A taskwarrior report with colour forced through the capture pipe."""
    return run(["task", "rc.verbose=nothing", "rc._forcecolor=on", *args], env=env)


def section_active(page, env):
    page.heading("ACTIVE (being worked now)")
    body = []
    if have("timew"):
        timers = run(["timew"], env=env)
        body.append(timers if timers else "  (no active timer)")
    active = task_report(env, "+ACTIVE")
    if active:
        body.append(active)
    page.raw("\n".join(body) if any(b.strip() for b in body) else "  (none)")


def section_github(page, export_json):
    """GitHub issues pulled into the human db by bugwarrior, surfaced on
    their own. Identified by the githuburl UDA (definitive) or +github tag."""
    def is_bw(t):
        return t.get(BUGWARRIOR_UDA) or BUGWARRIOR_TAG in t.get("tags", [])

    issues = [t for t in export_json if t.get("status") == "pending" and is_bw(t)]
    issues.sort(key=lambda t: (t.get("project", ""), t.get("githubnumber") or 0))
    lines = []
    for t in issues[:GITHUB_LIMIT]:
        repo = t.get("githubrepo") or t.get("project") or "-"
        num = t.get("githubnumber")
        ref = f"{repo}#{int(num)}" if num else repo
        title = (t.get("githubtitle") or t.get("description") or "").strip()
        lines.append(f"  #{t['id']:<4} {ref:<28} {title}")
    if len(issues) > GITHUB_LIMIT:
        lines.append(f"  ... and {len(issues) - GITHUB_LIMIT} more")
    page.section("GITHUB ISSUES (bugwarrior)", "\n".join(lines))


# -----------------------------------------------------------------------------
# INTERNAL: agent task-db flow summary
# -----------------------------------------------------------------------------


def classify_gated(agent_mod, agent_tasks):
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


def section_agent_flow(page, agent_mod):
    page.heading("AGENT FLOW (per project)")
    if agent_mod is None:
        page.raw("  (agent task-db module not found)")
        return

    dbs = sorted(glob.glob(AGENT_DB_GLOB))
    if not dbs:
        page.raw("  (no agent task dbs under ~/projects)")
        return

    for taskrc in dbs:
        root = os.path.dirname(os.path.dirname(taskrc))
        name = os.path.basename(root)
        try:
            all_tasks = agent_mod.load_all_tasks(taskrc)
        except Exception:
            page.raw(f"  {name}: (unreadable db)")
            continue

        agent_tasks = [t for t in all_tasks if t.get("status") == "pending"
                       and "agent-task" in t.get("tags", [])]
        if not agent_tasks:
            page.raw(f"  {name}: (no open agent tickets)")
            continue

        stages = Counter(agent_mod.stage_of(t) for t in agent_tasks)
        stage_str = " ".join(f"{s}:{n}" for s, n in sorted(stages.items()))
        page.raw(f"  {name}: {len(agent_tasks)} open  [{stage_str}]")

        clarify, review, answered = classify_gated(agent_mod, agent_tasks)
        # "needs human input" is the human's cue: make it prominent.
        for t in clarify:
            qf = agent_mod.question_file(t, root)
            page.raw(f"      NEEDS YOU: #{t['id']} {agent_mod.one_line(t['description'])}")
            if qf:
                page.raw(f"                 -> {qf}")
        for t in review:
            page.raw(f"      REVIEW PR: #{t['id']} {agent_mod.one_line(t['description'])}")
            page.raw(f"                 -> {agent_mod.pr_link(t) or '(no PR annotated)'}")
        if answered:
            page.raw(f"      ({len(answered)} answered, awaiting agent)")


# -----------------------------------------------------------------------------
# FUNCTIONS
# -----------------------------------------------------------------------------


def build_page():
    import json
    from datetime import datetime

    page = Page()
    env = human_env()

    page.banner(f"TASK DASHBOARD // {datetime.now():%Y-%m-%d %H:%M}")

    if not have("task"):
        page.raw("  taskwarrior not installed")
        return page.render()

    export_raw = run(["task", "rc.verbose=nothing", "export"], env=env)
    try:
        export_json = json.loads(export_raw) if export_raw.strip() else []
    except (json.JSONDecodeError, ValueError):
        export_json = []

    section_active(page, env)
    page.section("OVERDUE", task_report(env, "+OVERDUE"))
    page.section("DUE TODAY", task_report(env, "due:today"))
    page.section("UPCOMING (ready)", task_report(env, f"limit:{READY_LIMIT}", "ready"))
    page.section("AGING (oldest pending)", task_report(env, f"limit:{AGING_LIMIT}", "aging"))
    section_github(page, export_json)
    page.section("PROJECTS", task_report(env, "summary"))
    page.section("BURNDOWN (daily)", task_report(env, "burndown.daily"))

    if have("timew"):
        page.section("TIME THIS WEEK", run(["timew", "summary", ":week"], env=env))

    section_agent_flow(page, load_agent_module())
    return page.render()


def main():
    text = build_page()
    paged = len(sys.argv) > 1 and sys.argv[1] in ("--page", "-p")
    if paged and have("less") and sys.stdout.isatty():
        proc = subprocess.Popen(["less", "-R"], stdin=subprocess.PIPE, text=True)
        try:
            proc.communicate(text)
        except BrokenPipeError:
            pass
    else:
        sys.stdout.write(text)


if __name__ == "__main__":
    main()
