#!/usr/bin/env python3

import json
import re
from pathlib import Path
from urllib.parse import urlparse

BIN = Path.home() / ".local/bin"
ERROR_MSG = """
Invalid format: {0}.
Expected `<url>` or `<url> as <name>`.
Name has to match /^[a-zA-Z0-9-_]+$/.
"""

links = []
BIN.mkdir(parents=True, exist_ok=True)
with open("./links.txt", "r") as file:
    for line in file:
        line = line.strip()
        parts = [p.strip() for p in line.split(" ") if p.strip()]

        if len(parts) == 1:
            url = parts[0]

            try:
                exec_name = urlparse(url).hostname
            except ValueError as err:
                raise Exception(ERROR_MSG.format(line)) from err
            if exec_name is None:
                raise Exception(ERROR_MSG.format(line))

            exec_name = re.sub(r".\w+(?=$)", "", exec_name)
        elif len(parts) == 3:
            url = parts[0]
            exec_name = parts[2]

            try:
                urlparse(url)
            except ValueError as err:
                raise Exception(ERROR_MSG.format(line)) from err

            if parts[1] != "as":
                raise Exception(ERROR_MSG.format(line))

            if not re.match(r"^[a-zA-Z0-9-_]+$", exec_name):
                raise Exception(ERROR_MSG.format(line))
        else:
            raise Exception(ERROR_MSG.format(line))

        # exec_name becomes a file and symlink name
        if not re.match(r"^[a-zA-Z0-9-_]+$", exec_name):
            raise Exception(ERROR_MSG.format(line))

        script = Path("./collection") / f"{exec_name}.sh"
        script.write_text(f"#!/bin/sh\nxdg-open {url}\nexit 0\n")
        script.chmod(0o755)
        link = BIN / exec_name
        link.unlink(missing_ok=True)
        link.symlink_to(script.resolve())

        links.append({"name": exec_name, "url": url})
        print(f"Created executable {exec_name} for {url}.")

# the browser start pages render these as bookmarks
Path("./collection/links.js").write_text(f"const weblinks = {json.dumps(links)};\n")
print(f"Wrote {len(links)} links to collection/links.js.")
