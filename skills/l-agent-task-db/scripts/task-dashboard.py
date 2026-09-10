#!/usr/bin/env python3
"""Human-facing view of an l-agent-task-db taskwarrior instance: exactly
what's queued, what stage every ticket is in, and what needs the human's
input right now. Read-only — never modifies the db.

Usage: task-dashboard.py [project-dir]   (defaults to $PWD)
Resolution order for the taskrc: <project-dir>/tasks/.taskrc if a
project-dir arg was given, else $TASKRC if set, else ./tasks/.taskrc.
"""
import json
import os
import shutil
import subprocess
import sys
from collections import defaultdict

RECENT_COMPLETED_LIMIT = 10
DESC_MAX_CHARS = 50


def find_taskrc():
    if len(sys.argv) > 1:
        path = os.path.join(sys.argv[1], "tasks", ".taskrc")
        if os.path.isfile(path):
            return os.path.abspath(path)
        sys.exit(f"error: no {path}")
    env = os.environ.get("TASKRC")
    if env and os.path.isfile(env):
        return env
    path = os.path.join("tasks", ".taskrc")
    if os.path.isfile(path):
        return os.path.abspath(path)
    sys.exit(
        "error: no tasks/.taskrc found (pass a project-dir, or cd into one "
        "with direnv/devenv active)."
    )


def load_all_tasks(taskrc):
    env = dict(os.environ, TASKRC=taskrc)
    out = subprocess.run(
        ["task", "rc.verbose=nothing", "export"],
        env=env, capture_output=True, text=True, check=True,
    ).stdout
    return json.loads(out) if out.strip() else []


def stage_of(task):
    for t in task.get("tags", []):
        if t.startswith("stage-"):
            return t[len("stage-"):]
    return "-"


def question_file(task):
    for a in task.get("annotations", []):
        desc = a.get("description", "")
        if "tasks/context/questions/" in desc:
            return desc.split("context: ", 1)[-1]
    return None


def blocked_by(task, by_uuid):
    open_deps = []
    for dep_uuid in task.get("depends", []):
        dep = by_uuid.get(dep_uuid)
        if dep and dep.get("status") not in ("completed", "deleted"):
            open_deps.append(dep)
    return open_deps


def one_line(description):
    """Collapse whitespace/newlines to one line and cap length so a long
    or multi-line description (e.g. a nvim :LPromptBuffer prompt) never
    overflows the dashboard's aligned layout."""
    text = " ".join(description.split())
    if len(text) > DESC_MAX_CHARS:
        text = text[:DESC_MAX_CHARS - 1].rstrip() + "…"
    return text


def fmt(task):
    return f"#{task['id']:<4} {one_line(task['description'])}"


def clip(line, width):
    """Hard-clip an already-assembled line to the terminal width so a
    narrow pane (e.g. Herdr) never wraps mid-word into a garbled,
    pipe-fenced mess — one line in, one line out, always."""
    if len(line) <= width:
        return line
    return line[: max(width - 1, 0)].rstrip() + "…"


def main():
    taskrc = find_taskrc()
    all_tasks = load_all_tasks(taskrc)
    by_uuid = {t["uuid"]: t for t in all_tasks}
    color = sys.stdout.isatty()
    width = shutil.get_terminal_size(fallback=(100, 24)).columns

    def out(line):
        print(clip(line, width))

    def hdr(title, n):
        line = f"\n{title} ({n})"
        return f"\033[1m{line}\033[0m" if color else line

    pending = [t for t in all_tasks if t.get("status") == "pending"]
    prompts = [t for t in pending if "prompt" in t.get("tags", [])
               and "agent-task" not in t.get("tags", [])]
    agent = [t for t in pending if "agent-task" in t.get("tags", [])]

    needs_clarification = [t for t in agent if "human-clarification-needed" in t.get("tags", [])]
    needs_review = [t for t in agent if "human-review-ready" in t.get("tags", [])]
    blocking = needs_clarification + needs_review
    active = [t for t in agent if t.get("start") and t not in blocking]
    blocked = [t for t in agent if t not in blocking and t not in active
               and blocked_by(t, by_uuid)]
    ready = [t for t in agent if t not in blocking and t not in active
             and t not in blocked]
    recent_done = sorted(
        (t for t in all_tasks if t.get("status") == "completed"
         and "agent-task" in t.get("tags", [])),
        key=lambda t: t.get("end", ""), reverse=True,
    )[:RECENT_COMPLETED_LIMIT]

    print(f"=== task db: {os.path.dirname(os.path.dirname(taskrc))} ===")

    print(hdr("PROMPTS awaiting decomposition", len(prompts)))
    for t in prompts:
        out(f"  {fmt(t)}")
    if not prompts:
        print("  (none)")

    print(hdr("NEEDS CLARIFICATION", len(needs_clarification)))
    for t in needs_clarification:
        qf = question_file(t)
        out(f"  {fmt(t)}  [{t.get('project', '-')}] [{stage_of(t)}]")
        if qf:
            out(f"        -> {qf}")

    print(hdr("SPEC READY FOR YOUR REVIEW", len(needs_review)))
    for t in needs_review:
        out(f"  {fmt(t)}  [{t.get('project', '-')}] [{stage_of(t)}]")

    print(hdr("IN PROGRESS", len(active)))
    for t in active:
        out(f"  {fmt(t)}  [{t.get('project', '-')}] [{stage_of(t)}]  (started {t['start']})")

    print(hdr("READY (queued, unblocked)", len(ready)))
    by_project = defaultdict(list)
    for t in ready:
        by_project[t.get("project", "(no project)")].append(t)
    for proj in sorted(by_project):
        for t in by_project[proj]:
            out(f"  {fmt(t)}  [{proj}] [{stage_of(t)}]")

    print(hdr("BLOCKED (dependency not done)", len(blocked)))
    for t in blocked:
        deps = ", ".join(
            f"#{d['id']} {one_line(d['description'])}"
            for d in blocked_by(t, by_uuid)
        )
        out(f"  {fmt(t)}  [{t.get('project', '-')}] [{stage_of(t)}]")
        out(f"        waiting on: {deps}")

    print(hdr(f"COMPLETED (last {RECENT_COMPLETED_LIMIT})", len(recent_done)))
    for t in recent_done:
        out(f"  {one_line(t['description'])}  [{t.get('project', '-')}]  {t.get('end', '')}")


if __name__ == "__main__":
    main()
