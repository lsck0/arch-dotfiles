#!/usr/bin/env python3
"""Revert spicetify class renames the spotify js no longer emits (spotify >= 1.2.96)."""

import json
import re
import sys
import zipfile
from pathlib import Path

XPUI = Path("/opt/spotify/Apps/xpui")
CSS_MAP = Path("/opt/spicetify-cli/css-map.json")
BACKUP = Path.home() / ".local/state/spicetify/Backup/xpui.spa"
SKIP = {"user.css", "colors.css"}

PRELUDE = re.compile(r"(^|[};])([^{};]+)\{")


def preludes(css):
    """Yield (start, end) spans of every selector/at-rule prelude in `css`."""
    for m in PRELUDE.finditer(css):
        yield m.start(2), m.end(2)


def main() -> int:
    for path in (XPUI, CSS_MAP, BACKUP):
        if not path.exists():
            print(f"spicetify-unmap-classes: {path} missing, nothing to do", file=sys.stderr)
            return 0

    css_map = json.loads(CSS_MAP.read_text())
    rename = re.compile(
        r"(?<![-\w])(" + "|".join(re.escape(h) for h in sorted(css_map, key=len, reverse=True)) + r")(?![-\w])"
    )

    with zipfile.ZipFile(BACKUP) as spa:
        pristine = {
            Path(n).name: spa.read(n).decode("utf-8", "replace")
            for n in spa.namelist()
            if n.endswith(".css")
        }
        scripts = "\n".join(
            spa.read(n).decode("utf-8", "replace") for n in spa.namelist() if n.endswith(".js")
        )

    keep = {h: f for h, f in css_map.items() if h in scripts}

    restored = files = 0
    for css in sorted(XPUI.glob("*.css")):
        if css.name in SKIP or css.name not in pristine:
            continue

        # patched selector -> original selector
        original = {}
        source = pristine[css.name]
        for start, end in preludes(source):
            sel = source[start:end]
            if not sel.lstrip().startswith("@"):
                patched_sel = rename.sub(lambda m: css_map[m.group(1)], sel)
                wanted = rename.sub(lambda m: keep.get(m.group(1), m.group(1)), sel)
                original.setdefault(patched_sel, wanted)

        text = css.read_text(encoding="utf-8", errors="surrogateescape")
        out, last, count = [], 0, 0
        for start, end in preludes(text):
            sel = text[start:end]
            fixed = original.get(sel)
            if fixed is None or fixed == sel:
                continue
            out.append(text[last:start])
            out.append(fixed)
            last, count = end, count + 1

        if count:
            out.append(text[last:])
            css.write_text("".join(out), encoding="utf-8", errors="surrogateescape")
            restored += count
            files += 1

    print(f"spicetify-unmap-classes: restored {restored} selectors in {files} files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
